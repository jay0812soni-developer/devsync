import 'dart:convert';
import 'package:cryptography/cryptography.dart';

class EncryptedPayload {
  final String cipherTextBase64;
  final String nonceBase64;
  final String macBase64;

  EncryptedPayload({
    required this.cipherTextBase64,
    required this.nonceBase64,
    required this.macBase64,
  });

  Map<String, dynamic> toJson() => {
        'cipherText': cipherTextBase64,
        'nonce': nonceBase64,
        'mac': macBase64,
      };

  factory EncryptedPayload.fromJson(Map<String, dynamic> json) {
    return EncryptedPayload(
      cipherTextBase64: json['cipherText'] as String,
      nonceBase64: json['nonce'] as String,
      macBase64: json['mac'] as String,
    );
  }
}

class E2eeCipher {
  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Ed25519 _ed25519 = Ed25519();

  /// Derives an AES-256 secret key from our private key and the peer's public key
  Future<SecretKey> deriveSharedKey({
    required SimpleKeyPair myKeyPair,
    required String peerPublicKeyBase64,
  }) async {
    final peerBytes = base64Decode(peerPublicKeyBase64);
    final peerPublicKey = SimplePublicKey(peerBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: peerPublicKey,
    );

    // Derive symmetric encryption key via HKDF-SHA256
    final hkdf = Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 32,
    );

    return await hkdf.deriveKey(
      secretKey: sharedSecret,
      info: utf8.encode('devsync-e2ee-v1'),
    );
  }

  /// Encrypts a plaintext string to an EncryptedPayload
  Future<EncryptedPayload> encrypt({
    required String plainText,
    required SecretKey secretKey,
  }) async {
    final plainBytes = utf8.encode(plainText);
    final secretBox = await _aesGcm.encrypt(
      plainBytes,
      secretKey: secretKey,
    );

    return EncryptedPayload(
      cipherTextBase64: base64Encode(secretBox.cipherText),
      nonceBase64: base64Encode(secretBox.nonce),
      macBase64: base64Encode(secretBox.mac.bytes),
    );
  }

  /// Decrypts an EncryptedPayload to the original plaintext string
  Future<String> decrypt({
    required EncryptedPayload payload,
    required SecretKey secretKey,
  }) async {
    final cipherBytes = base64Decode(payload.cipherTextBase64);
    final nonce = base64Decode(payload.nonceBase64);
    final macBytes = base64Decode(payload.macBase64);

    final secretBox = SecretBox(
      cipherBytes,
      nonce: nonce,
      mac: Mac(macBytes),
    );

    final clearBytes = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(clearBytes);
  }

  /// Signs a string payload using the device's Ed25519 keypair
  Future<String> signPayload({
    required String message,
    required SimpleKeyPair signingKeyPair,
  }) async {
    final messageBytes = utf8.encode(message);
    final signature = await _ed25519.sign(messageBytes, keyPair: signingKeyPair);
    return base64Encode(signature.bytes);
  }

  /// Verifies an Ed25519 signature
  Future<bool> verifySignature({
    required String message,
    required String signatureBase64,
    required String publicKeyBase64,
  }) async {
    final messageBytes = utf8.encode(message);
    final sigBytes = base64Decode(signatureBase64);
    final pubKeyBytes = base64Decode(publicKeyBase64);

    final signature = Signature(
      sigBytes,
      publicKey: SimplePublicKey(pubKeyBytes, type: KeyPairType.ed25519),
    );

    return await _ed25519.verify(messageBytes, signature: signature);
  }
}
