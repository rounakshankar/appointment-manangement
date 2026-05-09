import 'package:dio/dio.dart';
import '../auth/token_storage.dart';

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
        // Check if error is nested under 'detail' key (FastAPI HTTPException format)
        final errorData = data['detail'] is Map<String, dynamic>
            ? data['detail'] as Map<String, dynamic>
            : data;
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
