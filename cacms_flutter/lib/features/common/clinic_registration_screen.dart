import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/token_storage.dart';
import '../../core/models/auth.dart';

class ClinicRegistrationScreen extends StatefulWidget {
  const ClinicRegistrationScreen({
    super.key,
    required this.apiClient,
    required this.tokenStorage,
    required this.onClinicRegistered,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final Function(String clinicId, String clinicName) onClinicRegistered;

  @override
  State<ClinicRegistrationScreen> createState() => _ClinicRegistrationScreenState();
}

class _ClinicRegistrationScreenState extends State<ClinicRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _clinicNameController = TextEditingController();
  final _ownerUsernameController = TextEditingController();
  final _ownerPasswordController = TextEditingController();
  final _ownerNameController = TextEditingController();
  final _ownerEmailController = TextEditingController();
  final _ownerPhoneController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _clinicNameController.dispose();
    _ownerUsernameController.dispose();
    _ownerPasswordController.dispose();
    _ownerNameController.dispose();
    _ownerEmailController.dispose();
    _ownerPhoneController.dispose();
    super.dispose();
  }

  Future<void> _registerClinic() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final request = ClinicRegistrationRequest(
        clinicName: _clinicNameController.text.trim(),
        ownerUsername: _ownerUsernameController.text.trim(),
        ownerPassword: _ownerPasswordController.text,
        ownerName: _ownerNameController.text.trim().isNotEmpty ? _ownerNameController.text.trim() : null,
        ownerEmail: _ownerEmailController.text.trim().isNotEmpty ? _ownerEmailController.text.trim() : null,
        ownerPhone: _ownerPhoneController.text.trim().isNotEmpty ? _ownerPhoneController.text.trim() : null,
      );

      final response = await widget.apiClient.registerClinic(request);

      // Store the token
      await widget.tokenStorage.setToken(response.accessToken);

      if (mounted) {
        widget.onClinicRegistered(response.clinicId, response.clinicName);
      }
    } catch (e) {
      if (mounted) {
        final apiError = ApiClient.unwrapError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(apiError?.message ?? 'Registration failed'),
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
          'Register Clinic',
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
                const Icon(Icons.add_business, size: 48, color: Color(0xFF1A6B8A)),
                const SizedBox(height: 16),
                const Text(
                  'Create Your Clinic',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A6B8A),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Set up your clinic account to get started',
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
                  controller: _ownerUsernameController,
                  label: 'Owner Username',
                  hint: 'Choose a username for the owner',
                  validator: (value) {
                    if (value?.trim().isEmpty ?? true) {
                      return 'Username is required';
                    }
                    if ((value?.length ?? 0) < 3) {
                      return 'Username must be at least 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _ownerPasswordController,
                  label: 'Owner Password',
                  hint: 'Choose a secure password',
                  obscureText: true,
                  validator: (value) {
                    if (value?.isEmpty ?? true) {
                      return 'Password is required';
                    }
                    if ((value?.length ?? 0) < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _ownerNameController,
                  label: 'Owner Name (Optional)',
                  hint: 'Enter owner full name',
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _ownerEmailController,
                  label: 'Owner Email (Optional)',
                  hint: 'Enter owner email address',
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _ownerPhoneController,
                  label: 'Owner Phone (Optional)',
                  hint: 'Enter owner phone number',
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _registerClinic,
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
                          'Create Clinic',
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
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
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