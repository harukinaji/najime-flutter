import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as c;
import 'package:flutter_test/flutter_test.dart';
import 'package:solana/encoder.dart';
import 'package:solana/solana.dart' hide Wallet;

import 'package:najime/wallet/services/wallet_service.dart';

void main() {
  group('Wallet.fromMnemonic (BIP39 key derivation)', () {
    const mnemonic =
        'test test test test test test test test test test test junk';

    test('is deterministic — same mnemonic derives the same address', () async {
      final a = await Wallet.fromMnemonic(mnemonic);
      final b = await Wallet.fromMnemonic(mnemonic);
      expect(a.address, b.address);
      expect(a.address.length, greaterThanOrEqualTo(32));
      // Valid Solana base58 pubkey: 32 bytes decoded.
      expect(base58Decode(a.address).length, 32);
    });

    test('normalizes whitespace and case', () async {
      final a = await Wallet.fromMnemonic(
        ' Test Test Test Test Test Test Test Test Test Test Test Junk ',
      );
      final b = await Wallet.fromMnemonic(mnemonic);
      expect(a.address, b.address);
    });

    test('24-word mnemonics are supported', () async {
      const mnemonic24 =
          'abandon abandon abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon abandon abandon abandon '
          'abandon abandon abandon abandon abandon abandon abandon art';
      final wallet = await Wallet.fromMnemonic(mnemonic24);
      expect(base58Decode(wallet.address).length, 32);
    });

    test('generated mnemonics are 12 words and reproducible', () async {
      final wallet = await Wallet.generate();
      final words = wallet.mnemonic.trim().split(RegExp(r'\s+'));
      expect(words.length, 12);
      final restored = await Wallet.fromMnemonic(wallet.mnemonic);
      expect(restored.address, wallet.address);
    });
  });

  group('Wallet.fromPrivateKey', () {
    test('64-byte keypair roundtrips (solana-keygen format)', () async {
      final wallet = await Wallet.generate();
      final encoded = await wallet.encodePrivateKey();
      expect(base58Decode(encoded).length, 64);

      final restored = await Wallet.fromPrivateKey(encoded);
      expect(restored.address, wallet.address);
    });

    test('rejects invalid key lengths', () async {
      // 2 '1's decode to 2 zero bytes — not 32 or 64.
      await expectLater(
        Wallet.fromPrivateKey('11'),
        throwsA(isA<FormatException>()),
      );
      // 40-byte base58 payload — not 32 or 64.
      final bad40 = base58Encode(List<int>.filled(40, 1));
      await expectLater(
        Wallet.fromPrivateKey(bad40),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('base58 codec helpers (wallet_service)', () {
    test('encodes leading zero bytes as "1"', () {
      expect(base58Encode([0]), '1');
      expect(base58Encode([0, 0]), '11');
    });

    test('roundtrip preserves bytes', () {
      final bytes = List<int>.generate(32, (i) => (i * 7 + 3) & 0xff);
      expect(base58Decode(base58Encode(bytes)), bytes);
    });

    test('hex helpers roundtrip', () {
      final bytes = hexToBytes('0xdeadbeef');
      expect(bytes, [0xde, 0xad, 0xbe, 0xef]);
      expect(bytesToHex(bytes), 'deadbeef');
    });
  });

  group('signing', () {
    test('Ed25519 signature verifies against the derived public key', () async {
      const mnemonic =
          'test test test test test test test test test test test junk';
      final wallet = await Wallet.fromMnemonic(mnemonic);

      final message = Uint8List.fromList(List<int>.generate(32, (i) => i));
      final sig = await wallet.keyPair.sign(message);
      expect(sig.bytes.length, 64);

      final extracted = await wallet.keyPair.extract();
      final pub = extracted.publicKey.bytes;

      final ed = c.Ed25519();
      final pk = c.SimplePublicKey(pub, type: c.KeyPairType.ed25519);
      final ok = await ed.verify(
        message,
        signature: c.Signature(sig.bytes, publicKey: pk),
      );
      expect(ok, isTrue, reason: 'signature must verify for the same keypair');
    });
  });

  group('transaction creation & serialization (no network)', () {
    const blockhash = '11111111111111111111111111111111';

    test(
      'System Program transfer encodes, decodes and preserves message',
      () async {
        const mnemonic =
            'test test test test test test test test test test test junk';
        final wallet = await Wallet.fromMnemonic(mnemonic);
        final senderKey = Ed25519HDPublicKey.fromBase58(wallet.address);
        final recipientKey = Ed25519HDPublicKey.fromBase58(
          'C6P9WUg4maMmurtDNA63vxsVyDzrpPMgLjetNnLAP4LW',
        );

        final message = Message(
          instructions: [
            SystemInstruction.transfer(
              fundingAccount: senderKey,
              recipientAccount: recipientKey,
              lamports: 1234,
            ),
          ],
        );
        final compiled = message.compile(
          recentBlockhash: blockhash,
          feePayer: senderKey,
        );
        final placeholder = Signature(
          List<int>.filled(64, 0),
          publicKey: senderKey,
        );
        final signed = SignedTx(
          compiledMessage: compiled,
          signatures: [placeholder],
        );

        final serialized = signed.encode();
        expect(serialized, isNotEmpty);

        // Decode the serialized base58 transaction back and re-decompile.
        final decoded = SignedTx.decode(serialized);
        expect(
          decoded.compiledMessage.toByteArray(),
          compiled.toByteArray(),
          reason: 'round-tripped message must be byte-identical',
        );
        final decodedInstructions = Message.decompile(
          decoded.compiledMessage,
        ).instructions;
        expect(decodedInstructions.length, 1);
      },
    );
  });
}
