class WalletConfig {
  static const String rpcUrl = String.fromEnvironment(
    'SOLANA_RPC_URL',
    defaultValue: 'https://api.devnet.solana.com',
  );
  static const String websocketUrl = String.fromEnvironment(
    'SOLANA_WS_URL',
    defaultValue: 'wss://api.devnet.solana.com',
  );
  static const String clusterName = String.fromEnvironment(
    'SOLANA_CLUSTER',
    defaultValue: 'Solana Devnet',
  );
  static const int lamportsPerSol = 1000000000;

  static const List<String> knownMints = [
    'So11111111111111111111111111111111111111112',
    'mSoLzYCxHdYgdzU16g5QSh3i5K3z3KZK7ytfqcJm7So',
  ];
}
