import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage key used across the app for the backend URL.
const String kServerUrlStorageKey = 'cacms_server_url';

/// Server Setup Screen — shown on first launch or when no backend URL is stored.
///
/// Allows the user to:
/// 1. Enter a backend URL (HTTP or HTTPS)
/// 2. Test the connection via GET {url}/health
/// 3. Save the URL to secure storage and navigate to the role-selection screen
///
/// Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.7, 4.8
class ServerSetupScreen extends StatefulWidget {
  const ServerSetupScreen({
    super.key,
    required this.onSetupComplete,
    this.initialUrl,
  });

  /// Called with the validated URL after the user saves successfully.
  final void Function(String url) onSetupComplete;

  /// Pre-fill the URL field (used when re-opening from settings).
  final String? initialUrl;

  @override
  State<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends State<ServerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _storage = const FlutterSecureStorage();

  _TestState _testState = _TestState.idle;
  String? _testError;
  bool _testPassed = false;

  @override
  void initState() {
    super.initState();
    _urlController.text = widget.initialUrl ?? '';
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  String? _validateUrl(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter the backend URL';
    }
    final trimmed = value.trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      return 'URL must start with http:// or https://';
    }
    if (uri.host.isEmpty) {
      return 'URL must include a host (e.g. http://192.168.1.10:8000)';
    }
    return null;
  }

  String _normaliseUrl(String url) {
    // Strip trailing slash for consistency
    return url.trim().replaceAll(RegExp(r'/+$'), '');
  }

  // ---------------------------------------------------------------------------
  // Test connection
  // ---------------------------------------------------------------------------

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;

    final url = _normaliseUrl(_urlController.text);

    setState(() {
      _testState = _TestState.loading;
      _testError = null;
      _testPassed = false;
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));

      final response = await dio.get('$url/health');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map && data['status'] == 'ok') {
          setState(() {
            _testState = _TestState.success;
            _testPassed = true;
          });
          return;
        }
      }

      setState(() {
        _testState = _TestState.failure;
        _testError = 'Server responded but health check failed. '
            'Expected {"status": "ok"}, got: ${response.data}';
      });
    } on DioException catch (e) {
      setState(() {
        _testState = _TestState.failure;
        _testError = _friendlyDioError(e);
      });
    } catch (e) {
      setState(() {
        _testState = _TestState.failure;
        _testError = 'Unexpected error: $e';
      });
    }
  }

  String _friendlyDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Connection timed out. Check the URL and that the server is running.';
      case DioExceptionType.connectionError:
        return 'Could not connect. Check the URL and your network.';
      case DioExceptionType.badResponse:
        return 'Server returned ${e.response?.statusCode}. Is this the right URL?';
      default:
        return e.message ?? 'Network error. Check the URL.';
    }
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    if (!_testPassed) return;
    final url = _normaliseUrl(_urlController.text);
    await _storage.write(key: kServerUrlStorageKey, value: url);
    widget.onSetupComplete(url);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F4F8),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  const Icon(
                    Icons.local_hospital,
                    size: 64,
                    color: Color(0xFF1A6B8A),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'CACMS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A6B8A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Server Setup',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Backend Server URL',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF374151),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _urlController,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              onChanged: (_) {
                                // Reset test state when URL changes
                                if (_testPassed || _testState != _TestState.idle) {
                                  setState(() {
                                    _testState = _TestState.idle;
                                    _testPassed = false;
                                    _testError = null;
                                  });
                                }
                              },
                              decoration: InputDecoration(
                                hintText: 'http://192.168.1.10:8000',
                                prefixIcon: const Icon(Icons.link),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: const Color(0xFFF9FAFB),
                              ),
                              validator: _validateUrl,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Examples:\n'
                              '  Local network: http://192.168.1.10:8000\n'
                              '  Cloud server:  https://clinic.yourdomain.com',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Test Connection button
                            OutlinedButton.icon(
                              onPressed: _testState == _TestState.loading
                                  ? null
                                  : _testConnection,
                              icon: _testState == _TestState.loading
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(
                                      _testState == _TestState.success
                                          ? Icons.check_circle_outline
                                          : Icons.wifi_tethering,
                                      color: _testState == _TestState.success
                                          ? const Color(0xFF2D9E6B)
                                          : null,
                                    ),
                              label: Text(
                                _testState == _TestState.loading
                                    ? 'Testing...'
                                    : _testState == _TestState.success
                                        ? 'Connection OK ✓'
                                        : 'Test Connection',
                                style: TextStyle(
                                  color: _testState == _TestState.success
                                      ? const Color(0xFF2D9E6B)
                                      : null,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: BorderSide(
                                  color: _testState == _TestState.success
                                      ? const Color(0xFF2D9E6B)
                                      : const Color(0xFF1A6B8A),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            ),

                            // Error message
                            if (_testError != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: Color(0xFFE63946),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _testError!,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFFE63946),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 16),

                            // Save button — only enabled after successful test
                            ElevatedButton(
                              onPressed: _testPassed ? _save : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1A6B8A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: const Text(
                                'Save & Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TestState { idle, loading, success, failure }
