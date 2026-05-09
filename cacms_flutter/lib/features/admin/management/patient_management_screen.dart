import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/patient.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_toast.dart';

class PatientManagementScreen extends StatefulWidget {
  const PatientManagementScreen({super.key, required this.apiClient});
  final ApiClient apiClient;

  @override
  State<PatientManagementScreen> createState() => _PatientManagementScreenState();
}

class _PatientManagementScreenState extends State<PatientManagementScreen> {
  final _searchCtrl = TextEditingController();
  Patient? _foundPatient;
  bool _searching = false;
  String? _searchError;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _normalisePhone(String raw) {
    var p = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (p.startsWith('+91')) p = p.substring(3);
    if (p.startsWith('91') && p.length == 12) p = p.substring(2);
    if (p.startsWith('0')) p = p.substring(1);
    return '+91$p';
  }

  Future<void> _search() async {
    final raw = _searchCtrl.text.trim();
    if (raw.isEmpty) return;
    setState(() { _searching = true; _foundPatient = null; _searchError = null; });
    try {
      final resp = await widget.apiClient.dio.get(
        '/v1/patients',
        queryParameters: {'phone': _normalisePhone(raw)},
      );
      setState(() { _foundPatient = Patient.fromJson(resp.data as Map<String, dynamic>); });
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      setState(() => _searchError = err?.statusCode == 404
          ? 'No patient found with that number'
          : err?.message ?? 'Search failed');
    } catch (_) {
      setState(() => _searchError = 'Search failed');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _openRegisterForm() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _PatientRegisterForm(
        apiClient: widget.apiClient,
        prefillPhone: _searchCtrl.text.trim(),
      ),
    );
    if (result == true) {
      // Re-search to show the newly registered patient
      _search();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral50,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PATIENT LOOKUP',
                style: AppTypography.caption.copyWith(color: AppColors.neutral600, letterSpacing: 0.8)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+]'))],
                    decoration: InputDecoration(
                      labelText: 'Phone Number',
                      hintText: '9876543210',
                      prefixText: '+91 ',
                      border: const OutlineInputBorder(),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                            )
                          : IconButton(icon: const Icon(Icons.search), onPressed: _search),
                    ),
                    onSubmitted: (_) => _search(),
                    onChanged: (_) => setState(() { _foundPatient = null; _searchError = null; }),
                  ),
                ),
              ],
            ),
            if (_searchError != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.warning),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_searchError!, style: AppTypography.body)),
                    TextButton(
                      onPressed: _openRegisterForm,
                      child: const Text('Register New'),
                    ),
                  ],
                ),
              ),
            ],
            if (_foundPatient != null) ...[
              const SizedBox(height: 16),
              _PatientDetailCard(patient: _foundPatient!),
            ],
            const SizedBox(height: 32),
            const Divider(color: AppColors.neutral200),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('REGISTER NEW PATIENT',
                    style: AppTypography.caption.copyWith(color: AppColors.neutral600, letterSpacing: 0.8)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _openRegisterForm,
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Register New Patient'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Patient detail card
// ---------------------------------------------------------------------------

class _PatientDetailCard extends StatelessWidget {
  const _PatientDetailCard({required this.patient});
  final Patient patient;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    return Card(
      elevation: 1,
      color: AppColors.primaryLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.primary),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                const SizedBox(width: 8),
                Text('Patient Found', style: AppTypography.caption.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            Text(patient.name, style: AppTypography.heading3),
            const SizedBox(height: 4),
            _Row('Phone', patient.phone),
            if (patient.age != null) _Row('Age', '${patient.age}'),
            if (patient.gender != null) _Row('Gender', _cap(patient.gender!)),
            if (patient.address != null && patient.address!.isNotEmpty)
              _Row('Address', patient.address!),
            _Row('Registered', fmt.format(patient.createdAt)),
            _Row('Consent', patient.consentGiven ? 'Given' : 'Not given'),
          ],
        ),
      ),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  Widget _Row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(label, style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
            ),
            Expanded(child: Text(value, style: AppTypography.body)),
          ],
        ),
      );
}

// ---------------------------------------------------------------------------
// Patient registration form
// ---------------------------------------------------------------------------

class _PatientRegisterForm extends StatefulWidget {
  const _PatientRegisterForm({required this.apiClient, this.prefillPhone});
  final ApiClient apiClient;
  final String? prefillPhone;

  @override
  State<_PatientRegisterForm> createState() => _PatientRegisterFormState();
}

class _PatientRegisterFormState extends State<_PatientRegisterForm> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  String _gender = 'male';
  bool _consent = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.prefillPhone != null) {
      var p = widget.prefillPhone!.trim();
      if (p.startsWith('+91')) p = p.substring(3);
      _phoneCtrl.text = p;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  String _normalisePhone(String raw) {
    var p = raw.trim();
    if (p.startsWith('+91')) p = p.substring(3);
    if (p.startsWith('91') && p.length == 12) p = p.substring(2);
    if (p.startsWith('0')) p = p.substring(1);
    return '+91$p';
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final age = int.tryParse(_ageCtrl.text.trim());
    if (name.isEmpty || phone.length < 10) {
      AppToast.show(context, message: 'Name and valid phone are required', type: ToastType.error);
      return;
    }
    if (!_consent) {
      AppToast.show(context, message: 'Patient consent is required', type: ToastType.error);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.apiClient.dio.post('/v1/patients', data: {
        'name': name,
        'phone': _normalisePhone(phone),
        'age': age,
        'gender': _gender,
      });
      if (mounted) {
        AppToast.show(context, message: 'Patient registered', type: ToastType.success);
        Navigator.pop(context, true);
      }
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) AppToast.show(
        context,
        message: err?.errorCode == 'PATIENT_CONFLICT'
            ? 'A patient with this phone already exists'
            : err?.message ?? 'Registration failed',
        type: ToastType.error,
      );
    } catch (_) {
      if (mounted) AppToast.show(context, message: 'Registration failed', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Register New Patient', style: AppTypography.heading2),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full Name *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            decoration: const InputDecoration(
              labelText: 'Phone Number *',
              prefixText: '+91 ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ageCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Age', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _gender,
                  decoration: const InputDecoration(labelText: 'Gender', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (v) { if (v != null) setState(() => _gender = v); },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _consent,
                activeColor: AppColors.primary,
                onChanged: (v) => setState(() => _consent = v ?? false),
              ),
              const Expanded(
                child: Text('Patient consents to data collection and use', style: AppTypography.body),
              ),
            ],
          ),
          const SizedBox(height: 16),
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
                  : const Text('REGISTER PATIENT'),
            ),
          ),
        ],
      ),
    );
  }
}
