import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:solana/dto.dart' hide TokenBalance;
import 'package:solana/solana.dart' hide Wallet;

import '../config/constants.dart';
import '../models/nft.dart';
import '../models/token_balance.dart';
import '../models/token_info.dart';
import '../models/token_metadata.dart';
import '../models/transaction_record.dart';
import 'wallet_service.dart';

class SolanaService {
  SolanaService()
      : _client = SolanaClient(
          rpcUrl: Uri.parse(WalletConfig.rpcUrl),
          websocketUrl: Uri.parse(WalletConfig.websocketUrl),
        );

  static const String tokenMetadataProgramId =
      'metaqbxxUerdq28cj1RbAWkYQm3ybzjb6a8bt518x1s';

  final SolanaClient _client;
  final Map<String, TokenMetadata?> _metadataCache = {};
  final Map<String, String?> _imageCache = {};
  final Map<String, Map<String, dynamic>?> _offchainCache = {};

  /// Exposes the underlying RPC client (used by the Solana Pay service).
  SolanaClient get client => _client;

  /// Returns the balance in lamports for [address].
  Future<int> getBalance(String address) async {
    final result = await _client.rpcClient.getBalance(
      address,
      commitment: Commitment.confirmed,
    );
    return result.value;
  }

  /// Requests a devnet airdrop of [lamports] to [address].
  ///
  /// Uses the plain JSON-RPC call directly instead of the package's
  /// [SolanaClient.requestAirdrop], which waits for `finalized` status over a
  /// WebSocket subscription and frequently times out on flaky connections.
  Future<String> requestAirdrop(String address, int lamports) async {
    return _client.rpcClient.requestAirdrop(
      address,
      lamports,
      commitment: Commitment.finalized,
    );
  }

  /// Sends [lamports] from [source] to [destination] with optional [memo].
  Future<String> transfer({
    required Wallet wallet,
    required String destination,
    required int lamports,
    String? memo,
  }) async {
    return _client.transferLamports(
      source: wallet.keyPair,
      destination: Ed25519HDPublicKey.fromBase58(destination),
      lamports: lamports,
      memo: memo,
      commitment: Commitment.finalized,
    );
  }

  /// Sends [amount] (base units) of the SPL token identified by [mint].
  ///
  /// [programId] selects the mint's token program (standard SPL or
  /// Token-2022). Throws [NoAssociatedTokenAccountException] when the sender
  /// or recipient has no associated token account for the mint.
  Future<String> transferToken({
    required Wallet wallet,
    required String mint,
    required String destination,
    required int amount,
    String? memo,
    String? programId,
  }) async {
    return _client.transferSplToken(
      mint: Ed25519HDPublicKey.fromBase58(mint),
      destination: Ed25519HDPublicKey.fromBase58(destination),
      amount: amount,
      owner: wallet.keyPair,
      memo: memo,
      tokenProgram: programId == Token2022Program.programId
          ? TokenProgramType.token2022Program
          : TokenProgramType.tokenProgram,
      commitment: Commitment.finalized,
    );
  }

  /// Fetches SPL and Token-2022 token balances owned by [address].
  ///
  /// Token symbols and names are resolved from on-chain Metaplex metadata
  /// first, then [known], then a short mint prefix.
  Future<List<TokenBalance>> getTokenBalances(
    String address, {
    Map<String, TokenInfo> known = const {},
  }) async {
    final balances = <TokenBalance>[];
    for (final programId in const [
      TokenProgram.programId,
      Token2022Program.programId,
    ]) {
      try {
        final result = await _client.rpcClient.getTokenAccountsByOwner(
          address,
          TokenAccountsFilter.byProgramId(programId),
          encoding: Encoding.jsonParsed,
        );

        for (final programAccount in result.value) {
          final data = programAccount.account.data;
          if (data is! ParsedAccountData) continue;

          final info = _extractTokenInfo(data);
          if (info == null) continue;

          final tokenAmount = info.tokenAmount;
          final rawAmount = int.tryParse(tokenAmount.amount) ?? 0;
          if (rawAmount == 0) continue;
          // Skip NFTs (0 decimals, exactly 1 unit) — they are handled by
          // `getNfts` and would otherwise appear as a "1 unit" token.
          if (tokenAmount.decimals == 0 && rawAmount == 1) continue;

          balances.add(
            TokenBalance(
              mint: info.mint,
              account: programAccount.pubkey,
              rawAmount: rawAmount,
              decimals: tokenAmount.decimals,
              uiAmountString: tokenAmount.uiAmountString ?? '0',
              tokenSymbol: '',
              tokenName: '',
              programId: programId,
            ),
          );
        }
      } catch (_) {
        // A failed query for one program should not hide the other.
      }
    }
    if (balances.isEmpty) return balances;

    final mints = <String>[];
    for (final balance in balances) {
      if (!mints.contains(balance.mint)) mints.add(balance.mint);
    }
    final metadataList = await Future.wait([
      for (final mint in mints) getTokenMetadata(mint),
    ]);
    final metadataById = <String, TokenMetadata?>{
      for (var i = 0; i < mints.length; i++) mints[i]: metadataList[i],
    };

    return [
      for (final balance in balances)
        TokenBalance(
          mint: balance.mint,
          account: balance.account,
          rawAmount: balance.rawAmount,
          decimals: balance.decimals,
          uiAmountString: balance.uiAmountString,
          tokenSymbol: _resolveSymbol(balance.mint, metadataById[balance.mint], known),
          tokenName: _resolveName(balance.mint, metadataById[balance.mint], known),
          programId: balance.programId,
        ),
    ];
  }

  /// Fetches the non-fungible tokens (NFTs) owned by [address].
  ///
  /// Detection: an account whose mint has 0 decimals, holds exactly 1 unit,
  /// whose total supply is 1, and which has a Metaplex metadata account.
  /// Off-chain metadata (image, description, attributes) is loaded from the
  /// on-chain metadata `uri` when present.
  Future<List<Nft>> getNfts(String address) async {
    // 1. Collect candidate token accounts across both token programs.
    final candidates = <String, ({String mint, String account, String programId, int decimals, int amount})>{
    };
    for (final programId in const [
      TokenProgram.programId,
      Token2022Program.programId,
    ]) {
      try {
        final result = await _client.rpcClient.getTokenAccountsByOwner(
          address,
          TokenAccountsFilter.byProgramId(programId),
          encoding: Encoding.jsonParsed,
        );
        for (final programAccount in result.value) {
          final data = programAccount.account.data;
          if (data is! ParsedAccountData) continue;
          final info = _extractTokenInfo(data);
          if (info == null) continue;
          final tokenAmount = info.tokenAmount;
          final rawAmount = int.tryParse(tokenAmount.amount) ?? 0;
          if (tokenAmount.decimals != 0 || rawAmount != 1) continue;
          candidates[info.mint] = (
            mint: info.mint,
            account: programAccount.pubkey,
            programId: programId,
            decimals: tokenAmount.decimals,
            amount: rawAmount,
          );
        }
      } catch (_) {
        // A failed query for one program should not hide the other.
      }
    }

    final nfts = <Nft>[];
    for (final entry in candidates.values) {
      final mint = entry.mint;
      try {
        // 2. Confirm total supply is exactly 1 (a true NFT).
        final supply = await _client.rpcClient.getTokenSupply(
          mint,
          commitment: Commitment.confirmed,
        );
        if (supply.value.amount != '1') continue;

        // 3. Load on-chain metadata, then the off-chain JSON.
        final metadata = await getTokenMetadata(mint);
        if (metadata == null || metadata.uri == null || metadata.uri!.isEmpty) {
          continue;
        }
        final offchain = await _fetchOffchainMetadata(metadata.uri!);

        final name = _firstNonEmpty([
          _cleanMetadata(offchain?['name'] as String?),
          metadata.name,
          _tokenSymbol(mint),
        ]);
        final symbol =
            _cleanMetadata(offchain?['symbol'] as String?).isNotEmpty
                ? _cleanMetadata(offchain?['symbol'] as String?)
                : metadata.symbol;
        final imageUrl = _cleanMetadata(offchain?['image'] as String?);
        final description =
            _cleanMetadata(offchain?['description'] as String?);
        final attributes = _parseNftAttributes(offchain?['attributes']);
        final files = _parseNftFiles(offchain?['properties']);
        final category = _parseNftCategory(offchain, files);

        nfts.add(
          Nft(
            mint: mint,
            tokenAccount: entry.account,
            name: name,
            symbol: symbol,
            imageUrl: imageUrl,
            description: description,
            programId: entry.programId,
            attributes: attributes,
            files: files,
            category: category,
          ),
        );
      } catch (_) {
        // Skip mints that fail any part of the lookup.
      }
    }
    return nfts;
  }

  /// Parses `properties.files` from the off-chain metadata.
  List<NftFile> _parseNftFiles(dynamic properties) {
    final result = <NftFile>[];
    if (properties is! Map<String, dynamic>) return result;
    final files = properties['files'];
    if (files is! List) return result;
    for (final item in files) {
      if (item is Map<String, dynamic>) {
        final uri = _cleanMetadata(item['uri'] as String?);
        final type = _cleanMetadata(item['type'] as String?);
        if (uri.isNotEmpty) {
          result.add(NftFile(uri: uri, type: type));
        }
      }
    }
    return result;
  }

  /// Resolves the media category from the off-chain metadata.
  ///
  /// Reads `category` from the top level or from `properties.category` (some
  /// projects nest it there), and falls back to the file MIME type when the
  /// category is missing.
  NftCategory _parseNftCategory(
    Map<String, dynamic>? offchain,
    List<NftFile> files,
  ) {
    dynamic rawCategory;
    final properties = offchain?['properties'];
    if (offchain?['category'] != null) {
      rawCategory = offchain?['category'];
    } else if (properties is Map<String, dynamic> &&
        properties['category'] != null) {
      rawCategory = properties['category'];
    }

    final value = _cleanMetadata(rawCategory as String?).toLowerCase();
    if (value.startsWith('audio')) return NftCategory.audio;
    if (value.startsWith('video')) return NftCategory.video;
    if (value == 'image') return NftCategory.image;

    // Fallback: infer from the first media file's MIME type.
    for (final file in files) {
      if (file.isAudio) return NftCategory.audio;
      if (file.isVideo) return NftCategory.video;
    }
    return NftCategory.unknown;
  }

  String _firstNonEmpty(List<String> values) {
    for (final value in values) {
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  /// Parses Metaplex off-chain `attributes` into [NftAttribute]s.
  List<NftAttribute> _parseNftAttributes(dynamic attributes) {
    final result = <NftAttribute>[];
    if (attributes is List) {
      for (final item in attributes) {
        if (item is Map<String, dynamic>) {
          final trait = item['trait_type'];
          final value = item['value'];
          if (trait is String && value != null) {
            result.add(
              NftAttribute(
                traitType: _cleanMetadata(trait),
                value: value.toString(),
              ),
            );
          }
        }
      }
    }
    return result;
  }

  /// Fetches on-chain token metadata (name/symbol) for [mint].
  ///
  /// Looks first at the Token-2022 `tokenMetadata` extension stored directly
  /// on the mint account, then at the Metaplex Token Metadata PDA. Results
  /// are cached in memory; both hits and misses are cached.
  Future<TokenMetadata?> getTokenMetadata(String mint) async {
    if (_metadataCache.containsKey(mint)) return _metadataCache[mint];

    var metadata = await _getOnMintMetadata(mint);
    metadata ??= await _getMetaplexMetadata(mint);

    _metadataCache[mint] = metadata;
    return metadata;
  }

  /// Curated icon URLs for known mints that have no on-chain Metaplex
  /// metadata on devnet (e.g. the devnet USDC/EURC faucet mints). Reuses the
  /// respective mainnet token logo.
static const Map<String, String> _knownTokenIcons = {
    // Solana (native token).
    'So11111111111111111111111111111111111111112':
        'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/solana/info/logo.png',
// Devnet USD Coin (mapped to the mainnet USDC logo).
    '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU':
        'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/solana/assets/EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v/logo.png',
    // Devnet Marinade staked SOL (mapped to the mainnet mSOL logo).
    'Fm9rHUTF5v3hwMLbStjZXqNBBoZyGjuQnT1ZWjNSKH4':
        'https://raw.githubusercontent.com/trustwallet/assets/master/blockchains/solana/assets/mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So/logo.png',
  };

  /// Resolves a token icon URL for [mint] from a curated map of known tokens
  /// first, then from its on-chain metadata `uri`. Returns `null` when
  /// unavailable. Cached in memory.
  Future<String?> getTokenImage(String mint) async {
    if (_imageCache.containsKey(mint)) return _imageCache[mint];

    String? image = _knownTokenIcons[mint];
    if (image == null) {
      final metadata = await getTokenMetadata(mint);
      final uriStr = metadata?.uri;
      if (uriStr != null && uriStr.isNotEmpty) {
        image = await _resolveImageFromUri(uriStr);
      }
    }

    _imageCache[mint] = image;
    return image;
  }

  Future<String?> _resolveImageFromUri(String metadataUri) async {
    final decoded = await _fetchOffchainMetadata(metadataUri);
    final image = decoded?['image'];
    if (image is String && image.isNotEmpty) return image;
    return null;
  }

  /// Fetches and caches the off-chain metadata JSON behind [metadataUri].
  Future<Map<String, dynamic>?> _fetchOffchainMetadata(String metadataUri) async {
    if (_offchainCache.containsKey(metadataUri)) {
      return _offchainCache[metadataUri];
    }
    try {
      final response = await http
          .get(Uri.parse(metadataUri))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        _offchainCache[metadataUri] = null;
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        _offchainCache[metadataUri] = decoded;
        return decoded;
      }
    } catch (_) {
      // Metadata JSON unreachable.
    }
    _offchainCache[metadataUri] = null;
    return null;
  }

  /// Reads the Token-2022 `tokenMetadata` extension embedded in the mint
  /// account (used by PYUSD, etc.).
  Future<TokenMetadata?> _getOnMintMetadata(String mint) async {
    try {
      final response = await http
          .post(
            Uri.parse(WalletConfig.rpcUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': 1,
              'method': 'getAccountInfo',
              'params': [
                mint,
                {'encoding': 'jsonParsed', 'commitment': 'confirmed'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final result = body['result'] as Map<String, dynamic>?;
      final value = result?['value'] as Map<String, dynamic>?;
      final data = value?['data'] as Map<String, dynamic>?;
      final parsed = data?['parsed'] as Map<String, dynamic>?;
      final info = parsed?['info'] as Map<String, dynamic>?;
      final extensions = info?['extensions'];
      if (extensions is! List) return null;

      for (final ext in extensions) {
        if (ext is! Map<String, dynamic>) continue;
        if (ext['extension'] != 'tokenMetadata') continue;
        final state = ext['state'] as Map<String, dynamic>?;
        if (state == null) return null;
        final name = _cleanMetadata(state['name'] as String?);
        final symbol = _cleanMetadata(state['symbol'] as String?);
        final uri = _cleanMetadata(state['uri'] as String?);
        if (name.isEmpty && symbol.isEmpty) return null;
        return TokenMetadata(
          name: name,
          symbol: symbol,
          uri: uri.isEmpty ? null : uri,
        );
      }
    } catch (_) {
      // No metadata on-chain for this mint.
    }
    return null;
  }

  /// Reads metadata from the Metaplex Token Metadata PDA account.
  Future<TokenMetadata?> _getMetaplexMetadata(String mint) async {
    try {
      final mintKey = Ed25519HDPublicKey.fromBase58(mint);
      final metadataProgram =
          Ed25519HDPublicKey.fromBase58(tokenMetadataProgramId);
      final metadataAddress = await Ed25519HDPublicKey.findProgramAddress(
        seeds: [
          utf8.encode('metadata'),
          metadataProgram.bytes,
          mintKey.bytes,
        ],
        programId: metadataProgram,
      );

      final account = await _client.rpcClient
          .getAccountInfo(
            metadataAddress.toBase58(),
            encoding: Encoding.base64,
            commitment: Commitment.confirmed,
          )
          .value;

      if (account != null && account.data is BinaryAccountData) {
        return _parseTokenMetadata((account.data as BinaryAccountData).data);
      }
    } catch (_) {
      // No metadata on-chain for this mint.
    }
    return null;
  }

  String _resolveSymbol(
    String mint,
    TokenMetadata? metadata,
    Map<String, TokenInfo> known,
  ) {
    if (metadata != null && metadata.symbol.isNotEmpty) return metadata.symbol;
    return known[mint]?.symbol ?? _tokenSymbol(mint);
  }

  String _resolveName(
    String mint,
    TokenMetadata? metadata,
    Map<String, TokenInfo> known,
  ) {
    if (metadata != null && metadata.name.isNotEmpty) return metadata.name;
    return known[mint]?.name ?? '';
  }

  /// Strips NUL padding and surrounding whitespace from Borsh/metadata fields.
  String _cleanMetadata(String? value) {
    if (value == null || value.isEmpty) return '';
    var cleaned = value.replaceAll('\u0000', '');
    return cleaned.trim();
  }

  /// Parses a Metaplex Token Metadata account into [TokenMetadata].
  ///
  /// Layout: key(1) + updateAuthority(32) + mint(32), then Borsh strings
  /// `name`, `symbol`, `uri`.
  TokenMetadata? _parseTokenMetadata(List<int> bytes) {
    try {
      final byteData = ByteData.sublistView(Uint8List.fromList(bytes));
      var offset = 65;

      String readBorshString() {
        final length = byteData.getUint32(offset, Endian.little);
        offset += 4;
        final str = utf8
            .decode(bytes.sublist(offset, offset + length),
                allowMalformed: true)
            .trim();
        offset += length;
        return _cleanMetadata(str);
      }

      final name = readBorshString();
      final symbol = readBorshString();
      if (name.isEmpty && symbol.isEmpty) return null;
      final uri = readBorshString();
      return TokenMetadata(
        name: name,
        symbol: symbol,
        uri: uri.isEmpty ? null : uri,
      );
    } catch (_) {
      return null;
    }
  }

  SplTokenAccountDataInfo? _extractTokenInfo(ParsedAccountData data) {
    switch (data) {
      case ParsedSplTokenProgramAccountData(:final parsed):
        if (parsed is TokenAccountData) return parsed.info;
      case ParsedSplToken2022ProgramAccountData(:final parsed):
        if (parsed is TokenAccountData) return parsed.info;
      default:
        break;
    }
    return null;
  }

  String _tokenSymbol(String mint) {
    const symbols = <String, String>{
      'So11111111111111111111111111111111111111112': 'SOL',
      'mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So': 'mSOL',
      'Fm9rHUTF5v3hwMLbStjZXqNBBoZyGjuQnT1ZWjNSKH4': 'USDC',
    };
    return symbols[mint] ?? mint.substring(0, 4).toUpperCase();
  }

  /// Fetches the transaction history for [address].
  Future<List<TransactionRecord>> getTransactionHistory(
    String address, {
    int limit = 50,
  }) async {
    try {
      final signatures = await _client.rpcClient.getSignaturesForAddress(
        address,
        limit: limit,
        commitment: Commitment.confirmed,
      );

      final records = <TransactionRecord>[];
      for (final sig in signatures) {
        records.add(
          TransactionRecord(
            signature: sig.signature,
            slot: sig.slot,
            blockTime: sig.blockTime,
            err: sig.err,
            memo: sig.memo,
            status: sig.confirmationStatus,
          ),
        );
      }
      return records;
    } catch (_) {
      return [];
    }
  }

  /// Resolves a transaction signature to a fully-parsed transaction.
  Future<TransactionDetails?> getTransaction(String signature) async {
    return _client.rpcClient.getTransaction(
      signature,
      encoding: Encoding.jsonParsed,
      commitment: Commitment.confirmed,
      maxSupportedTransactionVersion: 0,
    );
  }

  /// Returns the current cluster health.
  Future<String> getHealth() => _client.rpcClient.getHealth();
}
