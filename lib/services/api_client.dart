import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// API Error mit Details
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  ApiException(this.statusCode, this.message, {this.code});

  @override
  String toString() => 'ApiException($statusCode): $message';

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotApproved => code == 'NOT_APPROVED';
  bool get isBlocked => code == 'BLOCKED';
}

/// HTTP Client für VibedTracker API
class ApiClient {
  static const String _defaultBaseUrl = 'https://vibedtracker.lab.halbewahrheit21.de';

  final String baseUrl;
  String? _accessToken;
  String? _refreshToken;

  // Callback für Token-Refresh
  Future<String?> Function()? onTokenRefreshNeeded;
  // Callback wenn Auth fehlschlägt (für Logout)
  void Function()? onAuthFailure;

  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl;

  /// Setzt die Auth-Tokens
  void setTokens({String? accessToken, String? refreshToken}) {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
  }

  /// Prüft ob eingeloggt
  bool get isAuthenticated => _accessToken != null;

  /// Gibt den Refresh Token zurück (für Token-Refresh)
  String? get refreshToken => _refreshToken;

  /// Standard-Headers
  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (_accessToken != null) {
      headers['Authorization'] = 'Bearer $_accessToken';
    }
    return headers;
  }

  /// GET Request
  Future<Map<String, dynamic>> get(String endpoint, {Map<String, String>? queryParams}) async {
    final uri = _buildUri(endpoint, queryParams);
    debugPrint('API GET: $uri');

    final response = await _executeWithRetry(() => http.get(uri, headers: _headers));
    return _handleResponse(response);
  }

  /// POST Request
  Future<Map<String, dynamic>> post(String endpoint, {Map<String, dynamic>? body}) async {
    final uri = _buildUri(endpoint);
    debugPrint('API POST: $uri');

    final response = await _executeWithRetry(
      () => http.post(uri, headers: _headers, body: body != null ? jsonEncode(body) : null),
    );
    return _handleResponse(response);
  }

  /// DELETE Request
  Future<Map<String, dynamic>> delete(String endpoint) async {
    final uri = _buildUri(endpoint);
    debugPrint('API DELETE: $uri');

    final response = await _executeWithRetry(() => http.delete(uri, headers: _headers));
    return _handleResponse(response);
  }

  /// POST ohne Auth (für Login/Register)
  Future<Map<String, dynamic>> postPublic(String endpoint, Map<String, dynamic> body) async {
    final uri = _buildUri(endpoint);
    debugPrint('API POST (public): $uri');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode(body),
    );
    return _handleResponse(response);
  }

  Uri _buildUri(String endpoint, [Map<String, String>? queryParams]) {
    final path = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return Uri.parse('$baseUrl$path').replace(queryParameters: queryParams);
  }

  /// Führt Request aus mit automatischem Token-Refresh bei 401
  Future<http.Response> _executeWithRetry(Future<http.Response> Function() request) async {
    var response = await request();

    // Bei 401: Token refresh versuchen
    if (response.statusCode == 401 && onTokenRefreshNeeded != null && _refreshToken != null) {
      debugPrint('API: Token expired, attempting refresh...');
      final newToken = await onTokenRefreshNeeded!();

      if (newToken != null) {
        _accessToken = newToken;
        // Request wiederholen
        response = await request();
      } else {
        // Refresh fehlgeschlagen
        onAuthFailure?.call();
      }
    }

    return response;
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    debugPrint('API Response: ${response.statusCode}');

    Map<String, dynamic> body;
    try {
      body = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      body = {'error': response.body};
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final error = body['error'] as String? ?? 'Unknown error';
    final code = body['code'] as String?;

    throw ApiException(response.statusCode, error, code: code);
  }

  /// Health Check
  Future<bool> healthCheck() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Health check failed: $e');
      return false;
    }
  }
}
