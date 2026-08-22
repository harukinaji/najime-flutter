class TokenMetadata {
  const TokenMetadata({required this.name, required this.symbol, this.uri});

  final String name;
  final String symbol;

  /// Metadata JSON URI (used to resolve the token icon image).
  final String? uri;
}
