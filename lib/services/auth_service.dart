import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';

/// Auth-Status eines Users
enum AuthStatus {
  unknown,       // Noch nicht geprüft
  unauthenticated, // Nicht eingeloggt
  pendingApproval, // Eingeloggt, aber nicht freigeschaltet
  authenticated,   // Eingeloggt und freigeschaltet
  blocked,         // Account gesperrt
}

/// User-Daten vom Server
class User {
  final String id;
  final String email;
  final bool isApproved;
  final bool isAdmin;
  final bool isBlocked;
  final DateTime createdAt;

  User({
    required this.id,
    required this.email,
    required this.isApproved,
    required this.isAdmin,
    required this.isBlocked,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      isApproved: json['is_approved'] as bool? ?? false,
      isAdmin: json['is_admin'] as bool? ?? false,
      isBlocked: json['is_blocked'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  AuthStatus get authStatus {
    if (isBlocked) return AuthStatus.blocked;
    if (!isApproved) return AuthStatus.pendingApproval;
    return AuthStatus.authenticated;
  }
}

/// Service für Authentifizierung
class AuthService {
  final ApiClient _api;
  final FlutterSecureStorage _storage;

  // Storage Keys
  static const _keyAccessToken = 'auth_access_token';
  static const _keyRefreshToken = 'auth_refresh_token';
  static const _keyUser = 'auth_user';
  static const _keyDeviceId = 'auth_device_id';

  User? _currentUser;
  String? _deviceId;

  AuthService({ApiClient? api, FlutterSecureStorage? storage})
      : _api = api ?? ApiClient(),
        _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
          iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
        ) {
    // Token-Refresh Callback
    _api.onTokenRefreshNeeded = _refreshToken;
    _api.onAuthFailure = _handleAuthFailure;
  }

  /// Aktueller User (null wenn nicht eingeloggt)
  User? get currentUser => _currentUser;

  /// Device ID für Sync
  String? get deviceId => _deviceId;

  /// API Client (für CloudSyncService)
  ApiClient get api => _api;

  /// Auth-Status
  AuthStatus get status {
    if (_currentUser == null) return AuthStatus.unauthenticated;
    return _currentUser!.authStatus;
  }

  /// Prüft ob User für Sync berechtigt ist
  bool get canSync => status == AuthStatus.authenticated;

  /// Initialisiert Auth-State aus Secure Storage
  Future<AuthStatus> initialize() async {
    try {
      final accessToken = await _storage.read(key: _keyAccessToken);
      final refreshToken = await _storage.read(key: _keyRefreshToken);
      final userJson = await _storage.read(key: _keyUser);
      _deviceId = await _storage.read(key: _keyDeviceId);

      if (accessToken == null || refreshToken == null) {
        return AuthStatus.unauthenticated;
      }

      _api.setTokens(accessToken: accessToken, refreshToken: refreshToken);

      if (userJson != null) {
        _currentUser = User.fromJson(jsonDecode(userJson));
      }

      // User-Daten aktualisieren
      try {
        await _fetchCurrentUser();
      } catch (e) {
        debugPrint('Failed to refresh user: $e');
        // Bei API-Fehler: Cached User verwenden
      }

      return status;
    } catch (e) {
      debugPrint('Auth initialization failed: $e');
      return AuthStatus.unauthenticated;
    }
  }

  /// Registriert neuen Account
  Future<void> register(String email, String password) async {
    final response = await _api.postPublic('/api/v1/auth/register', {
      'email': email,
      'password': password,
    });

    debugPrint('Registration successful: ${response['message']}');
    // Nach Registrierung muss User einloggen
  }

  /// Login
  Future<User> login(String email, String password, {String? deviceName}) async {
    final response = await _api.postPublic('/api/v1/auth/login', {
      'email': email,
      'password': password,
      'device_name': deviceName ?? 'VibedTracker App',
      'device_type': 'android', // TODO: Platform detection
    });

    final accessToken = response['access_token'] as String;
    final refreshToken = response['refresh_token'] as String;
    final user = User.fromJson(response['user'] as Map<String, dynamic>);
    _deviceId = response['device_id'] as String?;

    // Tokens setzen
    _api.setTokens(accessToken: accessToken, refreshToken: refreshToken);
    _currentUser = user;

    // Persistent speichern
    await _saveAuthState(accessToken, refreshToken, user);

    return user;
  }

  /// Logout
  Future<void> logout() async {
    _api.setTokens(accessToken: null, refreshToken: null);
    _currentUser = null;
    _deviceId = null;

    await _storage.delete(key: _keyAccessToken);
    await _storage.delete(key: _keyRefreshToken);
    await _storage.delete(key: _keyUser);
    await _storage.delete(key: _keyDeviceId);
  }

  /// Aktualisiert User-Daten vom Server
  Future<User> refreshUser() async {
    return await _fetchCurrentUser();
  }

  /// Token refresh
  Future<String?> _refreshToken() async {
    final refreshToken = _api.refreshToken;
    if (refreshToken == null) return null;

    try {
      final response = await _api.postPublic('/api/v1/auth/refresh', {
        'refresh_token': refreshToken,
      });

      final newAccessToken = response['access_token'] as String;

      // Neuen Token speichern
      await _storage.write(key: _keyAccessToken, value: newAccessToken);
      _api.setTokens(accessToken: newAccessToken, refreshToken: refreshToken);

      debugPrint('Token refreshed successfully');
      return newAccessToken;
    } catch (e) {
      debugPrint('Token refresh failed: $e');
      return null;
    }
  }

  void _handleAuthFailure() {
    debugPrint('Auth failure - logging out');
    logout();
  }

  Future<User> _fetchCurrentUser() async {
    final response = await _api.get('/api/v1/me');
    final user = User.fromJson(response);
    _currentUser = user;

    // User aktualisieren
    await _storage.write(key: _keyUser, value: jsonEncode(response));

    return user;
  }

  Future<void> _saveAuthState(String accessToken, String refreshToken, User user) async {
    await _storage.write(key: _keyAccessToken, value: accessToken);
    await _storage.write(key: _keyRefreshToken, value: refreshToken);
    await _storage.write(key: _keyUser, value: jsonEncode({
      'id': user.id,
      'email': user.email,
      'is_approved': user.isApproved,
      'is_admin': user.isAdmin,
      'is_blocked': user.isBlocked,
      'created_at': user.createdAt.toIso8601String(),
    }));
    if (_deviceId != null) {
      await _storage.write(key: _keyDeviceId, value: _deviceId);
    }
  }

  /// Server Health Check
  Future<bool> isServerAvailable() => _api.healthCheck();
}
