class TokenInfo {
  const TokenInfo({
    required this.mint,
    required this.symbol,
    required this.name,
    required this.decimals,
    this.isCustom = false,
    this.programId,
  });

  final String mint;
  final String symbol;
  final String name;
  final int decimals;
  final bool isCustom;

  /// Owning token program (standard SPL or Token-2022), when known.
  final String? programId;

  static const String solMint = 'So11111111111111111111111111111111111111112';

  bool get isSol => mint == solMint;

  factory TokenInfo.fromJson(Map<String, dynamic> json) => TokenInfo(
    mint: json['mint'] as String,
    symbol: json['symbol'] as String,
    name: json['name'] as String,
    decimals: json['decimals'] as int,
    isCustom: true,
  );

  Map<String, dynamic> toJson() => {
    'mint': mint,
    'symbol': symbol,
    'name': name,
    'decimals': decimals,
  };
}

const TokenInfo kSolToken = TokenInfo(
  mint: TokenInfo.solMint,
  symbol: 'SOL',
  name: 'Solana',
  decimals: 9,
);

/// Tokens known to the app on devnet.
const List<TokenInfo> kKnownTokens = [
  kSolToken,
  TokenInfo(
    mint: '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
    symbol: 'USDC',
    name: 'USD Coin',
    decimals: 6,
  ),
  TokenInfo(
    mint: 'HzwqbKZw8HxMN6bF2yFZNrht3c2iXXzpKcFu7uBEDKtr',
    symbol: 'EURC',
    name: 'Euro Coin',
    decimals: 6,
  ),
  TokenInfo(
    mint: 'Fm9rHUTF5v3hwMLbStjZXqNBBoZyGjuQnT1ZWjNSKH4',
    symbol: 'mSOL',
    name: 'Marinade staked SOL',
    decimals: 9,
  ),
];
