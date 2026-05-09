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

/// Top-level admin shell with bottom navigation:
/// Queue | Doctors | Services | Patients | Staff | Reports
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

  static const _tabs = [
    _TabDef(icon: Icons.queue, label: 'Queue'),
    _TabDef(icon: Icons.medical_services_outlined, label: 'Doctors'),
    _TabDef(icon: Icons.medical_information_outlined, label: 'Services'),
    _TabDef(icon: Icons.people_outline, label: 'Patients'),
    _TabDef(icon: Icons.manage_accounts_outlined, label: 'Staff'),
    _TabDef(icon: Icons.analytics_outlined, label: 'Reports'),
  ];

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEE d MMM').format(DateTime.now());

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
        index: _tab,
        children: [
          // Tab 0 — Queue (existing home screen, without its own AppBar)
          AdminHomeScreen(
            apiClient: widget.apiClient,
            tokenStorage: widget.tokenStorage,
            onLogout: widget.onLogout,
          ),
          // Tab 1 — Doctors
          DoctorManagementScreen(apiClient: widget.apiClient),
          // Tab 2 — Services
          ServiceManagementScreen(apiClient: widget.apiClient),
          // Tab 3 — Patients
          PatientManagementScreen(apiClient: widget.apiClient),
          StaffManagementScreen(apiClient: widget.apiClient),
          ReportsScreen(apiClient: widget.apiClient),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withValues(alpha: 0.12),
        destinations: _tabs
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
