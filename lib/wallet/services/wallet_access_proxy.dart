import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:solana/base58.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart' hide Wallet;

import '../../data/lock_service.dart';
import '../state/app_state.dart';
import 'wallet_service.dart';

/// Outcome of a wallet operation exposed to mini-apps.
class WalletOperationResult {
  const WalletOperationResult({
    required this.source,
    required this.publicKey,
    this.signature,
    this.signedTransaction,
    this.warnings = const [],
  });

  /// Where the operation was performed: `walletconnect` or `builtin`.
  final String source;

  /// Base58 public key performing the operation.
  final String publicKey;

  /// Base58 signature / transaction id when applicable.
  final String? signature;

  /// Base64-encoded fully-signed transaction (built-in path only).
  final String? signedTransaction;

  /// Human-readable warnings surfaced to the client.
  final List<String> warnings;

  Map<String, dynamic> toJson() => {
        'source': source,
        'publicKey': publicKey,
        if (signature != null) 'signature': signature,
        if (signedTransaction != null) 'signedTransaction': signedTransaction,
        if (warnings.isNotEmpty) 'warnings': warnings,
      };
}

/// Info about the wallet currently bound to the messenger profile.
class WalletBindingInfo {
  const WalletBindingInfo({
    required this.bound,
    required this.source,
    this.publicKey,
    this.peerName,
  });

  final bool bound;
  final String source;
  final String? publicKey;
  final String? peerName;

  Map<String, dynamic> toJson() => {
        'bound': bound,
        'source': source,
        if (publicKey != null) 'publicKey': publicKey,
        if (peerName != null) 'peerName': peerName,
      };
}

/// A small description of one instruction found inside a transaction.
class _InstructionSummary {
  const _InstructionSummary({
    required this.programId,
    required this.label,
    required this.risk,
  });

  final String programId;
  final String label;

  /// 0 = ok, 1 = warn, 2 = danger.
  final int risk;
}

/// Thrown when a wallet operation cannot be performed or is rejected.
class WalletAccessException implements Exception {
  const WalletAccessException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Single entry point that gives mini-apps mediated access to the wallet.
///
/// The mini app never touches private keys or the WalletConnect session
/// directly: every request is routed here, the user confirms (built-in wallet)
/// or the external WalletConnect wallet signs, and only non-secret results are
/// returned to the mini app.
class WalletAccessProxy {
  const WalletAccessProxy();

  static const String builtinProgramId = '11111111111111111111111111111111';
  static const String tokenProgram =
      'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';
  static const String token2022Program =
      'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
  static const String memoProgram =
      'MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr';
  static const String computeBudgetProgram =
      'ComputeBudget111111111111111111111111111111';

  /// Platform fee wallet that receives 0.5% of every SOL transfer built by
  /// `paySolana` / `_buildSolTransferTx`.
  static const String feeWallet = 'C6P9WUg4maMmurtDNA63vxsVyDzrpPMgLjetNnLAP4LW';

  /// Fee rate (0.5%).
  static const double feeRate = 0.005;

  AppState get _state => AppState.instance;

  /// Requires biometric or PIN authentication before proceeding with a transaction.
  /// Returns true if authenticated or no lock is set.
  Future<bool> _requireTransactionAuth(BuildContext context) async {
    final lock = LockService.instance;
    if (!lock.isEnabled) return true;
    if (lock.canUseBiometric) {
      return await lock.authenticateWithBiometric();
    }
    // For PIN-only, show a dialog
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтвердите транзакцию'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          obscureText: true,
          decoration: const InputDecoration(hintText: 'Введите PIN'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () async {
              final ok = await LockService.instance.verifyPin(controller.text);
              if (ctx.mounted) Navigator.pop(ctx, ok);
            },
            child: const Text('Подтвердить'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result ?? false;
  }

  /// Returns which wallet is bound to the profile (no secrets).
  Future<WalletBindingInfo> getBinding() async {
    final state = _state;
    final wc = state.walletConnectSession;
    final builtin = state.wallet;
    if (wc != null && wc.primaryAccount != null) {
      return WalletBindingInfo(
        bound: true,
        source: 'walletconnect',
        publicKey: wc.primaryAccount,
        peerName: wc.peerName,
      );
    }
    if (builtin != null) {
      return WalletBindingInfo(
        bound: true,
        source: 'builtin',
        publicKey: builtin.address,
      );
    }
    return const WalletBindingInfo(bound: false, source: 'none');
  }

  /// Requests the wallet to sign [message] bytes.
  Future<WalletOperationResult> signMessage(
    BuildContext context, {
    required List<int> message,
  }) async {
    final authenticated = await _requireTransactionAuth(context);
    if (!authenticated) throw const WalletAccessException('Transaction cancelled');

    final state = _state;
    final wc = state.walletConnectClient;
    final wcSession = state.walletConnectSession;
    if (wc != null && wcSession != null && wcSession.primaryAccount != null) {
      final result = await wc.signMessage(Uint8List.fromList(message));
      return WalletOperationResult(
        source: 'walletconnect',
        publicKey: result.publicKey,
        signature: base58Encode(result.signature),
      );
    }

    final wallet = state.wallet;
    if (wallet == null) {
      throw const WalletAccessException('No wallet connected');
    }

    final confirmed = await _confirmMessageDialog(context, message);
    if (!confirmed) {
      throw const WalletAccessException('Rejected by user');
    }
    final signature = await wallet.keyPair.sign(Uint8List.fromList(message));
    return WalletOperationResult(
      source: 'builtin',
      publicKey: wallet.address,
      signature: base58Encode(signature.bytes),
    );
  }

  /// Signs a base58-serialized Solana transaction and returns the signature
  /// plus a fully-signed transaction (built-in path).
  Future<WalletOperationResult> signTransaction(
    BuildContext context, {
    required String transaction,
  }) async {
    final authenticated = await _requireTransactionAuth(context);
    if (!authenticated) throw const WalletAccessException('Transaction cancelled');

    final state = _state;
    final wc = state.walletConnectClient;
    final wcSession = state.walletConnectSession;
    if (wc != null && wcSession != null && wcSession.primaryAccount != null) {
      final result = await wc.signTransaction(transaction);
      return WalletOperationResult(
        source: 'walletconnect',
        publicKey: result.publicKey,
        signature: result.signature,
      );
    }

    final wallet = state.wallet;
    if (wallet == null) {
      throw const WalletAccessException('No wallet connected');
    }

    final signed = await _signAndConfirmTransaction(context, transaction, wallet);
    return WalletOperationResult(
      source: 'builtin',
      publicKey: wallet.address,
      signedTransaction: signed.encode(),
    );
  }

  /// Signs a transaction with the built-in wallet and submits it, returning a
  /// transaction id.
  Future<WalletOperationResult> signAndSendTransaction(
    BuildContext context, {
    required String transaction,
  }) async {
    final authenticated = await _requireTransactionAuth(context);
    if (!authenticated) throw const WalletAccessException('Transaction cancelled');

    final state = _state;
    final wc = state.walletConnectClient;
    final wcSession = state.walletConnectSession;
    if (wc != null && wcSession != null && wcSession.primaryAccount != null) {
      try {
        final result = await wc.signAndSendTransaction(transaction);
        return WalletOperationResult(
          source: 'walletconnect',
          publicKey: result.publicKey,
          signature: result.signature,
        );
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('not supported') || msg.contains('notSupported')) {
          final signedResult = await wc.signTransaction(transaction);
          final signedBytes = base58decode(signedResult.signature);
          final txid = await state.solana.client.rpcClient.sendTransaction(
            base64Encode(signedBytes),
            preflightCommitment: Commitment.confirmed,
          );
          return WalletOperationResult(
            source: 'walletconnect',
            publicKey: signedResult.publicKey,
            signature: txid,
          );
        }
        rethrow;
      }
    }

    final wallet = state.wallet;
    if (wallet == null) {
      throw const WalletAccessException('No wallet connected');
    }

    final signed = await _signAndConfirmTransaction(context, transaction, wallet);
    final txid = await state.solana.client.rpcClient.sendTransaction(
      signed.encode(),
      preflightCommitment: Commitment.confirmed,
    );
    return WalletOperationResult(
      source: 'builtin',
      publicKey: wallet.address,
      signature: txid,
    );
  }

  /// High-level "send [lamports] SOL to [recipient]" helper used both by the
  /// mini-app `MINIAPP_SOLANA_PAYMENT` handler and by the chat invoice card's
  /// "Оплатить" button. Builds a System Program transfer with the currently
  /// bound wallet as the fee payer/signer and routes it through Phantom/Reown
  /// (when connected) or the built-in wallet. Throws [WalletAccessException]
  /// when no wallet is bound.
  Future<WalletOperationResult> paySolana(
    BuildContext context, {
    required String recipient,
    required int lamports,
    String? memo,
  }) async {
    final authenticated = await _requireTransactionAuth(context);
    if (!authenticated) throw const WalletAccessException('Transaction cancelled');

    final binding = await getBinding();

    // Try Phantom/WalletConnect first when a session is active.
    if (binding.bound &&
        binding.publicKey != null &&
        binding.source == 'walletconnect') {
      try {
        final transaction = await _buildSolTransferTx(
          sender: binding.publicKey!,
          recipient: recipient,
          lamports: lamports,
          memo: memo,
        );
        final wcClient = _state.walletConnectClient;
        try {
          final signedResult = await wcClient!.signTransaction(transaction);
          final signedBytes = base58decode(signedResult.signature);
          final txid = await _state.solana.client.rpcClient.sendTransaction(
            base64Encode(signedBytes),
            preflightCommitment: Commitment.confirmed,
          );
          return WalletOperationResult(
            source: 'walletconnect',
            publicKey: signedResult.publicKey,
            signature: txid,
          );
        } catch (signErr) {
          final result =
              await signAndSendTransaction(context, transaction: transaction);
          return result;
        }
      } catch (_) {
        // Fall through to built-in wallet — handles session-key mismatches,
        // cluster issues, unsupported methods, any Phantom flakiness.
      }
    }

    // Built-in wallet.
    final wallet = _state.wallet;
    if (wallet == null) {
      throw const WalletAccessException('No wallet connected');
    }
    final transaction = await _buildSolTransferTx(
      sender: wallet.address,
      recipient: recipient,
      lamports: lamports,
      memo: memo,
    );
    final result =
        await signAndSendTransaction(context, transaction: transaction);
    return result;
  }

  /// Builds a base58-serialized unsigned System Program transfer transaction
  /// with [sender] as the fee payer/signer, [recipient] as destination and
  /// [lamports] as the amount. The connected wallet (Phantom/Reown or the
  /// built-in keypair via [signAndSendTransaction]) fills the signature.
  Future<String> _buildSolTransferTx({
    required String sender,
    required String recipient,
    required int lamports,
    String? memo,
  }) async {
    final rpc = _state.solana.client.rpcClient;
    final blockhashResult = await rpc.getLatestBlockhash(
      commitment: Commitment.confirmed,
    );
    final recentBlockhash = blockhashResult.value.blockhash;

    final senderKey = Ed25519HDPublicKey.fromBase58(sender);
    final recipientKey = Ed25519HDPublicKey.fromBase58(recipient);

    // 0.5% platform fee routed to the fee wallet in the same transaction.
    final feeLamports = (lamports * feeRate).round();

    final instructions = <Instruction>[
      SystemInstruction.transfer(
        fundingAccount: senderKey,
        recipientAccount: recipientKey,
        lamports: lamports,
      ),
      if (feeLamports > 0)
        SystemInstruction.transfer(
          fundingAccount: senderKey,
          recipientAccount: Ed25519HDPublicKey.fromBase58(feeWallet),
          lamports: feeLamports,
        ),
      if (memo != null && memo.isNotEmpty)
        MemoInstruction(signers: [senderKey], memo: memo),
    ];

    final message = Message(instructions: instructions);
    final compiled = message.compile(
      recentBlockhash: recentBlockhash,
      feePayer: senderKey,
    );

    final placeholder = Signature(
      List<int>.filled(64, 0),
      publicKey: senderKey,
    );
    final signed = SignedTx(
      compiledMessage: compiled,
      signatures: [placeholder],
    );
    return base58encode(signed.toByteArray().toList());
  }

  // ── Internal ─────────────────────────────────────────────────────────

  /// Decodes, analyzes, confirms with the user and signs a serialized
  /// transaction with the built-in wallet.
  Future<SignedTx> _signAndConfirmTransaction(
    BuildContext context,
    String transaction,
    Wallet wallet,
  ) async {
    final decoded = _decodeSignedTx(transaction);
    final summaries = _analyze(decoded);
    final feeLamports = await _feeLamports(decoded);
    final confirmed = await _confirmTransactionDialog(
      context,
      summaries: summaries,
      feeLamports: feeLamports,
    );
    if (!confirmed) {
      throw const WalletAccessException('Rejected by user');
    }
    return _signBuiltin(decoded, wallet);
  }

  /// Replaces the placeholder signature at our signer slot.
  Future<SignedTx> _signBuiltin(SignedTx decoded, Wallet wallet) async {
    final message = decoded.compiledMessage.toByteArray();
    final signature = await wallet.keyPair.sign(message.toList());

    final signatures = decoded.signatures.toList();
    final walletPub = Ed25519HDPublicKey.fromBase58(wallet.address);
    var replaced = false;
    for (var i = 0; i < signatures.length; i++) {
      if (_samePub(signatures[i].publicKey, walletPub)) {
        signatures[i] = Signature(signature.bytes, publicKey: walletPub);
        replaced = true;
        break;
      }
    }
    if (!replaced) {
      throw const WalletAccessException(
        'Transaction is not addressed to the connected wallet',
      );
    }
    return SignedTx(
      compiledMessage: decoded.compiledMessage,
      signatures: signatures,
    );
  }

  /// Decodes a base58- or base64-serialized transaction.
  SignedTx _decodeSignedTx(String transaction) {
    try {
      return SignedTx.fromBytes(base58Decode(transaction));
    } on FormatException {
      return SignedTx.decode(transaction);
    }
  }

  List<_InstructionSummary> _analyze(SignedTx tx) {
    final compiled = tx.compiledMessage;
    final instructions = Message.decompile(compiled).instructions;
    final walletAddr = _state.wallet?.address;
    return instructions.map((ix) {
      final program = ix.programId.toBase58();
      final accounts = ix.accounts.map((a) => a.pubKey.toBase58()).toList();
      final data = ix.data.toList();
      return _summarizeInstruction(program, accounts, data, walletAddr);
    }).toList();
  }

  _InstructionSummary _summarizeInstruction(
    String program,
    List<String> accounts,
    List<int> data,
    String? walletAddr,
  ) {
    switch (program) {
      case builtinProgramId:
        if (data.isNotEmpty && data[0] == 2) {
          final lamports = _u64le(data, 1);
          return _InstructionSummary(
            programId: program,
            label: 'Перевод SOL: ${lamports ?? '?'} лампортов',
            risk: 0,
          );
        }
        return const _InstructionSummary(
          programId: builtinProgramId,
          label: 'Системная операция',
          risk: 0,
        );
      case tokenProgram:
      case token2022Program:
        return _summarizeToken(program, accounts, data, walletAddr);
      case memoProgram:
        return const _InstructionSummary(
          programId: memoProgram,
          label: 'Заметка (memo)',
          risk: 0,
        );
      case computeBudgetProgram:
        return const _InstructionSummary(
          programId: computeBudgetProgram,
          label: 'Лимиты вычислений',
          risk: 0,
        );
      default:
        final risk = accounts.contains(walletAddr) ? 2 : 1;
        return _InstructionSummary(
          programId: program,
          label: 'Контракт: ${_short(program)}',
          risk: risk,
        );
    }
  }

  _InstructionSummary _summarizeToken(
    String program,
    List<String> accounts,
    List<int> data,
    String? walletAddr,
  ) {
    if (data.isEmpty) {
      return _InstructionSummary(
        programId: program,
        label: 'Token-операция',
        risk: accounts.contains(walletAddr) ? 1 : 0,
      );
    }
    const tokenOps = <int, String>{
      3: 'Перевод токена',
      9: 'Close аккаунта',
      12: 'Перевод (checked)',
      4: 'Approve (одобрение на списание)',
    };
    final op = data[0];
    final label = tokenOps[op];
    if (label == null) {
      return _InstructionSummary(
        programId: program,
        label: 'Token-операция #$op',
        risk: accounts.contains(walletAddr) ? 1 : 0,
      );
    }
    final amount = _u64le(data, 1);
    final risk = (op == 4 || op == 9) ? 2 : (accounts.contains(walletAddr) ? 1 : 0);
    var text = label;
    if (op == 3 || op == 4) text += ': ${amount ?? '?'}';
    return _InstructionSummary(programId: program, label: text, risk: risk);
  }

  /// Estimated network fee in lamports for the transaction message.
  Future<int?> _feeLamports(SignedTx tx) async {
    try {
      final bytes = tx.compiledMessage.toByteArray();
      final base64Msg = base64.encode(bytes.toList());
      return _state.solana.client.rpcClient.getFeeForMessage(
        base64Msg,
        commitment: Commitment.confirmed,
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> _confirmTransactionDialog(
    BuildContext context, {
    required List<_InstructionSummary> summaries,
    required int? feeLamports,
  }) async {
    final danger = summaries.where((s) => s.risk >= 2).toList();
    final feeText = feeLamports == null
        ? 'Комиссия сети: неизвестно'
        : 'Комиссия сети: ${(feeLamports / 1000000000).toStringAsFixed(6)} SOL';

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Подтверждение транзакции'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(feeText),
                  const SizedBox(height: 8),
                  ...summaries.map(
                    (s) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          _riskIcon(s.risk),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s.label)),
                        ],
                      ),
                    ),
                  ),
                  if (danger.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Внимание: в транзакции есть операции, которые могут '
                        'повлиять на безопасность ваших средств.',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(danger.isEmpty ? 'Подписать' : 'Всё равно подписать'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _riskIcon(int risk) {
    switch (risk) {
      case 2:
        return const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18);
      case 1:
        return const Icon(Icons.info_outline, color: Colors.orange, size: 18);
      default:
        return const Icon(Icons.check_circle_outline, color: Colors.green, size: 18);
    }
  }

  Future<bool> _confirmMessageDialog(
    BuildContext context,
    List<int> message,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Подпись сообщения'),
            content: Text(
              'Мини-апп запрашивает подпись сообщения кошельком '
              '(${message.length} байт).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Отмена'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Подписать'),
              ),
            ],
          ),
        ) ??
        false;
  }

  static bool _samePub(Object? a, Ed25519HDPublicKey b) {
    if (a is! Ed25519HDPublicKey) return false;
    final ba = a.bytes;
    final bb = b.bytes;
    if (ba.length != bb.length) return false;
    for (var i = 0; i < ba.length; i++) {
      if (ba[i] != bb[i]) return false;
    }
    return true;
  }

  static int? _u64le(List<int> data, int offset) {
    if (offset + 8 > data.length) return null;
    var value = BigInt.zero;
    for (var i = offset + 7; i >= offset; i--) {
      value = (value << 8) | BigInt.from(data[i]);
    }
    if (value > BigInt.from(0x7fffffffffffffff)) return null;
    return value.toInt();
  }

  static String _short(String value) => value.length <= 12
      ? value
      : '${value.substring(0, 6)}…${value.substring(value.length - 4)}';
}
