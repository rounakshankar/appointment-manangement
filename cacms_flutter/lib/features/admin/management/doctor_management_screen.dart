import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_toast.dart';

// ---------------------------------------------------------------------------
// Doctor model
// ---------------------------------------------------------------------------

class DoctorItem {
  DoctorItem({
    required this.doctorId,
    required this.name,
    required this.specialization,
    required this.maxPatientsPerDay,
    required this.active,
  });

  final String doctorId;
  String name;
  String specialization;
  int maxPatientsPerDay;
  bool active;

  factory DoctorItem.fromJson(Map<String, dynamic> j) => DoctorItem(
        doctorId: j['doctor_id'] as String,
        name: j['name'] as String,
        specialization: j['specialization'] as String? ?? '',
        maxPatientsPerDay: j['max_patients_per_day'] as int? ?? 40,
        active: j['active'] as bool? ?? true,
      );
}

// ---------------------------------------------------------------------------
// Doctor Management Screen
// ---------------------------------------------------------------------------

class DoctorManagementScreen extends StatefulWidget {
  const DoctorManagementScreen({super.key, required this.apiClient});
  final ApiClient apiClient;

  @override
  State<DoctorManagementScreen> createState() => _DoctorManagementScreenState();
}

class _DoctorManagementScreenState extends State<DoctorManagementScreen> {
  List<DoctorItem> _doctors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final resp = await widget.apiClient.dio.get('/v1/doctors/all');
      final list = (resp.data as List<dynamic>)
          .map((e) => DoctorItem.fromJson(e as Map<String, dynamic>))
          .where((d) => !d.name.startsWith('Dr. Property'))
          .toList();
      if (mounted) setState(() { _doctors = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm({DoctorItem? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _DoctorForm(
        apiClient: widget.apiClient,
        existing: existing,
      ),
    );
    if (result == true) _fetch();
  }

  Future<void> _toggleActive(DoctorItem doc) async {
    final action = doc.active ? 'deactivate' : 'reactivate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${doc.active ? 'Deactivate' : 'Reactivate'} Doctor'),
        content: Text('${doc.active ? 'Deactivate' : 'Reactivate'} ${doc.name}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(doc.active ? 'Deactivate' : 'Reactivate',
                style: TextStyle(color: doc.active ? AppColors.danger : AppColors.success)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.apiClient.dio.patch(
        '/v1/doctors/${doc.doctorId}',
        data: {'active': !doc.active},
      );
      if (mounted) AppToast.show(context, message: 'Doctor ${action}d', type: ToastType.success);
      _fetch();
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) AppToast.show(context, message: err?.message ?? 'Failed', type: ToastType.error);
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
              child: _doctors.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 80),
                      Center(child: Text('No doctors yet', style: AppTypography.body)),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _doctors.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _DoctorCard(
                        doctor: _doctors[i],
                        onEdit: () => _openForm(existing: _doctors[i]),
                        onToggle: () => _toggleActive(_doctors[i]),
                      ),
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        icon: const Icon(Icons.add),
        label: const Text('Add Doctor'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Doctor card
// ---------------------------------------------------------------------------

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({required this.doctor, required this.onEdit, required this.onToggle});
  final DoctorItem doctor;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: doctor.active ? AppColors.surface : AppColors.neutral50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: doctor.active ? AppColors.neutral200 : AppColors.neutral200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: doctor.active
                  ? AppColors.primary.withValues(alpha: 0.12)
                  : AppColors.neutral200,
              child: Icon(
                Icons.medical_services_outlined,
                color: doctor.active ? AppColors.primary : AppColors.neutral600,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(doctor.name, style: AppTypography.heading3),
                      if (!doctor.active) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.neutral200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Inactive',
                              style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
                        ),
                      ],
                    ],
                  ),
                  if (doctor.specialization.isNotEmpty)
                    Text(doctor.specialization,
                        style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
                  Text('Max ${doctor.maxPatientsPerDay} patients/day',
                      style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: AppColors.primary,
              onPressed: onEdit,
              tooltip: 'Edit',
            ),
            IconButton(
              icon: Icon(
                doctor.active ? Icons.toggle_on : Icons.toggle_off,
                size: 28,
                color: doctor.active ? AppColors.success : AppColors.neutral600,
              ),
              onPressed: onToggle,
              tooltip: doctor.active ? 'Deactivate' : 'Reactivate',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Doctor form (create / edit)
// ---------------------------------------------------------------------------

class _DoctorForm extends StatefulWidget {
  const _DoctorForm({required this.apiClient, this.existing});
  final ApiClient apiClient;
  final DoctorItem? existing;

  @override
  State<_DoctorForm> createState() => _DoctorFormState();
}

class _DoctorFormState extends State<_DoctorForm> {
  final _nameCtrl = TextEditingController();
  final _specCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!.name;
      _specCtrl.text = widget.existing!.specialization;
      _maxCtrl.text = widget.existing!.maxPatientsPerDay.toString();
    } else {
      _maxCtrl.text = '40';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _specCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final max = int.tryParse(_maxCtrl.text.trim()) ?? 40;
    if (name.isEmpty) {
      AppToast.show(context, message: 'Name is required', type: ToastType.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {
        'name': name,
        'specialization': _specCtrl.text.trim().isEmpty ? null : _specCtrl.text.trim(),
        'max_patients_per_day': max,
      };
      if (widget.existing == null) {
        await widget.apiClient.dio.post('/v1/doctors', data: body);
        if (mounted) AppToast.show(context, message: 'Doctor added', type: ToastType.success);
      } else {
        await widget.apiClient.dio.patch('/v1/doctors/${widget.existing!.doctorId}', data: body);
        if (mounted) AppToast.show(context, message: 'Doctor updated', type: ToastType.success);
      }
      if (mounted) Navigator.pop(context, true);
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) AppToast.show(context, message: err?.message ?? 'Failed', type: ToastType.error);
    } catch (_) {
      if (mounted) AppToast.show(context, message: 'Failed to save', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isEdit ? 'Edit Doctor' : 'Add Doctor', style: AppTypography.heading2),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full Name *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _specCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Specialization',
              hintText: 'e.g. General Medicine',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _maxCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Max Patients / Day',
              border: OutlineInputBorder(),
            ),
          ),
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
                  : Text(isEdit ? 'SAVE CHANGES' : 'ADD DOCTOR'),
            ),
          ),
        ],
      ),
    );
  }
}
