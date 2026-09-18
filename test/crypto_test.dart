import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:devsync/core/crypto/e2ee_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('E2eeCipher Tests', () {
    late E2eeCipher cipher;

    setUp(() {
      cipher = E2eeCipher();
    });

    test('ECDH Key Exchange + AES-256-GCM Encrypt & Decrypt matches between two devices', () async {
      final x25519 = X25519();

      // Device A generates X25519 keypair
      final deviceAKeyPair = await x25519.newKeyPair();
      final deviceAPub = await deviceAKeyPair.extractPublicKey();
      final deviceAPubBase64 = base64Encode(deviceAPub.bytes);

      // Device B generates X25519 keypair
      final deviceBKeyPair = await x25519.newKeyPair();
      final deviceBPub = await deviceBKeyPair.extractPublicKey();
      final deviceBPubBase64 = base64Encode(deviceBPub.bytes);

      // Both derive shared key independently
      final secretKeyA = await cipher.deriveSharedKey(
        myKeyPair: deviceAKeyPair,
        peerPublicKeyBase64: deviceBPubBase64,
      );

      final secretKeyB = await cipher.deriveSharedKey(
        myKeyPair: deviceBKeyPair,
        peerPublicKeyBase64: deviceAPubBase64,
      );

      // Device A encrypts a developer payload
      const originalMessage = 'void main() { print("P2P E2EE DevSync!"); }';
      final encryptedPayload = await cipher.encrypt(
        plainText: originalMessage,
        secretKey: secretKeyA,
      );

      expect(encryptedPayload.cipherTextBase64.isNotEmpty, isTrue);
      expect(encryptedPayload.nonceBase64.isNotEmpty, isTrue);
      expect(encryptedPayload.macBase64.isNotEmpty, isTrue);

      // Device B decrypts the payload
      final decryptedText = await cipher.decrypt(
        payload: encryptedPayload,
        secretKey: secretKeyB,
      );

      expect(decryptedText, equals(originalMessage));
    });

    test('Ed25519 digital signature generation and verification', () async {
      final ed25519 = Ed25519();
      final keyPair = await ed25519.newKeyPair();
      final pubKey = await keyPair.extractPublicKey();
      final pubKeyBase64 = base64Encode(pubKey.bytes);

      const payload = 'DEV-SIGNATURE-TEST-PAYLOAD';

      final signature = await cipher.signPayload(
        message: payload,
        signingKeyPair: keyPair,
      );

      final isValid = await cipher.verifySignature(
        message: payload,
        signatureBase64: signature,
        publicKeyBase64: pubKeyBase64,
      );

      expect(isValid, isTrue);

      // Tampered payload fails verification
      final isTamperedValid = await cipher.verifySignature(
        message: 'TAMPERED-PAYLOAD',
        signatureBase64: signature,
        publicKeyBase64: pubKeyBase64,
      );

      expect(isTamperedValid, isFalse);
    });
  });
}
