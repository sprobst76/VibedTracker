import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:cryptography/cryptography.dart';

/// Service für sichere Schlüsselverwaltung und Authentifizierung
class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'vibed_tracker_secure',
      preferencesKeyPrefix: 'vt_',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
      accountName: 'VibedTracker',
    ),
  );

  final _localAuth = LocalAuthentication();

  // Storage Keys
  static const _keyHiveEncryption = 'hive_encryption_key';
  static const _keyPinHash = 'pin_hash';
  static const _keyPinSalt = 'pin_salt';
  static const _keyBiometricsEnabled = 'biometrics_enabled';
  static const _keyAppLockEnabled = 'app_lock_enabled';
  static const _keyAutoLockTimeout = 'auto_lock_timeout';
  static const _keyLastActivity = 'last_activity';

  // ==================== Hive Encryption Key ====================

  /// Generiert oder lädt den Hive-Verschlüsselungsschlüssel
  Future<Uint8List> getOrCreateHiveKey() async {
    final existingKey = await _storage.read(key: _keyHiveEncryption);

    if (existingKey != null) {
      return base64Decode(existingKey);
    }

    // Neuen 256-bit Key generieren
    final algorithm = AesGcm.with256bits();
    final secretKey = await algorithm.newSecretKey();
    final keyBytes = await secretKey.extractBytes();
    final key = Uint8List.fromList(keyBytes);

    // Sicher speichern
    await _storage.write(
      key: _keyHiveEncryption,
      value: base64Encode(key),
    );

    return key;
  }

  /// Prüft ob bereits ein Hive-Key existiert (für Migration)
  Future<bool> hasHiveKey() async {
    final key = await _storage.read(key: _keyHiveEncryption);
    return key != null;
  }

  // ==================== PIN Management ====================

  /// Setzt eine neue PIN
  Future<void> setPin(String pin) async {
    // Salt generieren
    final algorithm = AesGcm.with256bits();
    final saltKey = await algorithm.newSecretKey();
    final saltBytes = await saltKey.extractBytes();
    final salt = Uint8List.fromList(saltBytes.sublist(0, 16));

    // PIN hashen mit Argon2
    final hash = await _hashPin(pin, salt);

    await _storage.write(key: _keyPinSalt, value: base64Encode(salt));
    await _storage.write(key: _keyPinHash, value: base64Encode(hash));
  }

  /// Verifiziert eine PIN
  Future<bool> verifyPin(String pin) async {
    final saltStr = await _storage.read(key: _keyPinSalt);
    final storedHashStr = await _storage.read(key: _keyPinHash);

    if (saltStr == null || storedHashStr == null) {
      return false;
    }

    final salt = base64Decode(saltStr);
    final storedHash = base64Decode(storedHashStr);
    final inputHash = await _hashPin(pin, Uint8List.fromList(salt));

    // Timing-safe comparison
    return _constantTimeCompare(storedHash, inputHash);
  }

  /// Prüft ob eine PIN gesetzt ist
  Future<bool> hasPin() async {
    final hash = await _storage.read(key: _keyPinHash);
    return hash != null;
  }

  /// Entfernt die PIN
  Future<void> removePin() async {
    await _storage.delete(key: _keyPinHash);
    await _storage.delete(key: _keyPinSalt);
  }

  Future<Uint8List> _hashPin(String pin, Uint8List salt) async {
    // Verwende PBKDF2 da Argon2 in cryptography nicht direkt verfügbar
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 100000,
      bits: 256,
    );

    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );

    final bytes = await secretKey.extractBytes();
    return Uint8List.fromList(bytes);
  }

  bool _constantTimeCompare(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  // ==================== Biometrics ====================

  /// Prüft ob Biometrie verfügbar ist
  Future<bool> isBiometricsAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      return canCheck && isDeviceSupported;
    } catch (e) {
      debugPrint('Biometrics check failed: $e');
      return false;
    }
  }

  /// Gibt verfügbare Biometrie-Typen zurück
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      debugPrint('Get biometrics failed: $e');
      return [];
    }
  }

  /// Authentifiziert mit Biometrie
  Future<bool> authenticateWithBiometrics({String reason = 'Bitte authentifizieren'}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (e) {
      debugPrint('Biometric auth failed: $e');
      return false;
    }
  }

  /// Aktiviert/Deaktiviert Biometrie
  Future<void> setBiometricsEnabled(bool enabled) async {
    await _storage.write(
      key: _keyBiometricsEnabled,
      value: enabled.toString(),
    );
  }

  /// Prüft ob Biometrie aktiviert ist
  Future<bool> isBiometricsEnabled() async {
    final value = await _storage.read(key: _keyBiometricsEnabled);
    return value == 'true';
  }

  // ==================== App Lock Settings ====================

  /// Aktiviert/Deaktiviert App-Lock
  Future<void> setAppLockEnabled(bool enabled) async {
    await _storage.write(
      key: _keyAppLockEnabled,
      value: enabled.toString(),
    );
  }

  /// Prüft ob App-Lock aktiviert ist
  Future<bool> isAppLockEnabled() async {
    final value = await _storage.read(key: _keyAppLockEnabled);
    return value == 'true';
  }

  /// Setzt Auto-Lock Timeout in Minuten (0 = sofort)
  Future<void> setAutoLockTimeout(int minutes) async {
    await _storage.write(
      key: _keyAutoLockTimeout,
      value: minutes.toString(),
    );
  }

  /// Gibt Auto-Lock Timeout zurück (default: 1 Minute)
  Future<int> getAutoLockTimeout() async {
    final value = await _storage.read(key: _keyAutoLockTimeout);
    return int.tryParse(value ?? '') ?? 1;
  }

  /// Speichert letzte Aktivitätszeit
  Future<void> updateLastActivity() async {
    await _storage.write(
      key: _keyLastActivity,
      value: DateTime.now().millisecondsSinceEpoch.toString(),
    );
  }

  /// Prüft ob Auto-Lock ausgelöst werden soll
  Future<bool> shouldAutoLock() async {
    final isEnabled = await isAppLockEnabled();
    if (!isEnabled) return false;

    final timeoutMinutes = await getAutoLockTimeout();
    if (timeoutMinutes <= 0) return true; // Sofort sperren

    final lastActivityStr = await _storage.read(key: _keyLastActivity);
    if (lastActivityStr == null) return true;

    final lastActivity = DateTime.fromMillisecondsSinceEpoch(
      int.parse(lastActivityStr),
    );
    final elapsed = DateTime.now().difference(lastActivity);

    return elapsed.inMinutes >= timeoutMinutes;
  }

  // ==================== Full Authentication Flow ====================

  /// Führt vollständige Authentifizierung durch (Biometrie oder PIN)
  Future<bool> authenticate({String reason = 'Bitte authentifizieren'}) async {
    // Erst Biometrie versuchen wenn aktiviert
    final biometricsEnabled = await isBiometricsEnabled();
    final biometricsAvailable = await isBiometricsAvailable();

    if (biometricsEnabled && biometricsAvailable) {
      final success = await authenticateWithBiometrics(reason: reason);
      if (success) {
        await updateLastActivity();
        return true;
      }
      // Bei Fehlschlag: Fallback auf PIN (wird von UI gehandelt)
      return false;
    }

    // Kein Biometrics - PIN wird von UI abgefragt
    return false;
  }

  // ==================== Data Wipe ====================

  /// Löscht alle sicheren Daten (für Logout/Reset)
  Future<void> wipeAllSecureData() async {
    await _storage.deleteAll();
  }

  /// Löscht nur Auth-Daten (PIN, Biometrics), behält Hive-Key
  Future<void> resetAuthentication() async {
    await removePin();
    await setBiometricsEnabled(false);
    await setAppLockEnabled(false);
  }
}
