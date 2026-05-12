import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Screen for patients to request their medical records by email.
/// Accessible without login — linked from the public queue screen.
class RecordRequestScreen extends StatefulWidget {
  const RecordRequestScreen({
    super.key,
    required this.baseUrl,
    this.prefillPhone,
  });

  final String baseUrl;
  final String? prefillPhone;

  @override
  State<RecordRequestScreen> createState() => _RecordRequestScreenState();
}

class _RecordRequestScreenState extends State<RecordRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _emailCtrl;
  bool _loading = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(text: widget.prefillPhone ?? '');
    _emailCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);

    try {
      final dio = Dio(BaseOptions(baseUrl: widget.baseUrl));
      await dio.post('/v1/public/request-records', data: {
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
      });
      if (mounted) setState(() { _submitted = true; _loading = false; });
    } catch (_) {
      // Always show the same confirmation message regardless of outcome
      // (prevents phone enumeration and avoids confusing error states)
      if (mounted) setState(() { _submitted = true; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral50,
      appBar: AppBar(
        title: const Text('Request My Records'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: _submitted ? _ConfirmationView() : _FormView(
          formKey: _formKey,
          phoneCtrl: _phoneCtrl,
          emailCtrl: _emailCtrl,
          loading: _loading,
          onSubmit: _submit,
        ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  const _FormView({
    required this.formKey,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.loading,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Get your medical records', style: AppTypography.heading2),
          const SizedBox(height: 8),
          Text(
            'Enter your registered phone number and an email address. '
            'We\'ll send a summary of your recent visits.',
            style: AppTypography.body.copyWith(color: AppColors.neutral600),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone Number',
              hintText: '+91 98765 43210',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Phone number is required';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email Address',
              hintText: 'you@example.com',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email address';
              return null;
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: loading ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.surface,
              ),
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.surface),
                    )
                  : const Text('Send My Records'),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Your records will be sent to the email you provide. '
            'The email does not need to match any registered address.',
            style: AppTypography.caption.copyWith(color: AppColors.neutral600),
          ),
        ],
      ),
    );
  }
}

class _ConfirmationView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mark_email_read_outlined,
              size: 72, color: AppColors.success),
          const SizedBox(height: 24),
          Text('Request Sent', style: AppTypography.heading2),
          const SizedBox(height: 12),
          Text(
            'If we have records for this number, we\'ll email them shortly.',
            style: AppTypography.body.copyWith(color: AppColors.neutral600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Queue'),
          ),
        ],
      ),
    );
  }
}
