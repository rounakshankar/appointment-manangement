import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/token_storage.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// P2 — Patient OTP verification screen.
///
/// Shows masked phone, 6-digit OTP boxes with auto-advance, VERIFY button,
/// countdown resend timer, and an error message slot.
class PatientOtpScreen extends StatefulWidget {
  const PatientOtpScreen({
    super.key,
    required this.phone,
    required this.apiClient,
    required this.tokenStorage,
    required this.onVerified,
    required this.onBack,
  });

  /// The 10-digit phone (without +91 prefix).
  final String phone;
  final ApiClient apiClient;
  final TokenStorage tokenStorage;

  /// Called with the patient_id after successful OTP verification.
  final ValueChanged<String> onVerified;
  final VoidCallback onBack;

  @override
  State<PatientOtpScreen> createState() => _PatientOtpScreenState();
}

class _PatientOtpScreenState extends State<PatientOtpScreen> {
  static const _otpLength = 6;
  static const _resendSeconds = 45;

  final _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final _focusNodes = List.generate(_otpLength, (_) => FocusNode());

  bool _isLoading = false;
  String? _errorMessage;

  int _resendCountdown = _resendSeconds;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Resend timer
  // ---------------------------------------------------------------------------

  void _startResendTimer() {
    _resendCountdown = _resendSeconds;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendCountdown > 0) {
          _resendCountdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _resendOtp() async {
    if (_resendCountdown > 0) return;
    setState(() => _errorMessage = null);
    try {
      await widget.apiClient.dio.post(
        '/v1/auth/request-otp',
        data: {'phone': '+91${widget.phone}'},
      );
      _startResendTimer();
      // Clear boxes
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes.first.requestFocus();
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) setState(() => _errorMessage = err?.message ?? 'Failed to resend OTP.');
    } on ApiError catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to resend OTP.');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // OTP input handling
  // ---------------------------------------------------------------------------

  String get _otpValue =>
      _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.length == _otpLength) {
      // SMS autofill pastes all digits at once into the first field
      for (var i = 0; i < _otpLength; i++) {
        _controllers[i].text = value[i];
      }
      _focusNodes.last.requestFocus();
      _verify();
      return;
    }

    if (value.isNotEmpty && index < _otpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    setState(() => _errorMessage = null);
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
  }

  // ---------------------------------------------------------------------------
  // Verify
  // ---------------------------------------------------------------------------

  Future<void> _verify() async {
    final otp = _otpValue;
    if (otp.length < _otpLength) {
      setState(() => _errorMessage = 'Enter all 6 digits');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiClient.dio.post(
        '/v1/auth/verify-otp',
        data: {
          'phone': '+91${widget.phone}',
          'otp': otp,
        },
      );

      final token = response.data['access_token'] as String?;
      if (token != null) {
        await widget.tokenStorage.saveToken(token);
        // Decode patient_id from JWT payload (sub claim)
        final patientId = _decodeSubFromJwt(token);
        if (mounted) widget.onVerified(patientId);
      } else {
        setState(() => _errorMessage = 'Verification failed. Try again.');
      }
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) setState(() => _errorMessage = err?.message ?? 'Verification failed. Try again.');
    } on ApiError catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Verification failed. Try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Decode the `sub` claim from a JWT without verifying the signature.
  String _decodeSubFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return '';
      final payload = parts[1];
      // Add padding if needed
      final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
      final decoded = utf8.decode(base64Url.decode(padded));
      final json = jsonDecode(decoded) as Map<String, dynamic>;
      return json['sub'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String get _maskedPhone {
    final p = widget.phone;
    if (p.length < 4) return '+91 $p';
    return '+91 ••••••${p.substring(p.length - 4)}';
  }

  String get _resendLabel {
    if (_resendCountdown > 0) {
      final mm = (_resendCountdown ~/ 60).toString().padLeft(2, '0');
      final ss = (_resendCountdown % 60).toString().padLeft(2, '0');
      return 'Resend OTP in $mm:$ss';
    }
    return 'Resend OTP';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral50,
      appBar: AppBar(
        backgroundColor: AppColors.neutral50,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.neutral900),
          onPressed: widget.onBack,
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              elevation: 1,
              color: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.sms_outlined,
                      size: 40,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 12),
                    const Text('Verify OTP', style: AppTypography.heading2),
                    const SizedBox(height: 8),
                    Text(
                      'Enter the 6-digit code sent to',
                      style: AppTypography.body.copyWith(
                        color: AppColors.neutral600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _maskedPhone,
                      style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.neutral900,
                      ),
                    ),
                    const SizedBox(height: 28),
                    // 6-digit OTP boxes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(_otpLength, (i) {
                        return _OtpBox(
                          controller: _controllers[i],
                          focusNode: _focusNodes[i],
                          enabled: !_isLoading,
                          isFirst: i == 0,
                          onChanged: (v) => _onDigitChanged(i, v),
                          onKeyEvent: (e) => _onKeyEvent(i, e),
                        );
                      }),
                    ),
                    // Error slot
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: _errorMessage != null
                          ? Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                _errorMessage!,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.danger,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _verify,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.surface,
                          disabledBackgroundColor:
                              AppColors.primary.withValues(alpha: 0.6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.surface,
                                ),
                              )
                            : const Text('VERIFY'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _resendCountdown == 0 ? _resendOtp : null,
                      child: Text(
                        _resendLabel,
                        style: AppTypography.caption.copyWith(
                          color: _resendCountdown == 0
                              ? AppColors.primary
                              : AppColors.neutral600,
                          fontWeight: _resendCountdown == 0
                              ? FontWeight.w600
                              : FontWeight.w400,
                          decoration: _resendCountdown == 0
                              ? TextDecoration.underline
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Single OTP digit box
// ---------------------------------------------------------------------------

class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.isFirst,
    required this.onChanged,
    required this.onKeyEvent,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool isFirst;
  final ValueChanged<String> onChanged;
  final ValueChanged<KeyEvent> onKeyEvent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 52,
      child: KeyboardListener(
        focusNode: FocusNode(),
        onKeyEvent: onKeyEvent,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          // Allow pasting full OTP into first box
          maxLength: isFirst ? 6 : 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppTypography.heading2.copyWith(color: AppColors.neutral900),
          decoration: InputDecoration(
            counterText: '',
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.neutral200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }
}
