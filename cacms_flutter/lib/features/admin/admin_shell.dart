import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/token_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'home/home_screen.dart';
import 'management/doctor_management_screen.dart';
import 'management/service_management_screen.dart';
import 'management/patient_management_screen.dart';
import 'management/staff_management_screen.dart';
import 'reports/reports_screen.dart';
import 'backup/backup_screen.dart';
import 'settings/clinic_settings_screen.dart';
import 'billing/billing_screen.dart';

/// Decode the role claim from a JWT without verifying the signature.
/// The token is already trusted (issued by our own backend).
String? _roleFromJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return null;
    // Base64url → base64 padding
    var payload = parts[1];
    payload = payload.replaceAll('-', '+').replaceAll('_', '/');
    while (payload.length % 4 != 0) {
      payload += '=';
    }
    final decoded = utf8.decode(base64Decode(payload));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    return json['role'] as String?;
  } catch (_) {
    return null;
  }
}

/// Top-level admin shell with bottom navigation.
/// Settings and Billing tabs are only shown when the authenticated user
/// has the ``owner`` role — decoded from the JWT in secure storage.
class AdminShell extends StatefulWidget {
  const AdminShell({
    super.key,
    required this.apiClient,
    required this.tokenStorage,
    required this.onLogout,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final VoidCallback onLogout;

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _tab = 0;
  String? _role;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final token = await widget.tokenStorage.getToken();
    if (token != null && mounted) {
      setState(() => _role = _roleFromJwt(token));
    }
  }

  bool get _isOwner => _role == 'owner';

  List<_TabDef> get _tabs {
    return [
      const _TabDef(icon: Icons.queue, label: 'Queue'),
      const _TabDef(icon: Icons.medical_services_outlined, label: 'Doctors'),
      const _TabDef(icon: Icons.medical_information_outlined, label: 'Services'),
      const _TabDef(icon: Icons.people_outline, label: 'Patients'),
      const _TabDef(icon: Icons.manage_accounts_outlined, label: 'Staff'),
      const _TabDef(icon: Icons.backup_outlined, label: 'Backup'),
      const _TabDef(icon: Icons.analytics_outlined, label: 'Reports'),
      if (_isOwner) ...[
        const _TabDef(icon: Icons.settings_outlined, label: 'Settings'),
        const _TabDef(icon: Icons.payment_outlined, label: 'Billing'),
      ],
    ];
  }

  List<Widget> get _screens {
    return [
      AdminHomeScreen(
        apiClient: widget.apiClient,
        tokenStorage: widget.tokenStorage,
        onLogout: widget.onLogout,
      ),
      DoctorManagementScreen(apiClient: widget.apiClient),
      ServiceManagementScreen(apiClient: widget.apiClient),
      PatientManagementScreen(apiClient: widget.apiClient),
      StaffManagementScreen(apiClient: widget.apiClient),
      BackupScreen(apiClient: widget.apiClient),
      ReportsScreen(apiClient: widget.apiClient),
      if (_isOwner) ...[
        ClinicSettingsScreen(apiClient: widget.apiClient),
        BillingScreen(apiClient: widget.apiClient),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEE d MMM').format(DateTime.now());
    final tabs = _tabs;
    final screens = _screens;

    // Clamp _tab in case the tab list shrinks (e.g. role not yet loaded)
    final safeTab = _tab.clamp(0, screens.length - 1);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🏥 CACMS Admin', style: AppTypography.heading3),
            Text('Today: $today',
                style: AppTypography.caption.copyWith(color: AppColors.surface)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: widget.onLogout,
            child: const Text('Logout', style: TextStyle(color: AppColors.surface)),
          ),
        ],
      ),
      body: IndexedStack(
        index: safeTab,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: safeTab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        destinations: tabs
            .map((t) => NavigationDestination(
                  icon: Icon(t.icon),
                  selectedIcon: Icon(t.icon, color: AppColors.primary),
                  label: t.label,
                ))
            .toList(),
      ),
    );
  }
}

class _TabDef {
  const _TabDef({required this.icon, required this.label});
  final IconData icon;
  final String label;
}
