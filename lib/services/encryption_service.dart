import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Service für E2E-Verschlüsselung (Zero-Knowledge)
class EncryptionService {
  final FlutterSecureStorage _storage;

  // Storage Keys
  static const _keyMasterKey = 'encryption_master_key';
  static const _keySalt = 'encryption_salt';
  static const _keyVerificationHash = 'encryption_verification';

  // Cached keys
  SecretKey? _masterKey;
  Uint8List? _salt;

  EncryptionService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
        );

  /// Prüft ob Verschlüsselung eingerichtet ist
  Future<bool> isSetUp() async {
    final key = await _storage.read(key: _keyMasterKey);
    return key != null;
  }

  /// Richtet Verschlüsselung mit Passphrase ein
  Future<void> setUp(String passphrase) async {
    // Salt generieren
    final algorithm = AesGcm.with256bits();
    final saltKey = await algorithm.newSecretKey();
    final saltBytes = await saltKey.extractBytes();
    _salt = Uint8List.fromList(saltBytes);

    // Master Key aus Passphrase ableiten
    _masterKey = await _deriveKey(passphrase, _salt!);

    // Verification Hash erstellen (um Passphrase zu verifizieren)
    final verificationHash = await _createVerificationHash(_masterKey!);

    // Sicher speichern
    final masterKeyBytes = await _masterKey!.extractBytes();
    await _storage.write(key: _keyMasterKey, value: base64Encode(masterKeyBytes));
    await _storage.write(key: _keySalt, value: base64Encode(_salt!));
    await _storage.write(key: _keyVerificationHash, value: base64Encode(verificationHash));

    debugPrint('Encryption set up successfully');
  }

  /// Lädt gespeicherte Keys
  Future<void> loadKeys() async {
    final masterKeyStr = await _storage.read(key: _keyMasterKey);
    final saltStr = await _storage.read(key: _keySalt);

    if (masterKeyStr == null || saltStr == null) {
      throw Exception('Encryption not set up');
    }

    final masterKeyBytes = base64Decode(masterKeyStr);
    _masterKey = SecretKey(masterKeyBytes);
    _salt = Uint8List.fromList(base64Decode(saltStr));
  }

  /// Verifiziert Passphrase
  Future<bool> verifyPassphrase(String passphrase) async {
    final saltStr = await _storage.read(key: _keySalt);
    final storedHashStr = await _storage.read(key: _keyVerificationHash);

    if (saltStr == null || storedHashStr == null) return false;

    final salt = Uint8List.fromList(base64Decode(saltStr));
    final key = await _deriveKey(passphrase, salt);
    final computedHash = await _createVerificationHash(key);
    final storedHash = base64Decode(storedHashStr);

    return _constantTimeCompare(computedHash, storedHash);
  }

  /// Salt für Server (zur Passphrase-Verifizierung auf anderen Geräten)
  Future<String?> getSaltBase64() async {
    return await _storage.read(key: _keySalt);
  }

  /// Verification Hash für Server
  Future<String?> getVerificationHashBase64() async {
    return await _storage.read(key: _keyVerificationHash);
  }

  /// Verschlüsselt Daten
  Future<EncryptedData> encrypt(Map<String, dynamic> data) async {
    if (_masterKey == null) {
      await loadKeys();
    }

    final algorithm = AesGcm.with256bits();
    final plaintext = utf8.encode(jsonEncode(data));

    // Zufällige Nonce generieren
    final nonce = algorithm.newNonce();

    final secretBox = await algorithm.encrypt(
      plaintext,
      secretKey: _masterKey!,
      nonce: nonce,
    );

    return EncryptedData(
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      nonce: Uint8List.fromList(secretBox.nonce),
      mac: Uint8List.fromList(secretBox.mac.bytes),
    );
  }

  /// Entschlüsselt Daten
  Future<Map<String, dynamic>> decrypt(EncryptedData encrypted) async {
    if (_masterKey == null) {
      await loadKeys();
    }

    final algorithm = AesGcm.with256bits();

    final secretBox = SecretBox(
      encrypted.ciphertext,
      nonce: encrypted.nonce,
      mac: Mac(encrypted.mac),
    );

    final plaintext = await algorithm.decrypt(
      secretBox,
      secretKey: _masterKey!,
    );

    return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
  }

  /// Leitet Schlüssel aus Passphrase ab (PBKDF2)
  Future<SecretKey> _deriveKey(String passphrase, Uint8List salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000, // Hohe Iteration für Sicherheit
      bits: 256,
    );

    return await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  /// Erstellt Verification Hash
  Future<Uint8List> _createVerificationHash(SecretKey key) async {
    final keyBytes = await key.extractBytes();
    final hmac = Hmac.sha256();
    final mac = await hmac.calculateMac(
      utf8.encode('vibedtracker-verification'),
      secretKey: SecretKey(keyBytes),
    );
    return Uint8List.fromList(mac.bytes);
  }

  bool _constantTimeCompare(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Löscht alle Encryption-Daten
  Future<void> reset() async {
    _masterKey = null;
    _salt = null;
    await _storage.delete(key: _keyMasterKey);
    await _storage.delete(key: _keySalt);
    await _storage.delete(key: _keyVerificationHash);
  }
}

/// Container für verschlüsselte Daten
class EncryptedData {
  final Uint8List ciphertext;
  final Uint8List nonce;
  final Uint8List mac;

  EncryptedData({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  /// Kombiniert ciphertext + mac für Server
  Uint8List get blob {
    final result = Uint8List(ciphertext.length + mac.length);
    result.setRange(0, ciphertext.length, ciphertext);
    result.setRange(ciphertext.length, result.length, mac);
    return result;
  }

  /// Base64-kodierter Blob
  String get blobBase64 => base64Encode(blob);

  /// Base64-kodierte Nonce
  String get nonceBase64 => base64Encode(nonce);

  /// Erstellt aus Server-Daten
  factory EncryptedData.fromBase64({
    required String blobBase64,
    required String nonceBase64,
  }) {
    final blob = base64Decode(blobBase64);
    final nonce = base64Decode(nonceBase64);

    // MAC ist die letzten 16 Bytes
    final ciphertext = Uint8List.fromList(blob.sublist(0, blob.length - 16));
    final mac = Uint8List.fromList(blob.sublist(blob.length - 16));

    return EncryptedData(
      ciphertext: ciphertext,
      nonce: Uint8List.fromList(nonce),
      mac: mac,
    );
  }
}
