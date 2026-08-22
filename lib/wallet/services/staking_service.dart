import 'package:solana/dto.dart' hide Instruction;
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart' hide Wallet;

import '../config/constants.dart';
import 'wallet_service.dart';

/// Information about an SPL native stake account held by the wallet.
class StakedAccount {
  const StakedAccount({
    required this.address,
    required this.vote,
    required this.amountLamports,
    required this.active,
  });

  final String address;
  final String? vote;
  final int amountLamports;
  final bool active;

  double get amountSol => amountLamports / WalletConfig.lamportsPerSol;
}

/// Stake config sysvar consumed by [StakeInstruction.delegateStake].
const String kStakeConfig = 'StakeConfig11111111111111111111111111111111';

/// Solana native SOL staking client (on-chain stake program).
class StakingService {
  StakingService(this._client);

  final SolanaClient _client;

  static const String _seedPrefix = 'stake';

  /// Minimum delegation (in lamports) required by the stake program on devnet.
  /// Staking below this amount fails with `InsufficientDelegation` (0xc).
  static const int minimalDelegationLamports = 1000000000; // 1 SOL

  /// Derives a stake account address for the wallet at [index].
  static Future<Ed25519HDPublicKey> deriveStakeAddress(
    Ed25519HDPublicKey wallet,
    int index,
  ) => Ed25519HDPublicKey.createWithSeed(
    fromPublicKey: wallet,
    seed: '$_seedPrefix:$index',
    programId: StakeProgram.id,
  );

  /// Returns the current active validators (vote accounts) so the user can
  /// choose where to delegate.
  Future<List<VoteAccount>> getValidators() async {
    final accounts = await _client.rpcClient.getVoteAccounts(
      commitment: Commitment.confirmed,
    );
    return accounts.current;
  }

  /// Creates a stake account funded with [amountLamports], initializes it and
  /// delegates to [vote]. Returns the transaction signature.
  Future<String> stake({
    required Wallet wallet,
    required String vote,
    required int amountLamports,
    required int index,
  }) async {
    final stakeAddress = await deriveStakeAddress(
      wallet.keyPair.publicKey,
      index,
    );

    // The delegated amount is (funded lamports - rent-exempt reserve) because
    // the reserve is locked to keep the account rent-exempt. Devnet enforces a
    // minimum delegation of 1 SOL; reject clearly instead of failing on-chain.
    final reserve = await _client.rpcClient.getMinimumBalanceForRentExemption(
      StakeProgram.neededAccountSpace,
      commitment: Commitment.confirmed,
    );
    final delegated = amountLamports - reserve;
    if (delegated < minimalDelegationLamports) {
      final needed =
          (minimalDelegationLamports + reserve) / WalletConfig.lamportsPerSol;
      throw ArgumentError(
        'Insufficient SOL for staking: requires minimum '
        '${needed.toStringAsFixed(4)} SOL (reserve $reserve), '
        'but you specified '
        '${(amountLamports / WalletConfig.lamportsPerSol).toStringAsFixed(4)} SOL.',
      );
    }

    final authorized = Authorized(
      staker: wallet.keyPair.publicKey.toBase58(),
      withdrawer: wallet.keyPair.publicKey.toBase58(),
    );

    final instructions = <Instruction>[
      SystemInstruction.createAccountWithSeed(
        fundingAccount: wallet.keyPair.publicKey,
        newAccount: stakeAddress,
        base: wallet.keyPair.publicKey,
        seed: '$_seedPrefix:$index',
        lamports: amountLamports,
        space: StakeProgram.neededAccountSpace,
        owner: StakeProgram.id,
      ),
      StakeInstruction.initialize(stake: stakeAddress, authorized: authorized),
      StakeInstruction.delegateStake(
        stake: stakeAddress,
        vote: Ed25519HDPublicKey.fromBase58(vote),
        config: Ed25519HDPublicKey.fromBase58(kStakeConfig),
        authority: wallet.keyPair.publicKey,
      ),
    ];

    final blockhash = await _client.rpcClient.getLatestBlockhash(
      commitment: Commitment.finalized,
    );
    final message = Message(instructions: instructions);
    final signed = await _sign(message, blockhash.value.blockhash, wallet);
    return _client.rpcClient.sendTransaction(
      signed.encode(),
      preflightCommitment: Commitment.finalized,
    );
  }

  /// Lists the wallet's stake accounts derived from its pubkey.
  Future<List<StakedAccount>> getAccounts(Wallet wallet) async {
    final results = <StakedAccount>[];
    for (var i = 0; i < 10; i++) {
      final address = await deriveStakeAddress(wallet.keyPair.publicKey, i);
      final info = await _client.rpcClient
          .getAccountInfo(address.toBase58(), commitment: Commitment.confirmed)
          .value;
      if (info == null || info.data is! BinaryAccountData) continue;
      final parsed = _parseStake((info.data as BinaryAccountData).data);
      if (parsed == null) continue;
      results.add(
        StakedAccount(
          address: address.toBase58(),
          vote: parsed.vote,
          amountLamports: parsed.stakeLamports,
          active: parsed.active,
        ),
      );
    }
    return results;
  }

  /// Parses a 200-byte stake account: returns the vote pubkey and the active
  /// stake lamports; null if the data is not a stake account.
  ///
  /// Layout after the owning program check: Meta is 8 (rent) + 64 (authorized)
  /// + 48 (lockup) = 120 bytes; the Stake struct starts at 120 with
  /// credits_observed (u64), then Delegation { voter_pubkey(32), stake(u64),
  /// activation_epoch, deactivation_epoch, warmup_cooldown_rate }.
  static ({String vote, int stakeLamports, bool active})? _parseStake(
    List<int> data,
  ) {
    if (data.length < 192) return null;
    final stateOffset = 124;
    if (stateOffset + 8 > data.length) return null;
    final stakeLamports = _readU64(data, 160);
    final vote = base58Encode(data.sublist(128, 160));
    return (
      vote: vote,
      stakeLamports: stakeLamports,
      active: stakeLamports > 0,
    );
  }

  static int _readU64(List<int> data, int offset) {
    var value = 0;
    for (var i = 7; i >= 0; i--) {
      value = (value << 8) | data[offset + i];
    }
    return value;
  }

  Future<SignedTx> _sign(
    Message message,
    String blockhash,
    Wallet wallet,
  ) async {
    final compiled = message.compile(
      recentBlockhash: blockhash,
      feePayer: wallet.keyPair.publicKey,
    );
    final signature = await wallet.keyPair.sign(compiled.toByteArray());
    return SignedTx(compiledMessage: compiled, signatures: [signature]);
  }
}
