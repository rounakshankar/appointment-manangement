import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../auth/token_storage.dart';
import '../models/auth.dart';
import '../../features/setup/server_setup_screen.dart' show kServerUrlStorageKey;

/// Typed error parsed from the backend error envelope:
/// { "error_code": "...", "message": "...", "detail": {} }
class ApiError implements Exception {
  const ApiError({
    required this.errorCode,
    required this.message,
    this.detail,
    this.statusCode,
  });

  final String errorCode;
  final String message;
  final dynamic detail;
  final int? statusCode;

  factory ApiError.fromJson(Map<String, dynamic> json, {int? statusCode}) =>
      ApiError(
        errorCode: json['error_code'] as String? ?? 'UNKNOWN_ERROR',
        message: json['message'] as String? ?? 'An unexpected error occurred.',
        detail: json['detail'],
        statusCode: statusCode,
      );

  @override
  String toString() => 'ApiError($errorCode): $message';
}

/// Dio-based HTTP client for the CACMS backend.
///
/// - Injects the stored JWT/OTP token as `Authorization: Bearer <token>` on
///   every request via [_AuthInterceptor].
/// - Parses backend error envelopes into typed [ApiError] exceptions via
///   [_ErrorInterceptor].
class ApiClient {
  ApiClient({
    required String baseUrl,
    required TokenStorage tokenStorage,
    Dio? dio,
  })  : _tokenStorage = tokenStorage,
        _dio = dio ?? Dio(BaseOptions(baseUrl: baseUrl)) {
    _dio.interceptors.addAll([
      _AuthInterceptor(tokenStorage),
      _ErrorInterceptor(),
    ]);
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;

  Dio get dio => _dio;

  /// Get the current auth token from secure storage.
  Future<String?> getToken() => _tokenStorage.getToken();

  /// Unwrap an [ApiError] from a [DioException] thrown by the error interceptor.
  static ApiError? unwrapError(Object e) {
    if (e is ApiError) return e;
    if (e is DioException && e.error is ApiError) return e.error as ApiError;
    return null;
  }

  /// Static async factory — reads the backend URL from secure storage.
  ///
  /// Returns null if no URL has been saved yet (caller should show ServerSetupScreen).
  static Future<ApiClient?> create(TokenStorage tokenStorage) async {
    const storage = FlutterSecureStorage();
    final url = await storage.read(key: kServerUrlStorageKey);
    if (url == null || url.isEmpty) return null;
    return ApiClient(baseUrl: url, tokenStorage: tokenStorage);
  }

  /// Register a new clinic and get owner access token.
  Future<ClinicRegistrationResponse> registerClinic(ClinicRegistrationRequest request) async {
    final response = await _dio.post('/v1/auth/register-clinic', data: request.toJson());
    return ClinicRegistrationResponse.fromJson(response.data);
  }

  /// Login with username/password and get token.
  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await _dio.post('/v1/auth/login', data: {
      'username': username,
      'password': password,
    });
    return response.data as Map<String, dynamic>;
  }
}

// ---------------------------------------------------------------------------
// Auth interceptor — injects Bearer token from secure storage
// ---------------------------------------------------------------------------

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._tokenStorage);

  final TokenStorage _tokenStorage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _tokenStorage.getToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

// ---------------------------------------------------------------------------
// Error interceptor — converts DioException into ApiError
// ---------------------------------------------------------------------------

class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null) {
      final data = response.data;
      if (data is Map<String, dynamic>) {
        // Phase 0 API: top-level { error_code, message, detail }
        // Legacy: { detail: { error_code, message } } or string detail
        final Map<String, dynamic> errorData;
        if (data['error_code'] != null) {
          errorData = data;
        } else if (data['detail'] is Map<String, dynamic> &&
            (data['detail'] as Map<String, dynamic>)['error_code'] != null) {
          errorData = data['detail'] as Map<String, dynamic>;
        } else if (data['detail'] is Map<String, dynamic>) {
          errorData = data['detail'] as Map<String, dynamic>;
        } else {
          errorData = data;
        }
        handler.reject(
          DioException(
            requestOptions: err.requestOptions,
            response: response,
            error: ApiError.fromJson(errorData, statusCode: response.statusCode),
          ),
        );
        return;
      }
      handler.reject(
        DioException(
          requestOptions: err.requestOptions,
          response: response,
          error: ApiError(
            errorCode: 'HTTP_ERROR',
            message: 'Request failed with status ${response.statusCode}.',
            statusCode: response.statusCode,
          ),
        ),
      );
      return;
    }
    // Network / timeout errors
    handler.reject(
      DioException(
        requestOptions: err.requestOptions,
        error: ApiError(
          errorCode: 'NETWORK_ERROR',
          message: err.message ?? 'A network error occurred.',
        ),
      ),
    );
  }
}
