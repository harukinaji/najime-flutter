import 'dart:convert';

import 'package:bip39/bip39.dart' as bip39;
import 'package:solana/solana.dart';

/// Represents a wallet derived from a mnemonic phrase.
class Wallet {
  Wallet({required this.mnemonic, required this.keyPair});

  /// Generates a new random 12-word mnemonic.
  static Future<Wallet> generate() async {
    final mnemonic = bip39.generateMnemonic();
    return Wallet.fromMnemonic(mnemonic);
  }

  /// Restores a wallet from a 12/24-word mnemonic phrase.
  static Future<Wallet> fromMnemonic(String mnemonic) async {
    final trimmed = mnemonic.trim().toLowerCase().split(RegExp(r'\s+')).join(' ');
    final keyPair = await Ed25519HDKeyPair.fromMnemonic(trimmed);
    return Wallet(mnemonic: trimmed, keyPair: keyPair);
  }

  /// Restores a wallet from a base58 private key.
  ///
  /// Accepts either a 64-byte keypair (secret + public, the format produced by
  /// `solana-keygen`) or a 32-byte secret seed.
  static Future<Wallet> fromPrivateKey(String base58) async {
    final bytes = base58Decode(base58);
    final List<int> seed;
    if (bytes.length == 64) {
      seed = bytes.sublist(0, 32);
    } else if (bytes.length == 32) {
      seed = bytes;
    } else {
      throw const FormatException('Invalid private key length, expected 32 or 64 bytes');
    }
    final keyPair = await Ed25519HDKeyPair.fromPrivateKeyBytes(privateKey: seed);
    return Wallet(mnemonic: '', keyPair: keyPair);
  }

  final String mnemonic;
  final Ed25519HDKeyPair keyPair;

  String get address => keyPair.address;

  /// Encodes the private key as base58 (64 bytes: secret + public).
  Future<String> encodePrivateKey() async {
    final data = await keyPair.extract();
    final secret = data.bytes;
    final public = data.publicKey.bytes;
    return base58Encode([...secret, ...public]);
  }
}

/// Minimal base58 codec (no external dependency needed).
const String base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

String base58Encode(List<int> bytes) {
  if (bytes.isEmpty) return '';
  var num = BigInt.zero;
  for (final b in bytes) {
    num = (num << 8) | BigInt.from(b);
  }

  final builder = StringBuffer();
  while (num > BigInt.zero) {
    final remainder = (num % BigInt.from(58)).toInt();
    builder.write(base58Alphabet[remainder]);
    num = num ~/ BigInt.from(58);
  }
  for (var i = 0; i < bytes.length && bytes[i] == 0; i++) {
    builder.write('1');
  }
  return builder.toString().split('').reversed.join();
}

/// Decodes a base58 string to bytes.
List<int> base58Decode(String input) {
  const alphabet = base58Alphabet;
  final cleaned = input.trim();
  if (cleaned.isEmpty) return [];

  var num = BigInt.zero;
  for (var i = 0; i < cleaned.length; i++) {
    final digit = alphabet.indexOf(cleaned[i]);
    if (digit < 0) {
      throw FormatException('Invalid base58 character: ${cleaned[i]}');
    }
    num = num * BigInt.from(58) + BigInt.from(digit);
  }

  final byteCount = ((num.bitLength + 7) ~/ 8);
  final bytes = List<int>.filled(byteCount, 0);
  for (var i = 0; i < byteCount; i++) {
    final shift = 8 * (byteCount - i - 1);
    bytes[i] = ((num >> shift) & BigInt.from(0xff)).toInt();
  }

  var zeros = 0;
  while (zeros < cleaned.length && cleaned[zeros] == '1') {
    zeros++;
  }
  return [...List<int>.filled(zeros, 0), ...bytes];
}

String base58EncodeHex(String hex) => base58Encode(hexToBytes(hex));

List<int> hexToBytes(String hex) {
  final clean = hex.replaceAll('0x', '');
  return List<int>.generate(
    clean.length ~/ 2,
    (i) => int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16),
  );
}

String bytesToHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

String jsonEncodeKeyPair(Map<String, dynamic> data) => jsonEncode(data);
