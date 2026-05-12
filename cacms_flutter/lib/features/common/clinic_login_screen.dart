import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/token_storage.dart';

class ClinicLoginScreen extends StatefulWidget {
  const ClinicLoginScreen({
    super.key,
    required this.apiClient,
    required this.tokenStorage,
    required this.onClinicSelected,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final Function(String clinicId, String clinicName) onClinicSelected;

  @override
  State<ClinicLoginScreen> createState() => _ClinicLoginScreenState();
}

class _ClinicLoginScreenState extends State<ClinicLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clinicNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _clinicNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await widget.apiClient.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      // Store the token
      await widget.tokenStorage.setToken(response['access_token'] as String);

      // Extract clinic info from token (we'll need to decode JWT)
      // For now, we'll use the clinic name from the form
      final clinicName = _clinicNameController.text.trim();
      final clinicId = response['clinic_id'] as String;

      if (mounted) {
        widget.onClinicSelected(clinicId, clinicName);
      }
    } catch (e) {
      if (mounted) {
        final apiError = ApiClient.unwrapError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiError?.message ?? 'Login failed'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F4F8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1A6B8A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Login to Clinic',
          style: TextStyle(color: Color(0xFF1A6B8A), fontWeight: FontWeight.w600),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.login, size: 48, color: Color(0xFF1A6B8A)),
                const SizedBox(height: 16),
                const Text(
                  'Clinic Login',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A6B8A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Enter your clinic details to continue',
                  style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _buildTextField(
                  controller: _clinicNameController,
                  label: 'Clinic Name',
                  hint: 'Enter your clinic name',
                  validator: (value) {
                    if (value?.trim().isEmpty ?? true) {
                      return 'Clinic name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _usernameController,
                  label: 'Username',
                  hint: 'Enter your username',
                  validator: (value) {
                    if (value?.trim().isEmpty ?? true) {
                      return 'Username is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  hint: 'Enter your password',
                  obscureText: true,
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return 'Password is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A6B8A),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Login',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1A6B8A)),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: validator,
    );
  }
}