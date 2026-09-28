import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart' hide Wallet;

import '../../data/api_service.dart';
import '../services/wallet_service.dart';
import '../services/walletconnect_service.dart';

class CheckEscrowService {
  const CheckEscrowService(this._client);

  static String? _cachedProgramId;
  static Future<String?>? _programIdRequest;

  final SolanaClient _client;

  // ── Public API ──────────────────────────────────────────────────

  static Future<String?> getProgramId() async {
    final cached = _cachedProgramId;
    if (cached != null) return cached;
    final pending = _programIdRequest;
    if (pending != null) return pending;

    final request = _fetchProgramId();
    _programIdRequest = request;
    try {
      final programId = await request;
      if (programId != null) _cachedProgramId = programId;
      return programId;
    } finally {
      _programIdRequest = null;
    }
  }

  static Future<String?> _fetchProgramId() async {
    try {
      final resp = await ApiService.getProgramId();
      if (resp != null && resp['success'] == true && resp['version'] == 2) {
        return resp['program_id'] as String?;
      }
    } catch (_) {}
    return null;
  }

  /// Returns true while the escrow PDA exists, false after it has been
  /// redeemed/closed, and null when its state could not be read.
  static Future<bool?> isCheckActive(
    SolanaClient client,
    String checkIdOrPda,
  ) async {
    try {
      var address = checkIdOrPda;
      // Older local demo payloads stored the seed (which may contain `_`)
      // instead of the derived PDA.
      if (address.contains('_')) {
        final programId = await getProgramId();
        if (programId == null) return null;
        address = await deriveCheckPda(programId, address);
      }
      final result = await client.rpcClient.getAccountInfo(
        address,
        commitment: Commitment.confirmed,
      );
      return result.value != null;
    } catch (_) {
      return null;
    }
  }

  static Future<String> deriveCheckPda(String programId, String checkId) async {
    final programKey = Ed25519HDPublicKey.fromBase58(programId);
    final pda = await Ed25519HDPublicKey.findProgramAddress(
      seeds: [
        ByteArray(Uint8List.fromList(utf8.encode('check_v2'))),
        ByteArray(Uint8List.fromList(utf8.encode(checkId))),
      ],
      programId: programKey,
    );
    return pda.toBase58();
  }

  /// Create check — supports both built-in wallet and WalletConnect (Phantom).
  Future<(String, String)> createCheck({
    Wallet? wallet,
    WalletConnectClient? wcClient,
    required String feePayerAddress,
    required String checkId,
    required int lamports,
    required String recipientAddress,
  }) async {
    final programId = await getProgramId();
    if (programId == null) throw Exception('Program ID not configured');

    final pdaAddress = await deriveCheckPda(programId, checkId);
    final pda = Ed25519HDPublicKey.fromBase58(pdaAddress);
    final programKey = Ed25519HDPublicKey.fromBase58(programId);
    final feePayer = Ed25519HDPublicKey.fromBase58(feePayerAddress);

    if (base58Decode(recipientAddress).length != 32 ||
        recipientAddress == feePayerAddress) {
      throw ArgumentError('A different valid recipient wallet is required');
    }
    // The local demo account has no backend identity. In Devnet alpha the
    // on-chain signer is sufficient, so wallet linking/proof is skipped.
    if (ApiService.accessToken != 'demo-local-session') {
      final proof = await ApiService.linkWalletAccount(
        walletAddress: feePayerAddress,
        signMessage: (message) async {
          if (wallet != null)
            return base58Encode(
              (await wallet.keyPair.sign(utf8.encode(message))).bytes,
            );
          if (wcClient != null)
            return base58Encode(
              (await wcClient.signMessage(
                Uint8List.fromList(utf8.encode(message)),
              )).signature,
            );
          throw StateError('No wallet available');
        },
      );
      if (!proof.success)
        throw StateError(proof.message ?? 'Wallet proof failed');
    }
    final data = ByteArray.merge([
      ByteArray(_instructionDiscriminator('create_check_v2')),
      _borshString(checkId),
      ByteArray.u64(lamports),
      ByteArray(base58Decode(recipientAddress)),
    ]);

    final instruction = Instruction(
      programId: programKey,
      accounts: [
        AccountMeta.writeable(pubKey: pda, isSigner: false),
        AccountMeta.writeable(pubKey: feePayer, isSigner: true),
        AccountMeta.readonly(pubKey: SystemProgram.id, isSigner: false),
      ],
      data: data,
    );

    final txSig = await _signAndSend(
      instruction: instruction,
      feePayer: feePayer,
      wallet: wallet,
      wcClient: wcClient,
    );

    debugPrint('[CheckEscrow] createCheck pda=$pdaAddress tx=$txSig');
    return (pdaAddress, txSig);
  }

  /// Redeem check — supports both built-in wallet and WalletConnect (Phantom).
  Future<String> redeemCheck({
    Wallet? wallet,
    WalletConnectClient? wcClient,
    required String feePayerAddress,
    required String pdaAddress,
    required String creatorAddress,
  }) async {
    final programId = await getProgramId();
    if (programId == null) throw Exception('Program ID not configured');

    final pda = Ed25519HDPublicKey.fromBase58(pdaAddress);
    final programKey = Ed25519HDPublicKey.fromBase58(programId);
    final feePayer = Ed25519HDPublicKey.fromBase58(feePayerAddress);
    final creator = Ed25519HDPublicKey.fromBase58(creatorAddress);

    if (ApiService.accessToken != 'demo-local-session') {
      final proof = await ApiService.linkWalletAccount(
        walletAddress: feePayerAddress,
        signMessage: (message) async {
          if (wallet != null)
            return base58Encode(
              (await wallet.keyPair.sign(utf8.encode(message))).bytes,
            );
          if (wcClient != null)
            return base58Encode(
              (await wcClient.signMessage(
                Uint8List.fromList(utf8.encode(message)),
              )).signature,
            );
          throw StateError('No wallet available');
        },
      );
      if (!proof.success)
        throw StateError(proof.message ?? 'Wallet proof failed');
    }
    final data = ByteArray(_instructionDiscriminator('redeem_check_v2'));

    final instruction = Instruction(
      programId: programKey,
      accounts: [
        AccountMeta.writeable(pubKey: pda, isSigner: false),
        AccountMeta.writeable(pubKey: creator, isSigner: false),
        AccountMeta.writeable(pubKey: feePayer, isSigner: true),
        AccountMeta.readonly(pubKey: SystemProgram.id, isSigner: false),
      ],
      data: data,
    );

    final txSig = await _signAndSend(
      instruction: instruction,
      feePayer: feePayer,
      wallet: wallet,
      wcClient: wcClient,
    );

    debugPrint('[CheckEscrow] redeemCheck pda=$pdaAddress tx=$txSig');
    return txSig;
  }

  // ── Internal: sign + send via wallet or WalletConnect ────────────

  Future<String> _signAndSend({
    required Instruction instruction,
    required Ed25519HDPublicKey feePayer,
    Wallet? wallet,
    WalletConnectClient? wcClient,
  }) async {
    final blockhash = await _client.rpcClient.getLatestBlockhash(
      commitment: Commitment.confirmed,
    );
    final message = Message(instructions: [instruction]);
    final compiled = message.compile(
      recentBlockhash: blockhash.value.blockhash,
      feePayer: feePayer,
    );

    // ── Path A: Built-in wallet (has private key) ──
    if (wallet != null) {
      final signature = await wallet.keyPair.sign(compiled.toByteArray());
      final signed = SignedTx(
        compiledMessage: compiled,
        signatures: [signature],
      );
      return _client.rpcClient.sendTransaction(
        signed.encode(),
        preflightCommitment: Commitment.confirmed,
      );
    }

    // ── Path B: WalletConnect / Phantom (deep-link signing) ──
    if (wcClient != null) {
      // Build unsigned tx with placeholder signature
      final placeholder = Signature(
        List<int>.filled(64, 0),
        publicKey: feePayer,
      );
      final unsigned = SignedTx(
        compiledMessage: compiled,
        signatures: [placeholder],
      );
      final txB58 = unsigned.encode();

      // Use signTransaction (not signAndSendTransaction — Phantom
      // doesn't support custom programs via signAndSend).
      debugPrint('[CheckEscrow] sending to Phantom for signing...');
      final signResult = await wcClient.signTransaction(txB58);
      // signResult.signature is the base58 signed tx — broadcast via RPC
      final txSig = await _client.rpcClient.sendTransaction(
        signResult.signature,
        preflightCommitment: Commitment.confirmed,
      );
      return txSig;
    }

    throw Exception('No wallet available for signing');
  }

  // ── Helpers ─────────────────────────────────────────────────────

  static Uint8List _instructionDiscriminator(String name) {
    return Uint8List.fromList(
      crypto.sha256.convert(utf8.encode('global:$name')).bytes.take(8).toList(),
    );
  }

  static ByteArray _borshString(String s) {
    final bytes = Uint8List.fromList(utf8.encode(s));
    final len = Uint8List(4)
      ..buffer.asByteData().setUint32(0, bytes.length, Endian.little);
    return ByteArray(Uint8List.fromList([...len, ...bytes]));
  }
}
