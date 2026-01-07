// Conditional imports for platform-specific implementations
import 'platform_storage_stub.dart'
    if (dart.library.html) 'platform_storage_web.dart'
    if (dart.library.io) 'platform_storage_mobile.dart';

/// Abstract interface for platform-independent secure storage
/// Uses named parameters to match FlutterSecureStorage API
abstract class PlatformStorage {
  /// Read a value from storage
  Future<String?> read({required String key});

  /// Write a value to storage
  Future<void> write({required String key, required String value});

  /// Delete a value from storage
  Future<void> delete({required String key});

  /// Delete all values from storage
  Future<void> deleteAll();

  /// Check if a key exists
  Future<bool> containsKey({required String key});
}

/// Factory to create platform-specific storage instance
PlatformStorage createPlatformStorage() {
  return createStorage();
}
