class TokenBalance {
  const TokenBalance({
    required this.mint,
    required this.account,
    required this.rawAmount,
    required this.decimals,
    required this.uiAmountString,
    required this.tokenSymbol,
    required this.tokenName,
    required this.programId,
  });

  final String mint;
  final String account;
  final int rawAmount;
  final int decimals;
  final String uiAmountString;
  final String tokenSymbol;
  final String tokenName;

  /// Owning token program (standard SPL or Token-2022).
  final String programId;

  bool get isSol => mint == 'So11111111111111111111111111111111111111112';

  bool get isToken2022 =>
      programId == 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb';
}
