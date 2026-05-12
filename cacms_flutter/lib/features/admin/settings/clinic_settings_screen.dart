import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_toast.dart';
import '../billing/billing_screen.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _ClinicProfile {
  _ClinicProfile({
    required this.clinicId,
    required this.name,
    required this.plan,
    required this.planStatus,
    this.billingEmail,
    this.clinicAddress,
    this.clinicPhone,
    this.clinicGstin,
    this.clinicRegNumber,
    this.receiptHeader,
    this.receiptFooter,
  });

  final String clinicId;
  final String name;
  final String plan;
  final String planStatus;
  final String? billingEmail;
  final String? clinicAddress;
  final String? clinicPhone;
  final String? clinicGstin;
  final String? clinicRegNumber;
  final String? receiptHeader;
  final String? receiptFooter;

  factory _ClinicProfile.fromJson(Map<String, dynamic> j) => _ClinicProfile(
        clinicId: j['clinic_id'] as String,
        name: j['name'] as String,
        plan: j['plan'] as String,
        planStatus: j['plan_status'] as String,
        billingEmail: j['billing_email'] as String?,
        clinicAddress: j['clinic_address'] as String?,
        clinicPhone: j['clinic_phone'] as String?,
        clinicGstin: j['clinic_gstin'] as String?,
        clinicRegNumber: j['clinic_reg_number'] as String?,
        receiptHeader: j['receipt_header'] as String?,
        receiptFooter: j['receipt_footer'] as String?,
      );
}

class _PlanInfo {
  _PlanInfo({
    required this.plan,
    required this.planStatus,
    required this.features,
    required this.usage,
    this.planExpiresAt,
  });

  final String plan;
  final String planStatus;
  final Map<String, dynamic> features;
  final Map<String, int> usage;
  final DateTime? planExpiresAt;

  factory _PlanInfo.fromJson(Map<String, dynamic> j) => _PlanInfo(
        plan: j['plan'] as String,
        planStatus: j['plan_status'] as String,
        features: (j['features'] as Map<String, dynamic>?) ?? {},
        usage: (j['usage'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
            {},
        planExpiresAt: j['plan_expires_at'] != null
            ? DateTime.tryParse(j['plan_expires_at'] as String)
            : null,
      );
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ClinicSettingsScreen extends StatefulWidget {
  const ClinicSettingsScreen({super.key, required this.apiClient});
  final ApiClient apiClient;

  @override
  State<ClinicSettingsScreen> createState() => _ClinicSettingsScreenState();
}

class _ClinicSettingsScreenState extends State<ClinicSettingsScreen> {
  static final _dateFmt = DateFormat('d MMM yyyy');

  _ClinicProfile? _profile;
  _PlanInfo? _planInfo;
  bool _loading = true;
  bool _saving = false;

  // Form controllers
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _billingEmailCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _gstinCtrl;
  late final TextEditingController _regNumberCtrl;
  late final TextEditingController _receiptHeaderCtrl;
  late final TextEditingController _receiptFooterCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _billingEmailCtrl = TextEditingController();
    _addressCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _gstinCtrl = TextEditingController();
    _regNumberCtrl = TextEditingController();
    _receiptHeaderCtrl = TextEditingController();
    _receiptFooterCtrl = TextEditingController();
    _fetch();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _billingEmailCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _gstinCtrl.dispose();
    _regNumberCtrl.dispose();
    _receiptHeaderCtrl.dispose();
    _receiptFooterCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.apiClient.dio.get('/v1/clinic'),
        widget.apiClient.dio.get('/v1/clinic/plan'),
      ]);
      final profile = _ClinicProfile.fromJson(results[0].data as Map<String, dynamic>);
      final planInfo = _PlanInfo.fromJson(results[1].data as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          _profile = profile;
          _planInfo = planInfo;
          _loading = false;
        });
        _populateControllers(profile);
      }
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) {
        setState(() => _loading = false);
        AppToast.show(context, message: err?.message ?? 'Failed to load settings', type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        AppToast.show(context, message: 'Failed to load settings', type: ToastType.error);
      }
    }
  }

  void _populateControllers(_ClinicProfile p) {
    _nameCtrl.text = p.name;
    _billingEmailCtrl.text = p.billingEmail ?? '';
    _addressCtrl.text = p.clinicAddress ?? '';
    _phoneCtrl.text = p.clinicPhone ?? '';
    _gstinCtrl.text = p.clinicGstin ?? '';
    _regNumberCtrl.text = p.clinicRegNumber ?? '';
    _receiptHeaderCtrl.text = p.receiptHeader ?? '';
    _receiptFooterCtrl.text = p.receiptFooter ?? '';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final body = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'billing_email': _billingEmailCtrl.text.trim().isEmpty ? null : _billingEmailCtrl.text.trim(),
        'clinic_address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'clinic_phone': _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'clinic_gstin': _gstinCtrl.text.trim().isEmpty ? null : _gstinCtrl.text.trim(),
        'clinic_reg_number': _regNumberCtrl.text.trim().isEmpty ? null : _regNumberCtrl.text.trim(),
        'receipt_header': _receiptHeaderCtrl.text.trim().isEmpty ? null : _receiptHeaderCtrl.text.trim(),
        'receipt_footer': _receiptFooterCtrl.text.trim().isEmpty ? null : _receiptFooterCtrl.text.trim(),
      };
      await widget.apiClient.dio.patch('/v1/clinic', data: body);
      if (mounted) {
        AppToast.show(context, message: 'Settings saved', type: ToastType.success);
        await _fetch();
      }
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) {
        AppToast.show(context, message: err?.message ?? 'Failed to save', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _goToBilling() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BillingScreen(apiClient: widget.apiClient),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final plan = _planInfo;

    return Scaffold(
      backgroundColor: AppColors.neutral50,
      appBar: AppBar(
        title: const Text('Clinic Settings'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save', style: TextStyle(color: AppColors.surface, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Section 1: Clinic Profile ──────────────────────────────
              _SectionHeader(title: 'Clinic Profile', subtitle: 'Shown on patient receipts'),
              _SettingsCard(children: [
                _Field(label: 'Clinic Name *', controller: _nameCtrl, validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Name cannot be empty';
                  return null;
                }),
                _Field(label: 'Address', controller: _addressCtrl, maxLines: 3),
                _Field(label: 'Phone', controller: _phoneCtrl, keyboardType: TextInputType.phone),
                _Field(label: 'GSTIN (optional)', controller: _gstinCtrl),
                _Field(label: 'Registration Number (optional)', controller: _regNumberCtrl),
                _Field(label: 'Receipt Header (optional)', controller: _receiptHeaderCtrl,
                    hint: 'Custom text at top of receipt'),
                _Field(label: 'Receipt Footer (optional)', controller: _receiptFooterCtrl,
                    hint: 'e.g. Thank you for visiting'),
              ]),
              const SizedBox(height: 16),

              // ── Section 2: Billing Info ────────────────────────────────
              _SectionHeader(title: 'Billing Info'),
              _SettingsCard(children: [
                _Field(label: 'Billing Email', controller: _billingEmailCtrl,
                    keyboardType: TextInputType.emailAddress),
                if (plan != null) ...[
                  const SizedBox(height: 8),
                  _InfoRow(label: 'Plan', value: plan.plan.toUpperCase()),
                  _InfoRow(
                    label: 'Status',
                    value: plan.planStatus,
                    valueColor: plan.planStatus == 'active'
                        ? AppColors.success
                        : plan.planStatus == 'grace'
                            ? AppColors.danger
                            : AppColors.neutral600,
                  ),
                  if (plan.planExpiresAt != null)
                    _InfoRow(label: 'Expires', value: _dateFmt.format(plan.planExpiresAt!)),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _goToBilling,
                    icon: const Icon(Icons.upgrade),
                    label: const Text('Upgrade Plan'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.primary),
                  ),
                ),
              ]),
              const SizedBox(height: 16),

              // ── Section 3: Usage ───────────────────────────────────────
              if (plan != null) ...[
                _SectionHeader(title: 'Usage This Month'),
                _UsageCard(planInfo: plan),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable widgets
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.heading3),
          if (subtitle != null)
            Text(subtitle!, style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: AppTypography.body)),
          Text(
            value,
            style: AppTypography.body.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.planInfo});
  final _PlanInfo planInfo;

  static const _metered = [
    ('appointment_created', 'Appointments', 'max_appointments_per_month'),
    ('report_export', 'Report Exports', null),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _metered.map((entry) {
            final (eventKey, label, limitKey) = entry;
            final used = planInfo.usage[eventKey] ?? 0;
            final limit = limitKey != null ? planInfo.features[limitKey] : null;
            final limitLabel = limit == null ? '∞' : '$limit';
            final pct = (limit != null && limit > 0) ? (used / limit).clamp(0.0, 1.0) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(label, style: AppTypography.body)),
                      Text('$used / $limitLabel',
                          style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (limit != null)
                    LinearProgressIndicator(
                      value: pct,
                      backgroundColor: AppColors.neutral200,
                      color: pct > 0.9 ? AppColors.danger : AppColors.primary,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
