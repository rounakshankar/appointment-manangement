import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for JWT / OTP tokens using flutter_secure_storage.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'cacms_auth_token';

  final FlutterSecureStorage _storage;

  /// Persist [token] securely.
  Future<void> saveToken(String token) =>
      _storage.write(key: _key, value: token);

  /// Return the stored token, or `null` if none exists.
  Future<String?> getToken() => _storage.read(key: _key);

  /// Remove the stored token.
  Future<void> clearToken() => _storage.delete(key: _key);
}
