import 'package:flutter/foundation.dart';
import 'package:solana/dto.dart' hide Instruction;
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart' hide Wallet;

import '../models/token_info.dart';
import 'wallet_service.dart';

/// Parsed Raydium CPMM pool state (devnet program DRaycpLY...).
class RaydiumCpmmPool {
  const RaydiumCpmmPool({
    required this.id,
    required this.ammConfig,
    required this.poolCreator,
    required this.token0Vault,
    required this.token1Vault,
    required this.lpMint,
    required this.token0Mint,
    required this.token1Mint,
    required this.token0Program,
    required this.token1Program,
    required this.observationKey,
    required this.authBump,
    required this.status,
    required this.mint0Decimals,
    required this.mint1Decimals,
    required this.openTime,
    required this.protocolFeesToken0,
    required this.protocolFeesToken1,
    required this.fundFeesToken0,
    required this.fundFeesToken1,
    required this.creatorFeesToken0,
    required this.creatorFeesToken1,
    required this.creatorFeeOn,
    required this.enableCreatorFee,
  });

  final String id;
  final String ammConfig;
  final String poolCreator;
  final String token0Vault;
  final String token1Vault;
  final String lpMint;
  final String token0Mint;
  final String token1Mint;
  final String token0Program;
  final String token1Program;
  final String observationKey;
  final int authBump;
  final int status;
  final int mint0Decimals;
  final int mint1Decimals;
  final int openTime;

  /// Accrued protocol / fund / creator fees held in the vaults. The on-chain
  /// swap deducts these before computing the constant-product output.
  final int protocolFeesToken0;
  final int protocolFeesToken1;
  final int fundFeesToken0;
  final int fundFeesToken1;
  final int creatorFeesToken0;
  final int creatorFeesToken1;

  /// Creator fee collection mode: 0 = both tokens, 1 = only token0,
  /// 2 = only token1.
  final int creatorFeeOn;
  final bool enableCreatorFee;

  bool get swapEnabled => (status & 4) == 0;
}

/// AmmConfig (fee schedule) for a CPMM pool.
class RaydiumAmmConfig {
  const RaydiumAmmConfig({
    required this.tradeFeeRate,
    required this.protocolFeeRate,
    required this.fundFeeRate,
    required this.creatorFeeRate,
  });

  final int tradeFeeRate;
  final int protocolFeeRate;
  final int fundFeeRate;
  final int creatorFeeRate;
}

/// Result of a swap quote.
class RaydiumQuote {
  const RaydiumQuote({
    required this.amountIn,
    required this.amountOut,
    required this.fee,
    required this.minimumAmountOut,
    required this.inputMint,
    required this.outputMint,
    required this.inputDecimals,
    required this.outputDecimals,
    required this.priceImpactBps,
  });

  final int amountIn;
  final int amountOut;
  final int fee;
  final int minimumAmountOut;
  final String inputMint;
  final String outputMint;
  final int inputDecimals;
  final int outputDecimals;
  final int priceImpactBps;
}

class RaydiumException implements Exception {
  const RaydiumException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Client for Raydium CPMM pools on devnet.
///
/// Raydium has no Dart SDK, so pool discovery, state parsing, quoting and
/// instruction building are implemented here directly against the on-chain
/// program (devnet `DRaycpLY18LhpbydsBWbVJtxpNv9oXPgjRSfpF2bWpYb`).
class RaydiumService {
  RaydiumService(this._client);

  /// Raydium CPMM program id on devnet.
  static const String programId =
      'DRaycpLY18LhpbydsBWbVJtxpNv9oXPgjRSfpF2bWpYb';

  /// Raydium CPMM program id on mainnet (for reference).
  static const String programIdMainnet =
      'CPMMoo8L3F4NbTegBCKVNunggL7H1ZpdTHKxQB5qKP1';

  /// Anchor discriminator of the PoolState account.
  static const List<int> poolDiscriminator = [
    247,
    237,
    227,
    245,
    215,
    195,
    222,
    70,
  ];

  /// Anchor discriminator of the AmmConfig account.
  static const List<int> configDiscriminator = [
    218,
    244,
    33,
    104,
    203,
    203,
    43,
    111,
  ];

  /// Discriminator of the `swap_base_input` instruction.
  static const List<int> swapBaseInputDiscriminator = [
    143,
    190,
    90,
    218,
    196,
    30,
    51,
    222,
  ];

  /// PoolState serialized size (8-byte discriminator + packed struct).
  static const int poolDataSize = 637;

  /// PDA seed for the vault & lp mint authority.
  static const List<int> authSeed = [
    118,
    97,
    117,
    108,
    116,
    95,
    97,
    110,
    100,
    95,
    108,
    112,
    95,
    109,
    105,
    110,
    116, //
    95, 97, 117, 116, 104, 95, 115, 101, 101, 100,
  ];

  static const int feeDenominator = 1000000;

  final SolanaClient _client;

  /// Derives the Raydium authority PDA (pool vault + lp mint authority).
  static Future<Ed25519HDPublicKey> deriveAuthority() =>
      Ed25519HDPublicKey.findProgramAddress(
        seeds: [authSeed],
        programId: Ed25519HDPublicKey.fromBase58(programId),
      );

  /// Discovers CPMM pools where [mintA] is one of the two pool mints.
  ///
  /// Uses `getProgramAccounts` with a memcmp filter on the token_0 mint slot
  /// (offset 168 after the 8-byte discriminator); [mintB], when provided,
  /// narrows to pools pairing [mintA] with [mintB] in either order.
  Future<List<RaydiumCpmmPool>> findPools({
    String? mintA,
    String? mintB,
  }) async {
    final filters = <ProgramDataFilter>[
      ProgramDataFilter.dataSize(poolDataSize),
    ];
    if (mintA != null) {
      filters.add(ProgramDataFilter.memcmpBase58(offset: 168, bytes: mintA));
    }

    final result = await _client.rpcClient.getProgramAccounts(
      programId,
      commitment: Commitment.confirmed,
      encoding: Encoding.base64,
      filters: filters,
    );

    final pools = <RaydiumCpmmPool>[];
    for (final account in result) {
      final data = (account.account.data as BinaryAccountData).data;
      final pool = _parsePool(account.pubkey, data);
      if (pool == null) continue;
      if (mintB != null) {
        if (pool.token0Mint != mintB && pool.token1Mint != mintB) continue;
      }
      pools.add(pool);
    }
    return pools;
  }

  /// Parses a raw 637-byte PoolState account.
  RaydiumCpmmPool? _parsePool(String id, List<int> data) {
    if (data.length < poolDataSize) return null;
    for (var i = 0; i < 8; i++) {
      if (data[i] != poolDiscriminator[i]) return null;
    }
    return RaydiumCpmmPool(
      id: id,
      ammConfig: base58Encode(data.sublist(8, 40)),
      poolCreator: base58Encode(data.sublist(40, 72)),
      token0Vault: base58Encode(data.sublist(72, 104)),
      token1Vault: base58Encode(data.sublist(104, 136)),
      lpMint: base58Encode(data.sublist(136, 168)),
      token0Mint: base58Encode(data.sublist(168, 200)),
      token1Mint: base58Encode(data.sublist(200, 232)),
      token0Program: base58Encode(data.sublist(232, 264)),
      token1Program: base58Encode(data.sublist(264, 296)),
      observationKey: base58Encode(data.sublist(296, 328)),
      authBump: data[328],
      status: data[329],
      mint0Decimals: data[331],
      mint1Decimals: data[332],
      openTime: _readU64(data, 373),
      protocolFeesToken0: _readU64(data, 341),
      protocolFeesToken1: _readU64(data, 349),
      fundFeesToken0: _readU64(data, 357),
      fundFeesToken1: _readU64(data, 365),
      creatorFeesToken0: _readU64(data, 397),
      creatorFeesToken1: _readU64(data, 405),
      creatorFeeOn: data[389],
      enableCreatorFee: data[390] != 0,
    );
  }

  /// Fetches and parses the AmmConfig account referenced by [pool].
  Future<RaydiumAmmConfig> getAmmConfig(RaydiumCpmmPool pool) async {
    final info = await _client.rpcClient
        .getAccountInfo(
          pool.ammConfig,
          commitment: Commitment.confirmed,
          encoding: Encoding.base64,
        )
        .value;
    if (info == null || info.data is! BinaryAccountData) {
      throw const RaydiumException('AmmConfig not found');
    }
    final data = (info.data as BinaryAccountData).data;
    for (var i = 0; i < 8; i++) {
      if (data[i] != configDiscriminator[i]) {
        throw const RaydiumException('Invalid AmmConfig account');
      }
    }
    return RaydiumAmmConfig(
      tradeFeeRate: _readU64(data, 12),
      protocolFeeRate: _readU64(data, 20),
      fundFeeRate: _readU64(data, 28),
      creatorFeeRate: _readU64(data, 108),
    );
  }

  /// Reads the current token amounts (base units) of [pool]'s two vaults.
  Future<({int token0, int token1})> getVaultBalances(
    RaydiumCpmmPool pool,
  ) async {
    final token0 = await _tokenAmount(pool.token0Vault);
    final token1 = await _tokenAmount(pool.token1Vault);
    return (token0: token0, token1: token1);
  }

  Future<int> _tokenAmount(String address) async {
    try {
      return int.parse(
        (await _client.rpcClient
                .getTokenAccountBalance(
                  address,
                  commitment: Commitment.confirmed,
                )
                .value)
            .amount,
      );
    } catch (_) {
      return 0;
    }
  }

  /// Computes an exact-input swap quote for [amountIn] base units of the input
  /// mint on [pool].
  ///
  /// Mirrors `CurveCalculator::swap_base_input` from the on-chain CPMM program:
  /// accrued protocol/fund/creator fees are deducted from the vault reserves,
  /// the creator fee is charged either on input or on output depending on the
  /// pool's `creator_fee_on` mode, and all fee math uses ceil/floor division
  /// with a 1e6 denominator.
  Future<RaydiumQuote> quote({
    required RaydiumCpmmPool pool,
    required RaydiumAmmConfig config,
    required String inputMint,
    required int amountIn,
    required int slippageBps,
  }) async {
    if (amountIn <= 0) {
      throw const RaydiumException('Amount must be positive');
    }
    final inputIsToken0 = pool.token0Mint == inputMint;
    if (pool.token0Mint != inputMint && pool.token1Mint != inputMint) {
      throw RaydiumException('Mint $inputMint is not in this pool');
    }

    final balances = await getVaultBalances(pool);
    // Deduct accrued fees exactly like `vault_amount_without_fee`.
    final inputReserve =
        (inputIsToken0 ? balances.token0 : balances.token1) -
        (inputIsToken0
            ? pool.protocolFeesToken0 +
                  pool.fundFeesToken0 +
                  pool.creatorFeesToken0
            : pool.protocolFeesToken1 +
                  pool.fundFeesToken1 +
                  pool.creatorFeesToken1);
    final outputReserve =
        (inputIsToken0 ? balances.token1 : balances.token0) -
        (inputIsToken0
            ? pool.protocolFeesToken1 +
                  pool.fundFeesToken1 +
                  pool.creatorFeesToken1
            : pool.protocolFeesToken0 +
                  pool.fundFeesToken0 +
                  pool.creatorFeesToken0);
    if (inputReserve <= 0 || outputReserve <= 0) {
      throw const RaydiumException('Pool has no liquidity');
    }

    // Creator fee on input? Mirrors `is_creator_fee_on_input`:
    // BothToken(0) -> always input; OnlyToken0(1) -> input when input is token0;
    // OnlyToken1(2) -> input when input is token1.
    final isCreatorFeeOnInput = switch (pool.creatorFeeOn) {
      0 => true,
      1 => inputIsToken0,
      2 => !inputIsToken0,
      _ => false,
    };
    final creatorFeeRate = pool.enableCreatorFee ? config.creatorFeeRate : 0;

    final input = BigInt.from(amountIn);
    final inputVault = BigInt.from(inputReserve);
    final outputVault = BigInt.from(outputReserve);

    BigInt tradeFee;
    BigInt inputAfterFee;
    if (isCreatorFeeOnInput) {
      final totalRate = BigInt.from(config.tradeFeeRate + creatorFeeRate);
      final totalFee = _ceilDiv(input * totalRate, BigInt.from(feeDenominator));
      final creatorFee = (totalFee * BigInt.from(creatorFeeRate)) ~/ totalRate;
      tradeFee = totalFee - creatorFee;
      inputAfterFee = input - totalFee;
    } else {
      tradeFee = _ceilDiv(
        input * BigInt.from(config.tradeFeeRate),
        BigInt.from(feeDenominator),
      );
      inputAfterFee = input - tradeFee;
    }

    // Constant product: (input_after_fee * output) / (input + input_after_fee)
    final outputSwapped =
        (inputAfterFee * outputVault) ~/ (inputVault + inputAfterFee);

    var outputAmount = outputSwapped;
    if (!isCreatorFeeOnInput && creatorFeeRate > 0) {
      final creatorFee = _ceilDiv(
        outputSwapped * BigInt.from(creatorFeeRate),
        BigInt.from(feeDenominator),
      );
      outputAmount = outputSwapped - creatorFee;
    }

    if (outputAmount <= BigInt.zero) {
      throw const RaydiumException('Swap output rounds to zero');
    }

    final priceImpactBps = _priceImpactBps(
      amountIn: input,
      inputReserve: inputVault,
      outputReserve: outputVault,
      outputAmount: outputAmount,
    );

    // minimum_amount_out = output * (10000 - slippage) / 10000
    final minOut =
        (outputAmount * BigInt.from(10000 - slippageBps)) ~/ BigInt.from(10000);

    return RaydiumQuote(
      amountIn: amountIn,
      amountOut: outputAmount.toInt(),
      fee: tradeFee.toInt(),
      minimumAmountOut: minOut.toInt(),
      inputMint: inputMint,
      outputMint: inputIsToken0 ? pool.token1Mint : pool.token0Mint,
      inputDecimals: inputIsToken0 ? pool.mint0Decimals : pool.mint1Decimals,
      outputDecimals: inputIsToken0 ? pool.mint1Decimals : pool.mint0Decimals,
      priceImpactBps: priceImpactBps,
    );
  }

  static BigInt _ceilDiv(BigInt a, BigInt b) {
    if (a.isNegative) return a ~/ b;
    return (a + b - BigInt.one) ~/ b;
  }

  int _priceImpactBps({
    required BigInt amountIn,
    required BigInt inputReserve,
    required BigInt outputReserve,
    required BigInt outputAmount,
  }) {
    // spot = output_reserve / input_reserve ; effective = output / amount_in
    // impact ≈ (1 - effective/spot). Compare cross-multiplied:
    // spot * outputAmount  vs  outputReserve * amountIn
    final spotNum = outputReserve * amountIn;
    final effNum = outputAmount * inputReserve;
    if (spotNum <= BigInt.zero) return 0;
    if (effNum >= spotNum) return 0;
    final diff = spotNum - effNum;
    return ((diff * BigInt.from(10000)) ~/ spotNum).toInt();
  }

  /// Builds, signs and sends a `swap_base_input` transaction.
  /// Creates the user's ATA for input/output mints if missing, wraps native SOL
  /// when needed, then submits the swap. Returns the transaction signature.
  Future<String> swap({
    required Wallet wallet,
    required RaydiumCpmmPool pool,
    required RaydiumAmmConfig config,
    required RaydiumQuote quote,
  }) async {
    final inputIsToken0 = pool.token0Mint == quote.inputMint;
    final inputVault = inputIsToken0 ? pool.token0Vault : pool.token1Vault;
    final outputVault = inputIsToken0 ? pool.token1Vault : pool.token0Vault;
    final inputProgram = inputIsToken0
        ? pool.token0Program
        : pool.token1Program;
    final outputProgram = inputIsToken0
        ? pool.token1Program
        : pool.token0Program;
    final inputMintKey = Ed25519HDPublicKey.fromBase58(quote.inputMint);
    final outputMintKey = Ed25519HDPublicKey.fromBase58(quote.outputMint);

    final isNativeIn = quote.inputMint == TokenInfo.solMint;

    final inputAta = await _resolveAta(wallet, inputMintKey);
    final outputAta = await _resolveAta(wallet, outputMintKey);

    final authority = await deriveAuthority();

    final instructions = <Instruction>[
      // Raise the compute budget; pool state + observation + ATA logic can
      // exceed the default 200k unit limit.
      ComputeBudgetInstruction.setComputeUnitLimit(units: 400000),
      if (!inputAta.exists)
        AssociatedTokenAccountInstruction.createAccountIdempotent(
          funder: wallet.keyPair.publicKey,
          address: inputAta.address,
          owner: wallet.keyPair.publicKey,
          mint: inputMintKey,
        ),
      if (!outputAta.exists)
        AssociatedTokenAccountInstruction.createAccountIdempotent(
          funder: wallet.keyPair.publicKey,
          address: outputAta.address,
          owner: wallet.keyPair.publicKey,
          mint: outputMintKey,
        ),
      // Native SOL must first be wrapped into the wSOL associated token
      // account (transfer lamports + syncNative) before the swap can move it.
      if (isNativeIn) ...[
        SystemInstruction.transfer(
          fundingAccount: wallet.keyPair.publicKey,
          recipientAccount: inputAta.address,
          lamports: quote.amountIn,
        ),
        TokenInstruction.syncNative(nativeTokenAccount: inputAta.address),
      ],
      _buildSwapInstruction(
        payer: wallet.keyPair.publicKey,
        authority: authority,
        ammConfig: Ed25519HDPublicKey.fromBase58(pool.ammConfig),
        poolState: Ed25519HDPublicKey.fromBase58(pool.id),
        inputAta: inputAta.address,
        outputAta: outputAta.address,
        inputVault: Ed25519HDPublicKey.fromBase58(inputVault),
        outputVault: Ed25519HDPublicKey.fromBase58(outputVault),
        inputTokenProgram: Ed25519HDPublicKey.fromBase58(inputProgram),
        outputTokenProgram: Ed25519HDPublicKey.fromBase58(outputProgram),
        inputMint: inputMintKey,
        outputMint: outputMintKey,
        observationKey: Ed25519HDPublicKey.fromBase58(pool.observationKey),
        amountIn: quote.amountIn,
        minimumAmountOut: quote.minimumAmountOut,
      ),
    ];

    // Fetch a blockhash at finalized commitment (devnet load-balanced nodes may
    // reject `confirmed`-level blockhashes) and retry with a fresh blockhash if
    // submission fails (e.g. BlockhashNotFound after expiry).
    const attempts = 3;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final blockhash = await _client.rpcClient.getLatestBlockhash(
        commitment: Commitment.finalized,
      );
      final message = Message(instructions: instructions);
      final signed = await _sign(message, blockhash.value.blockhash, wallet);
      try {
        return await _client.rpcClient.sendTransaction(
          signed.encode(),
          preflightCommitment: Commitment.finalized,
        );
      } catch (e) {
        if (attempt == attempts - 1) rethrow;
        debugPrint('Swap submit failed (attempt ${attempt + 1}): $e');
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    throw const RaydiumException('Swap submission failed');
  }

  Instruction _buildSwapInstruction({
    required Ed25519HDPublicKey payer,
    required Ed25519HDPublicKey authority,
    required Ed25519HDPublicKey ammConfig,
    required Ed25519HDPublicKey poolState,
    required Ed25519HDPublicKey inputAta,
    required Ed25519HDPublicKey outputAta,
    required Ed25519HDPublicKey inputVault,
    required Ed25519HDPublicKey outputVault,
    required Ed25519HDPublicKey inputTokenProgram,
    required Ed25519HDPublicKey outputTokenProgram,
    required Ed25519HDPublicKey inputMint,
    required Ed25519HDPublicKey outputMint,
    required Ed25519HDPublicKey observationKey,
    required int amountIn,
    required int minimumAmountOut,
  }) {
    final data = ByteArray.merge([
      ByteArray(swapBaseInputDiscriminator),
      ByteArray.u64(amountIn),
      ByteArray.u64(minimumAmountOut),
    ]);

    return Instruction(
      programId: Ed25519HDPublicKey.fromBase58(programId),
      accounts: [
        AccountMeta.readonly(pubKey: payer, isSigner: true),
        AccountMeta.readonly(pubKey: authority, isSigner: false),
        AccountMeta.readonly(pubKey: ammConfig, isSigner: false),
        AccountMeta.writeable(pubKey: poolState, isSigner: false),
        AccountMeta.writeable(pubKey: inputAta, isSigner: false),
        AccountMeta.writeable(pubKey: outputAta, isSigner: false),
        AccountMeta.writeable(pubKey: inputVault, isSigner: false),
        AccountMeta.writeable(pubKey: outputVault, isSigner: false),
        AccountMeta.readonly(pubKey: inputTokenProgram, isSigner: false),
        AccountMeta.readonly(pubKey: outputTokenProgram, isSigner: false),
        AccountMeta.readonly(pubKey: inputMint, isSigner: false),
        AccountMeta.readonly(pubKey: outputMint, isSigner: false),
        AccountMeta.writeable(pubKey: observationKey, isSigner: false),
      ],
      data: data,
    );
  }

  Future<({Ed25519HDPublicKey address, bool exists})> _resolveAta(
    Wallet wallet,
    Ed25519HDPublicKey mint,
  ) async {
    final ata = await findAssociatedTokenAddress(
      owner: wallet.keyPair.publicKey,
      mint: mint,
    );
    final info = await _client.rpcClient
        .getAccountInfo(ata.toBase58(), commitment: Commitment.confirmed)
        .value;
    return (address: ata, exists: info != null);
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

  static int _readU64(List<int> data, int offset) {
    var value = 0;
    for (var i = 7; i >= 0; i--) {
      value = (value << 8) | data[offset + i];
    }
    return value;
  }
}
