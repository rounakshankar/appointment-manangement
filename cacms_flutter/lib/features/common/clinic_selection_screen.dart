import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/token_storage.dart';
import '../../core/models/auth.dart';
import 'clinic_registration_screen.dart';
import 'clinic_login_screen.dart';

class ClinicSelectionScreen extends StatelessWidget {
  const ClinicSelectionScreen({
    super.key,
    required this.apiClient,
    required this.tokenStorage,
    required this.onClinicSelected,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final Function(String clinicId, String clinicName) onClinicSelected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE8F4F8),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_hospital, size: 64, color: Color(0xFF1A6B8A)),
              const SizedBox(height: 12),
              const Text(
                'CACMS',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A6B8A),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Clinic Appointment & Consultation System',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              const Text(
                'Select Your Clinic',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 32),
              _ClinicCard(
                icon: Icons.login,
                title: 'Login to Existing Clinic',
                subtitle: 'Access your clinic account',
                color: const Color(0xFF1A6B8A),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClinicLoginScreen(
                      apiClient: apiClient,
                      tokenStorage: tokenStorage,
                      onClinicSelected: onClinicSelected,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _ClinicCard(
                icon: Icons.add_business,
                title: 'Register New Clinic',
                subtitle: 'Create a new clinic account',
                color: const Color(0xFF2D9E6B),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClinicRegistrationScreen(
                      apiClient: apiClient,
                      tokenStorage: tokenStorage,
                      onClinicRegistered: onClinicSelected,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClinicCard extends StatelessWidget {
  const _ClinicCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFF9CA3AF)),
            ],
          ),
        ),
      ),
    );
  }
}