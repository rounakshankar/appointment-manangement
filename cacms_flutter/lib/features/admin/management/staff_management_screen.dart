import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_toast.dart';
import 'doctor_management_screen.dart';

class StaffUser {
  StaffUser({
    required this.userId,
    required this.username,
    required this.role,
    required this.active,
    this.linkedDoctorId,
  });

  final String userId;
  String username;
  String role;
  bool active;
  String? linkedDoctorId;

  factory StaffUser.fromJson(Map<String, dynamic> json) => StaffUser(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        role: json['role'] as String,
        active: json['active'] as bool? ?? true,
        linkedDoctorId: json['linked_doctor_id'] as String?,
      );
}

class StaffManagementScreen extends StatefulWidget {
  const StaffManagementScreen({super.key, required this.apiClient});
  final ApiClient apiClient;

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  List<StaffUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final resp = await widget.apiClient.dio.get('/v1/users');
      final users = (resp.data as List<dynamic>)
          .map((e) => StaffUser.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _users = users;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({StaffUser? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _StaffForm(
        apiClient: widget.apiClient,
        existing: existing,
      ),
    );
    if (result == true) _fetch();
  }

  Future<void> _toggleActive(StaffUser user) async {
    try {
      await widget.apiClient.dio.patch(
        '/v1/users/${user.userId}',
        data: {'active': !user.active},
      );
      if (mounted) {
        AppToast.show(
          context,
          message: user.active ? 'Staff deactivated' : 'Staff activated',
          type: ToastType.success,
        );
      }
      _fetch();
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) {
        AppToast.show(context, message: err?.message ?? 'Failed', type: ToastType.error);
      }
    } catch (_) {
      if (mounted) AppToast.show(context, message: 'Failed', type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral50,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: _users.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 80),
                      Center(child: Text('No staff users yet', style: AppTypography.body)),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _users.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _StaffCard(
                        user: _users[i],
                        onEdit: () => _openForm(existing: _users[i]),
                        onToggle: () => _toggleActive(_users[i]),
                      ),
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Staff'),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.user, required this.onEdit, required this.onToggle});
  final StaffUser user;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: user.active ? AppColors.surface : AppColors.neutral50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              child: Icon(_roleIcon(user.role), color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(user.username, style: AppTypography.heading3)),
                      if (!user.active) ...[
                        const SizedBox(width: 8),
                        _Badge(label: 'Inactive', color: AppColors.neutral600),
                      ],
                    ],
                  ),
                  Text(
                    user.role.toUpperCase(),
                    style: AppTypography.caption.copyWith(color: AppColors.neutral600),
                  ),
                  if (user.linkedDoctorId != null)
                    Text(
                      'Doctor link: ${user.linkedDoctorId}',
                      style: AppTypography.caption.copyWith(color: AppColors.neutral600),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: AppColors.primary,
              onPressed: onEdit,
            ),
            IconButton(
              icon: Icon(
                user.active ? Icons.toggle_on : Icons.toggle_off,
                size: 28,
                color: user.active ? AppColors.success : AppColors.neutral600,
              ),
              onPressed: onToggle,
            ),
          ],
        ),
      ),
    );
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'owner':
        return Icons.workspace_premium_outlined;
      case 'doctor':
        return Icons.medical_services_outlined;
      case 'receptionist':
        return Icons.support_agent_outlined;
      default:
        return Icons.admin_panel_settings_outlined;
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: AppTypography.caption.copyWith(color: color)),
    );
  }
}

class _StaffForm extends StatefulWidget {
  const _StaffForm({required this.apiClient, this.existing});
  final ApiClient apiClient;
  final StaffUser? existing;

  @override
  State<_StaffForm> createState() => _StaffFormState();
}

class _StaffFormState extends State<_StaffForm> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _role = 'receptionist';
  String? _linkedDoctorId;
  List<DoctorItem> _doctors = [];
  bool _saving = false;
  bool _loadingDoctors = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _usernameCtrl.text = existing.username;
      _role = existing.role;
      _linkedDoctorId = existing.linkedDoctorId;
    }
    _fetchDoctors();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchDoctors() async {
    try {
      final resp = await widget.apiClient.dio.get('/v1/doctors/all');
      final doctors = (resp.data as List<dynamic>)
          .map((e) => DoctorItem.fromJson(e as Map<String, dynamic>))
          .where((d) => d.active)
          .toList();
      if (mounted) {
        setState(() {
          _doctors = doctors;
          _loadingDoctors = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingDoctors = false);
    }
  }

  Future<void> _save() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    if (username.length < 3) {
      AppToast.show(context, message: 'Username must be at least 3 characters', type: ToastType.error);
      return;
    }
    if (widget.existing == null && password.length < 8) {
      AppToast.show(context, message: 'Password must be at least 8 characters', type: ToastType.error);
      return;
    }
    if (_role == 'doctor' && _linkedDoctorId == null) {
      AppToast.show(context, message: 'Select linked doctor', type: ToastType.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'username': username,
        'role': _role,
        'linked_doctor_id': _role == 'doctor' ? _linkedDoctorId : null,
      };
      if (password.isNotEmpty) body['password'] = password;

      if (widget.existing == null) {
        await widget.apiClient.dio.post('/v1/users', data: body);
        if (mounted) AppToast.show(context, message: 'Staff user added', type: ToastType.success);
      } else {
        await widget.apiClient.dio.patch('/v1/users/${widget.existing!.userId}', data: body);
        if (mounted) AppToast.show(context, message: 'Staff user updated', type: ToastType.success);
      }
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) AppToast.show(context, message: err?.message ?? 'Failed', type: ToastType.error);
    } catch (_) {
      if (mounted) AppToast.show(context, message: 'Failed to save staff user', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEdit ? 'Edit Staff User' : 'Add Staff User', style: AppTypography.heading2),
            const SizedBox(height: 20),
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(labelText: 'Username *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: InputDecoration(
                labelText: isEdit ? 'New Password (optional)' : 'Password *',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _role,
              decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'owner', child: Text('Owner')),
                DropdownMenuItem(value: 'admin', child: Text('Admin')),
                DropdownMenuItem(value: 'doctor', child: Text('Doctor')),
                DropdownMenuItem(value: 'receptionist', child: Text('Receptionist')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _role = value;
                  if (_role != 'doctor') _linkedDoctorId = null;
                });
              },
            ),
            if (_role == 'doctor') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _linkedDoctorId,
                decoration: const InputDecoration(labelText: 'Linked Doctor', border: OutlineInputBorder()),
                items: _doctors
                    .map((d) => DropdownMenuItem(value: d.doctorId, child: Text(d.name)))
                    .toList(),
                onChanged: _loadingDoctors ? null : (value) => setState(() => _linkedDoctorId = value),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                    : Text(isEdit ? 'SAVE CHANGES' : 'ADD STAFF'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
