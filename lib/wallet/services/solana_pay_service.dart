import 'package:decimal/decimal.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart' hide Wallet;
import 'package:solana/solana_pay.dart';

import 'wallet_service.dart';

/// Parsed Solana Pay request ready for display and payment execution.
class SolanaPayInfo {
  SolanaPayInfo({
    required this.type,
    required this.recipient,
    this.amount,
    this.splToken,
    this.reference = const [],
    this.label,
    this.message,
    this.memo,
  });

  final SolanaPayType type;

  /// For [SolanaPayType.transfer]: the recipient base58 address.
  /// For [SolanaPayType.transactionRequest]: the merchant HTTPS link.
  final String recipient;

  final Decimal? amount;
  final String? splToken;
  final List<String> reference;
  final String? label;
  final String? message;
  final String? memo;
}

enum SolanaPayType {
  /// A direct `solana:` transfer request (spec v1).
  transfer,

  /// A merchant transaction request (spec v2) resolved over HTTPS.
  transactionRequest,
}

/// Wraps the `solana` package's built-in Solana Pay support with a simple
/// amount/recipient-oriented API used by the payment screen.
class SolanaPayService {
  SolanaPayService(this._client);

  final SolanaClient _client;

  /// Parses a `solana:` URL (or a plain https link for v2) into a
  /// [SolanaPayInfo]. Returns null if the URL is not a Solana Pay link.
  SolanaPayInfo? tryParse(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    final payRequest = SolanaPayRequest.tryParse(trimmed);
    if (payRequest != null) {
      return SolanaPayInfo(
        type: SolanaPayType.transfer,
        recipient: payRequest.recipient.toBase58(),
        amount: payRequest.amount,
        splToken: payRequest.splToken?.toBase58(),
        reference: (payRequest.reference ?? const [])
            .map((e) => e.toBase58())
            .toList(),
        label: payRequest.label,
        message: payRequest.message,
        memo: payRequest.memo,
      );
    }

    final txRequest =
        SolanaTransactionRequest.tryParse(trimmed) ??
        _legacyTransactionRequest(trimmed);
    if (txRequest != null) {
      return SolanaPayInfo(
        type: SolanaPayType.transactionRequest,
        recipient: txRequest.link.toString(),
        label: txRequest.label,
        message: txRequest.message,
      );
    }

    return null;
  }

  /// Builds, signs and sends a native SOL or SPL transfer payment (spec v1).
  ///
  /// [overrideAmount] overrides the amount parsed from the link.
  Future<String> payWithSol({
    required Wallet wallet,
    required SolanaPayInfo info,
    Decimal? overrideAmount,
  }) async {
    final amount = overrideAmount ?? info.amount;
    if (amount == null || amount <= Decimal.zero) {
      throw const CreateTransactionException('Amount invalid or missing.');
    }

    final recipient = Ed25519HDPublicKey.fromBase58(info.recipient);
    final splToken = info.splToken == null
        ? null
        : Ed25519HDPublicKey.fromBase58(info.splToken!);

    final message = await _client.createSolanaPayMessage(
      payer: wallet.keyPair,
      recipient: recipient,
      amount: amount,
      splToken: splToken,
      reference: info.reference.map(Ed25519HDPublicKey.fromBase58),
      memo: info.memo,
      commitment: Commitment.finalized,
    );

    final blockhash = await _client.rpcClient.getLatestBlockhash(
      commitment: Commitment.finalized,
    );
    final signed = await _sign(
      message,
      blockhash.value.blockhash,
      wallet.keyPair,
    );

    return _sendAndReturn(signed);
  }

  /// Fetches the merchant's transaction from the v2 link, signs it with the
  /// wallet and submits it. Returns the transaction signature.
  Future<String> processTransactionRequest({
    required Wallet wallet,
    required SolanaPayInfo info,
  }) async {
    final txRequest = await _buildTransactionRequest(info);
    final response = await txRequest.post(account: wallet.address);

    final processed = await _client.processSolanaPayTransactionRequest(
      transaction: response.transaction,
      signer: wallet.keyPair.publicKey,
      commitment: Commitment.finalized,
    );

    final signed = await _resign(processed, wallet);
    return _sendAndReturn(signed);
  }

  // Helpers ------------------------------------------------------------------

  SolanaTransactionRequest? _legacyTransactionRequest(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') return null;
    return SolanaTransactionRequest.parse(
      Uri(scheme: 'solana', path: Uri.encodeComponent(url)).toString(),
    );
  }

  Future<SolanaTransactionRequest> _buildTransactionRequest(
    SolanaPayInfo info,
  ) async {
    final parsed = SolanaTransactionRequest.tryParse(info.recipient);
    if (parsed != null) return parsed;
    final url = info.recipient;
    final link = Uri.tryParse(url);
    if (link == null || link.scheme == 'solana') {
      throw const ParseUrlException('Link invalid');
    }
    return SolanaTransactionRequest.parse(
      Uri(scheme: 'solana', path: Uri.encodeComponent(url)).toString(),
    );
  }

  Future<SignedTx> _sign(
    Message message,
    String blockhash,
    Ed25519HDKeyPair signer,
  ) async {
    final compiled = message.compile(
      recentBlockhash: blockhash,
      feePayer: signer.publicKey,
    );
    return _signCompiled(compiled, [signer]);
  }

  Future<SignedTx> _signCompiled(
    CompiledMessage compiled,
    List<Ed25519HDKeyPair> signers,
  ) async {
    final signatures = await Future.wait(
      signers.map((s) => s.sign(compiled.toByteArray())),
    );
    return SignedTx(compiledMessage: compiled, signatures: signatures);
  }

  Future<SignedTx> _resign(SignedTx tx, Wallet wallet) async {
    final signature = await wallet.keyPair.sign(
      tx.compiledMessage.toByteArray(),
    );
    final signatures = tx.signatures
        .map((s) => s.publicKey == wallet.keyPair.publicKey ? signature : s)
        .toList();
    return SignedTx(
      compiledMessage: tx.compiledMessage,
      signatures: signatures,
    );
  }

  Future<String> _sendAndReturn(SignedTx signed) async {
    return _client.rpcClient.sendTransaction(
      signed.encode(),
      preflightCommitment: Commitment.finalized,
    );
  }
}
