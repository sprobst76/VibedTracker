import 'dart:html' as html;
import 'platform_storage.dart';

/// Web implementation using localStorage
/// Note: localStorage is NOT as secure as native keychains!
/// Sensitive data like encryption keys should be handled differently on web.
class WebStorage implements PlatformStorage {
  static const _prefix = 'vibedtracker_';

  String _getKey(String key) => '$_prefix$key';

  @override
  Future<String?> read({required String key}) async {
    return html.window.localStorage[_getKey(key)];
  }

  @override
  Future<void> write({required String key, required String value}) async {
    html.window.localStorage[_getKey(key)] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    html.window.localStorage.remove(_getKey(key));
  }

  @override
  Future<void> deleteAll() async {
    final keysToRemove = <String>[];
    for (var key in html.window.localStorage.keys) {
      if (key.startsWith(_prefix)) {
        keysToRemove.add(key);
      }
    }
    for (var key in keysToRemove) {
      html.window.localStorage.remove(key);
    }
  }

  @override
  Future<bool> containsKey({required String key}) async {
    return html.window.localStorage.containsKey(_getKey(key));
  }
}

PlatformStorage createStorage() => WebStorage();
