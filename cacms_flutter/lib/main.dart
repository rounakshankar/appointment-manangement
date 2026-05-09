import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/api/api_client.dart';
import 'core/auth/token_storage.dart';
import 'core/theme/theme.dart';
import 'features/admin/login/login_screen.dart';
import 'features/admin/admin_shell.dart';
import 'features/doctor/login/login_screen.dart';
import 'features/doctor/queue_dashboard/queue_dashboard_screen.dart';
import 'features/doctor/consultation/consultation_screen.dart';
import 'features/patient/otp_login/phone_screen.dart';
import 'features/patient/otp_login/otp_screen.dart';
import 'features/patient/live_status/live_status_screen.dart';

// ---------------------------------------------------------------------------
// Backend base URL — change this to your server's IP/hostname for beta.
// On Android emulator use 10.0.2.2; on a real device use your machine's LAN IP.
// Override at build time: flutter run --dart-define=BACKEND_URL=http://10.218.231.247:8000
// ---------------------------------------------------------------------------
const String kBackendBaseUrl = String.fromEnvironment(
  'BACKEND_URL',
  defaultValue: 'http://10.22.74.162:8000',
);

// ---------------------------------------------------------------------------
// Shared singletons
// ---------------------------------------------------------------------------

final _tokenStorage = TokenStorage();
final _apiClient = ApiClient(
  baseUrl: kBackendBaseUrl,
  tokenStorage: _tokenStorage,
);

void main() {
  runApp(const ProviderScope(child: CacmsApp()));
}

// ---------------------------------------------------------------------------
// JWT payload decoder (no signature verification — client-side only)
// ---------------------------------------------------------------------------

Map<String, dynamic> _decodeJwtPayload(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return {};
    final payload = parts[1];
    final padded = payload.padRight((payload.length + 3) ~/ 4 * 4, '=');
    final decoded = utf8.decode(base64Url.decode(padded));
    return jsonDecode(decoded) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}

// ---------------------------------------------------------------------------
// Root app — role selection splash
// ---------------------------------------------------------------------------

class CacmsApp extends StatelessWidget {
  const CacmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CACMS',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const _RoleSelectionScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Role selection screen
// ---------------------------------------------------------------------------

class _RoleSelectionScreen extends StatelessWidget {
  const _RoleSelectionScreen();

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
              _RoleCard(
                icon: Icons.admin_panel_settings,
                title: 'Admin',
                subtitle: 'Manage patients & appointments',
                color: const Color(0xFF1A6B8A),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminLoginScreen(
                      apiClient: _apiClient,
                      tokenStorage: _tokenStorage,
                      onLoginSuccess: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminShell(
                            apiClient: _apiClient,
                            tokenStorage: _tokenStorage,
                            onLogout: () async {
                              await _tokenStorage.clearToken();
                              if (context.mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(builder: (_) => const _RoleSelectionScreen()),
                                  (_) => false,
                                );
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: Icons.medical_services,
                title: 'Doctor',
                subtitle: 'View queue & record consultations',
                color: const Color(0xFF2D9E6B),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _DoctorLoginFlow(
                      apiClient: _apiClient,
                      tokenStorage: _tokenStorage,
                      onLogout: () async {
                        await _tokenStorage.clearToken();
                        if (context.mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (_) => const _RoleSelectionScreen()),
                            (_) => false,
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _RoleCard(
                icon: Icons.person,
                title: 'Patient',
                subtitle: 'Check appointment status',
                color: const Color(0xFFF4A261),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PatientPhoneScreen(
                      apiClient: _apiClient,
                      onOtpSent: (phone) => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PatientOtpScreen(
                            phone: phone,
                            apiClient: _apiClient,
                            tokenStorage: _tokenStorage,
                            onVerified: (patientId) => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PatientLiveStatusScreen(
                                  patientId: patientId,
                                  apiClient: _apiClient,
                                  onLogout: () async {
                                    await _tokenStorage.clearToken();
                                    if (context.mounted) {
                                      Navigator.pushAndRemoveUntil(
                                        context,
                                        MaterialPageRoute(builder: (_) => const _RoleSelectionScreen()),
                                        (_) => false,
                                      );
                                    }
                                  },
                                ),
                              ),
                            ),
                            onBack: () => Navigator.pop(context),
                          ),
                        ),
                      ),
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

// ---------------------------------------------------------------------------
// Doctor login flow — handles login then extracts doctor info from JWT
// ---------------------------------------------------------------------------

class _DoctorLoginFlow extends StatefulWidget {
  const _DoctorLoginFlow({
    required this.apiClient,
    required this.tokenStorage,
    required this.onLogout,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final VoidCallback onLogout;

  @override
  State<_DoctorLoginFlow> createState() => _DoctorLoginFlowState();
}

class _DoctorLoginFlowState extends State<_DoctorLoginFlow> {
  DoctorInfo? _doctorInfo;

  void _onLoginSuccess(String token) async {
    // Decode doctor_id from JWT sub claim
    final payload = _decodeJwtPayload(token);
    final doctorId = payload['sub'] as String? ?? '';

    // Fetch doctor details from API
    DoctorInfo info;
    try {
      final resp = await widget.apiClient.dio.get('/v1/doctors');
      final doctors = (resp.data as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .where((d) => !(d['name'] as String).startsWith('Dr. Property'))
          .toList();
      final match = doctors.firstWhere(
        (d) => d['doctor_id'] == doctorId,
        orElse: () => {'doctor_id': doctorId, 'name': 'Doctor', 'specialization': ''},
      );
      info = DoctorInfo(
        doctorId: match['doctor_id'] as String,
        name: match['name'] as String? ?? 'Doctor',
        specialization: match['specialization'] as String? ?? '',
      );
    } catch (_) {
      info = DoctorInfo(
        doctorId: doctorId,
        name: 'Doctor',
        specialization: '',
      );
    }

    if (mounted) {
      setState(() => _doctorInfo = info);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_doctorInfo == null) {
      return DoctorLoginScreen(
        apiClient: widget.apiClient,
        tokenStorage: widget.tokenStorage,
        onLoginSuccess: () async {
          final token = await widget.tokenStorage.getToken();
          if (token != null) _onLoginSuccess(token);
        },
      );
    }

    return DoctorQueueDashboardScreen(
      apiClient: widget.apiClient,
      doctor: _doctorInfo!,
      onStartConsultation: (appointment) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DoctorConsultationScreen(
            apiClient: widget.apiClient,
            appointment: appointment,
            onConsultationComplete: () => Navigator.pop(context),
          ),
        ),
      ),
      onLogout: widget.onLogout,
    );
  }
}

// ---------------------------------------------------------------------------
// Role card widget
// ---------------------------------------------------------------------------

class _RoleCard extends StatelessWidget {
  const _RoleCard({
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
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, size: 16, color: color),
            ],
          ),
        ),
      ),
    );
  }
}
