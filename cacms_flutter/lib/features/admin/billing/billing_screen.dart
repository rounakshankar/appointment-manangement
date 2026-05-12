import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_toast.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _PlanCard {
  _PlanCard({
    required this.name,
    required this.priceInr,
    required this.features,
  });

  final String name;
  final int priceInr;
  final Map<String, dynamic> features;

  factory _PlanCard.fromJson(Map<String, dynamic> j) => _PlanCard(
        name: j['name'] as String,
        priceInr: (j['price_inr'] as num).toInt(),
        features: (j['features'] as Map<String, dynamic>?) ?? {},
      );
}

class _BillingStatus {
  _BillingStatus({
    required this.plan,
    required this.planStatus,
    this.planExpiresAt,
    this.daysRemaining,
    this.message,
  });

  final String plan;
  final String planStatus;
  final DateTime? planExpiresAt;
  final int? daysRemaining;
  final String? message;

  factory _BillingStatus.fromJson(Map<String, dynamic> j) => _BillingStatus(
        plan: j['plan'] as String,
        planStatus: j['plan_status'] as String,
        planExpiresAt: j['plan_expires_at'] != null
            ? DateTime.tryParse(j['plan_expires_at'] as String)
            : null,
        daysRemaining: j['days_remaining'] as int?,
        message: j['message'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, required this.apiClient});
  final ApiClient apiClient;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends State<BillingScreen> {
  static final _dateFmt = DateFormat('d MMM yyyy');

  List<_PlanCard> _plans = [];
  _BillingStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        widget.apiClient.dio.get('/v1/billing/plans'),
        widget.apiClient.dio.get('/v1/billing/status'),
      ]);
      final plansData = (results[0].data['plans'] as List<dynamic>);
      final plans = plansData.map((e) => _PlanCard.fromJson(e as Map<String, dynamic>)).toList();
      final status = _BillingStatus.fromJson(results[1].data as Map<String, dynamic>);
      if (mounted) {
        setState(() {
          _plans = plans;
          _status = status;
          _loading = false;
        });
      }
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) {
        setState(() => _loading = false);
        AppToast.show(context, message: err?.message ?? 'Failed to load billing info', type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        AppToast.show(context, message: 'Failed to load billing info', type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final status = _status;

    return Scaffold(
      backgroundColor: AppColors.neutral50,
      appBar: AppBar(
        title: const Text('Billing & Plans'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
      ),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Current subscription status ────────────────────────────
            if (status != null) ...[
              _StatusCard(status: status, dateFmt: _dateFmt),
              const SizedBox(height: 16),
            ],

            // ── Contact card for upgrade ───────────────────────────────
            if (status != null &&
                (status.plan == 'free' || status.planStatus == 'grace')) ...[
              _ContactCard(isGrace: status.planStatus == 'grace'),
              const SizedBox(height: 16),
            ],

            // ── Plan cards ─────────────────────────────────────────────
            Text('Available Plans', style: AppTypography.heading3),
            const SizedBox(height: 8),
            ..._plans.map((plan) => _PlanCardWidget(
                  plan: plan,
                  isCurrent: plan.name == status?.plan,
                )),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.dateFmt});
  final _BillingStatus status;
  final DateFormat dateFmt;

  Color get _statusColor {
    switch (status.planStatus) {
      case 'active':
        return AppColors.success;
      case 'grace':
        return AppColors.danger;
      default:
        return AppColors.neutral600;
    }
  }

  String get _statusLabel {
    switch (status.planStatus) {
      case 'active':
        return 'Active';
      case 'grace':
        return 'Expired — Grace Period';
      default:
        return status.planStatus.toUpperCase();
    }
  }

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
          children: [
            Text('Current Subscription', style: AppTypography.heading3),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text('Plan', style: AppTypography.body)),
                Text(status.plan.toUpperCase(),
                    style: AppTypography.body.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: Text('Status', style: AppTypography.body)),
                Text(_statusLabel,
                    style: AppTypography.body.copyWith(
                        fontWeight: FontWeight.bold, color: _statusColor)),
              ],
            ),
            if (status.planExpiresAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      status.planStatus == 'grace' ? 'Expired on' : 'Renews on',
                      style: AppTypography.body,
                    ),
                  ),
                  Text(dateFmt.format(status.planExpiresAt!),
                      style: AppTypography.body.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
            if (status.message != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(status.message!,
                    style: AppTypography.caption.copyWith(color: AppColors.danger)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.isGrace});
  final bool isGrace;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: AppColors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isGrace ? 'Renew Your Plan' : 'Upgrade Your Plan',
              style: AppTypography.heading3.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 6),
            Text(
              'To ${isGrace ? 'renew' : 'upgrade'}, contact us directly:',
              style: AppTypography.body,
            ),
            const SizedBox(height: 8),
            // Replace with your actual contact details
            const _ContactRow(icon: Icons.chat, label: 'WhatsApp', value: '+91 98765 43210'),
            const _ContactRow(icon: Icons.email_outlined, label: 'Email', value: 'support@cacms.in'),
            const SizedBox(height: 4),
            Text(
              'We\'ll activate your plan within minutes of receiving payment.',
              style: AppTypography.caption.copyWith(color: AppColors.neutral600),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('$label: ', style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
          Text(value, style: AppTypography.body),
        ],
      ),
    );
  }
}

class _PlanCardWidget extends StatelessWidget {
  const _PlanCardWidget({required this.plan, required this.isCurrent});
  final _PlanCard plan;
  final bool isCurrent;

  static const _featureLabels = {
    'max_doctors': 'Doctors',
    'max_staff': 'Staff users',
    'max_appointments_per_month': 'Appointments/month',
    'can_export_reports': 'Report exports',
    'can_export_pdf': 'PDF exports',
    'multi_branch': 'Multi-branch',
    'api_access': 'API access',
    'lab_integrations': 'Lab integrations',
  };

  String _featureValue(String key, dynamic value) {
    if (value == null) return 'Unlimited';
    if (value is bool) return value ? '✓' : '✗';
    return '$value';
  }

  @override
  Widget build(BuildContext context) {
    final isEnterprise = plan.name == 'enterprise';
    final priceLabel = isEnterprise
        ? 'Contact us'
        : plan.priceInr == 0
            ? 'Free'
            : '₹${plan.priceInr}/month';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: isCurrent ? 3 : 1,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isCurrent
              ? const BorderSide(color: AppColors.primary, width: 2)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      plan.name.toUpperCase(),
                      style: AppTypography.heading3.copyWith(
                        color: isCurrent ? AppColors.primary : null,
                      ),
                    ),
                  ),
                  if (isCurrent)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('Current',
                          style: TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(priceLabel,
                  style: AppTypography.heading2.copyWith(
                    color: plan.priceInr == 0 ? AppColors.neutral600 : AppColors.accent,
                  )),
              const SizedBox(height: 10),
              ...plan.features.entries
                  .where((e) => _featureLabels.containsKey(e.key))
                  .map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(_featureLabels[e.key]!,
                                  style: AppTypography.caption
                                      .copyWith(color: AppColors.neutral600)),
                            ),
                            Text(
                              _featureValue(e.key, e.value),
                              style: AppTypography.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: e.value == false ? AppColors.neutral400 : null,
                              ),
                            ),
                          ],
                        ),
                      )),
            ],
          ),
        ),
      ),
    );
  }
}
