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
// Patient OTP login screens removed — patients no longer log in.
// Queue info is public via /v1/public/queue/{clinic_id}/{doctor_id}.
// Medical records are delivered by email via /v1/public/request-records.
// Kept in place for reference; replaced by public queue flow (Phase 1 SaaS).
// import 'features/patient/otp_login/phone_screen.dart';
// import 'features/patient/otp_login/otp_screen.dart';
// import 'features/patient/live_status/live_status_screen.dart';
import 'features/common/clinic_selection_screen.dart';
import 'features/setup/server_setup_screen.dart';

// ---------------------------------------------------------------------------
// Shared singletons — initialised in main() after reading secure storage
// ---------------------------------------------------------------------------

final _tokenStorage = TokenStorage();

// ---------------------------------------------------------------------------
// Entry point — async startup reads cacms_server_url from secure storage
// ---------------------------------------------------------------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Try to build ApiClient from stored URL; null = no URL saved yet
  final apiClient = await ApiClient.create(_tokenStorage);

  runApp(ProviderScope(
    child: CacmsApp(initialApiClient: apiClient),
  ));
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
// Root app — routes to ServerSetupScreen or ClinicSelectionScreen
// ---------------------------------------------------------------------------

class CacmsApp extends StatefulWidget {
  const CacmsApp({super.key, required this.initialApiClient});

  final ApiClient? initialApiClient;

  @override
  State<CacmsApp> createState() => _CacmsAppState();
}

class _CacmsAppState extends State<CacmsApp> {
  ApiClient? _apiClient;

  @override
  void initState() {
    super.initState();
    _apiClient = widget.initialApiClient;
  }

  void _onServerConfigured(String url) {
    setState(() {
      _apiClient = ApiClient(baseUrl: url, tokenStorage: _tokenStorage);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CACMS',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: _apiClient == null
          ? ServerSetupScreen(onSetupComplete: _onServerConfigured)
          : ClinicSelectionScreen(
              apiClient: _apiClient!,
              tokenStorage: _tokenStorage,
              onClinicSelected: (clinicId, clinicName) => Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => _RoleSelectionScreen(
                    apiClient: _apiClient!,
                    clinicId: clinicId,
                    clinicName: clinicName,
                  ),
                ),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Role selection screen
// ---------------------------------------------------------------------------

class _RoleSelectionScreen extends StatelessWidget {
  const _RoleSelectionScreen({
    required this.apiClient,
    required this.clinicId,
    required this.clinicName,
  });

  final ApiClient apiClient;
  final String clinicId;
  final String clinicName;

  void _openServerSetup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ServerSetupScreen(
          initialUrl: apiClient.dio.options.baseUrl,
          onSetupComplete: (newUrl) {
            // Pop back — the new URL takes effect on next app restart
            // or the user can restart the app for a full re-init.
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Server URL saved. Restart the app to apply.'),
              ),
            );
          },
        ),
      ),
    );
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
          onPressed: () => Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ClinicSelectionScreen(
                apiClient: apiClient,
                tokenStorage: _tokenStorage,
                onClinicSelected: (newClinicId, newClinicName) => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _RoleSelectionScreen(
                      apiClient: apiClient,
                      clinicId: newClinicId,
                      clinicName: newClinicName,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          clinicName,
          style: const TextStyle(color: Color(0xFF1A6B8A), fontWeight: FontWeight.w600),
        ),
        // Settings gear — opens ServerSetupScreen to change backend URL
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Color(0xFF1A6B8A)),
            tooltip: 'Server Settings',
            onPressed: () => _openServerSetup(context),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_hospital, size: 64, color: Color(0xFF1A6B8A)),
              const SizedBox(height: 12),
              const Text(
                'Select Your Role',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A6B8A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Clinic: $clinicName',
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
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
                      apiClient: apiClient,
                      tokenStorage: _tokenStorage,
                      onLoginSuccess: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AdminShell(
                            apiClient: apiClient,
                            tokenStorage: _tokenStorage,
                            onLogout: () async {
                              await _tokenStorage.clearToken();
                              if (context.mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ClinicSelectionScreen(
                                      apiClient: apiClient,
                                      tokenStorage: _tokenStorage,
                                      onClinicSelected: (newClinicId, newClinicName) => Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => _RoleSelectionScreen(
                                            apiClient: apiClient,
                                            clinicId: newClinicId,
                                            clinicName: newClinicName,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
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
                      apiClient: apiClient,
                      tokenStorage: _tokenStorage,
                      clinicId: clinicId,
                      clinicName: clinicName,
                      onLogout: () async {
                        await _tokenStorage.clearToken();
                        if (context.mounted) {
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClinicSelectionScreen(
                                apiClient: apiClient,
                                tokenStorage: _tokenStorage,
                                onClinicSelected: (newClinicId, newClinicName) => Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _RoleSelectionScreen(
                                      apiClient: apiClient,
                                      clinicId: newClinicId,
                                      clinicName: newClinicName,
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
                icon: Icons.assignment_ind,
                title: 'Doc Assistant',
                subtitle: 'Manage appointments & assist doctors',
                color: const Color(0xFFF4A261),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _DocAssistantLoginScreen(
                      apiClient: apiClient,
                      tokenStorage: _tokenStorage,
                      clinicId: clinicId,
                      clinicName: clinicName,
                      onLoginSuccess: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _DocAssistantDashboard(
                            apiClient: apiClient,
                            tokenStorage: _tokenStorage,
                            clinicId: clinicId,
                            clinicName: clinicName,
                            onLogout: () async {
                              await _tokenStorage.clearToken();
                              if (context.mounted) {
                                Navigator.pushAndRemoveUntil(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ClinicSelectionScreen(
                                      apiClient: apiClient,
                                      tokenStorage: _tokenStorage,
                                      onClinicSelected: (newClinicId, newClinicName) => Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => _RoleSelectionScreen(
                                            apiClient: apiClient,
                                            clinicId: newClinicId,
                                            clinicName: newClinicName,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
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
              // Patient role card removed — patients no longer log in.
              // Queue info is public via the QR code / shared link.
              // See PublicQueueScreen and RecordRequestScreen for the new patient flow.
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
    required this.clinicId,
    required this.clinicName,
    required this.onLogout,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final String clinicId;
  final String clinicName;
  final VoidCallback onLogout;

  @override
  State<_DoctorLoginFlow> createState() => _DoctorLoginFlowState();
}

class _DoctorLoginFlowState extends State<_DoctorLoginFlow> {
  DoctorInfo? _doctorInfo;

  void _onLoginSuccess(String token) async {
    // JWT `sub` is the user_id; doctor queue APIs need linked_doctor_id.
    final payload = _decodeJwtPayload(token);
    final doctorId = payload['linked_doctor_id'] as String? ?? '';

    if (doctorId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This login is not a doctor account (missing linked doctor). '
              'In Admin → Staff, add a user with role Doctor and link the doctor profile.',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    DoctorInfo info;
    try {
      final resp = await widget.apiClient.dio.get('/v1/doctors');
      final doctors = (resp.data as List<dynamic>)
          .map((e) => e as Map<String, dynamic>)
          .where((d) => !(d['name'] as String).startsWith('Dr. Property'))
          .toList();
      Map<String, dynamic>? match;
      for (final d in doctors) {
        if (d['doctor_id'] == doctorId) {
          match = d;
          break;
        }
      }
      if (match != null) {
        info = DoctorInfo(
          doctorId: match['doctor_id'] as String,
          name: match['name'] as String? ?? 'Doctor',
          specialization: match['specialization'] as String? ?? '',
        );
      } else {
        info = DoctorInfo(
          doctorId: doctorId,
          name: 'Doctor',
          specialization: '',
        );
      }
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

// ---------------------------------------------------------------------------
// Doc Assistant Login Screen (Placeholder)
// ---------------------------------------------------------------------------

class _DocAssistantLoginScreen extends StatelessWidget {
  const _DocAssistantLoginScreen({
    required this.apiClient,
    required this.tokenStorage,
    required this.clinicId,
    required this.clinicName,
    required this.onLoginSuccess,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final String clinicId;
  final String clinicName;
  final VoidCallback onLoginSuccess;

  @override
  Widget build(BuildContext context) {
    // TODO: Implement proper doc assistant login screen
    // For now, just show a placeholder that calls onLoginSuccess
    return Scaffold(
      appBar: AppBar(title: const Text('Doc Assistant Login')),
      body: Center(
        child: ElevatedButton(
          onPressed: onLoginSuccess,
          child: const Text('Login (Placeholder)'),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Doc Assistant Dashboard (Placeholder)
// ---------------------------------------------------------------------------

class _DocAssistantDashboard extends StatelessWidget {
  const _DocAssistantDashboard({
    required this.apiClient,
    required this.tokenStorage,
    required this.clinicId,
    required this.clinicName,
    required this.onLogout,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final String clinicId;
  final String clinicName;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    // TODO: Implement proper doc assistant dashboard
    return Scaffold(
      appBar: AppBar(
        title: Text('Doc Assistant - $clinicName'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: onLogout,
          ),
        ],
      ),
      body: const Center(
        child: Text('Doc Assistant Dashboard\n\nTODO: Implement appointment management interface'),
      ),
    );
  }
}
