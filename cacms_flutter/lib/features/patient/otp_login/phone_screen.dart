import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/api/api_client.dart';
import 'package:dio/dio.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// P1 — Patient OTP phone entry screen.
///
/// Shows CACMS logo, "Patient Portal" subtitle, +91 prefix phone input,
/// SEND OTP button, and a privacy note.
class PatientPhoneScreen extends StatefulWidget {
  const PatientPhoneScreen({
    super.key,
    required this.apiClient,
    required this.onOtpSent,
  });

  final ApiClient apiClient;

  /// Called with the entered phone number when OTP is successfully sent.
  final ValueChanged<String> onOtpSent;

  @override
  State<PatientPhoneScreen> createState() => _PatientPhoneScreenState();
}

class _PatientPhoneScreenState extends State<PatientPhoneScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  bool get _isPhoneValid => _phoneController.text.trim().length == 10;

  Future<void> _sendOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      setState(() => _errorMessage = 'Enter a valid 10-digit phone number');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await widget.apiClient.dio.post(
        '/v1/auth/request-otp',
        data: {'phone': '+91$phone'},
      );
      if (mounted) widget.onOtpSent(phone);
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) setState(() => _errorMessage = err?.message ?? 'Failed to send OTP. Please try again.');
    } on ApiError catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Failed to send OTP. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral50,
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
                      Icons.health_and_safety_outlined,
                      size: 48,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: 8),
                    const Text('CACMS', style: AppTypography.heading1),
                    const SizedBox(height: 4),
                    Text(
                      'Patient Portal',
                      style: AppTypography.body.copyWith(
                        color: AppColors.neutral600,
                      ),
                    ),
                    const SizedBox(height: 32),
                    // Phone input with +91 prefix
                    TextField(
                      controller: _phoneController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(),
                        prefixText: '+91 ',
                        prefixStyle: TextStyle(
                          color: AppColors.neutral900,
                          fontWeight: FontWeight.w500,
                        ),
                        hintText: '9876543210',
                      ),
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() => _errorMessage = null),
                      onSubmitted: (_) => _isLoading ? null : _sendOtp(),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _sendOtp,
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
                            : const Text('SEND OTP'),
                      ),
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.danger,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: AppTypography.body.copyWith(
                            color: AppColors.surface,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Your phone number is used only for appointment verification and will never be shared.',
                      style: AppTypography.caption.copyWith(
                        color: AppColors.neutral600,
                      ),
                      textAlign: TextAlign.center,
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
