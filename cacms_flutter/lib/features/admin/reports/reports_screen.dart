import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_toast.dart';

class DailyReport {
  DailyReport({
    required this.reportDate,
    required this.totalAppointments,
    required this.scheduled,
    required this.inProgress,
    required this.completedVisits,
    required this.cancelled,
    required this.noShow,
    required this.totalCollection,
    required this.paidCollection,
    required this.pendingCollection,
    required this.partialCollection,
  });

  final DateTime reportDate;
  final int totalAppointments;
  final int scheduled;
  final int inProgress;
  final int completedVisits;
  final int cancelled;
  final int noShow;
  final double totalCollection;
  final double paidCollection;
  final double pendingCollection;
  final double partialCollection;

  factory DailyReport.fromJson(Map<String, dynamic> json) => DailyReport(
        reportDate: DateTime.parse(json['report_date'] as String),
        totalAppointments: json['total_appointments'] as int? ?? 0,
        scheduled: json['scheduled'] as int? ?? 0,
        inProgress: json['in_progress'] as int? ?? 0,
        completedVisits: json['completed_visits'] as int? ?? 0,
        cancelled: json['cancelled'] as int? ?? 0,
        noShow: json['no_show'] as int? ?? 0,
        totalCollection: double.parse(json['total_collection'].toString()),
        paidCollection: double.parse(json['paid_collection'].toString()),
        pendingCollection: double.parse(json['pending_collection'].toString()),
        partialCollection: double.parse(json['partial_collection'].toString()),
      );
}

class BackupStatus {
  BackupStatus({
    required this.backupDir,
    required this.exists,
    required this.count,
    this.latestFile,
    this.latestSizeBytes,
  });

  final String backupDir;
  final bool exists;
  final int count;
  final String? latestFile;
  final int? latestSizeBytes;

  factory BackupStatus.fromJson(Map<String, dynamic> json) => BackupStatus(
        backupDir: json['backup_dir'] as String? ?? '',
        exists: json['backup_dir_exists'] as bool? ?? false,
        count: json['backup_count'] as int? ?? 0,
        latestFile: json['latest_backup_file'] as String?,
        latestSizeBytes: json['latest_backup_size_bytes'] as int?,
      );
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.apiClient});
  final ApiClient apiClient;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static final _dateFmt = DateFormat('yyyy-MM-dd');
  static final _prettyDateFmt = DateFormat('EEE, d MMM yyyy');
  static final _moneyFmt = NumberFormat.currency(locale: 'en_IN', symbol: 'Rs ', decimalDigits: 0);

  DateTime _selectedDate = DateTime.now();
  DailyReport? _report;
  BackupStatus? _backup;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final date = _dateFmt.format(_selectedDate);
      final responses = await Future.wait([
        widget.apiClient.dio.get('/v1/reports/daily', queryParameters: {'report_date': date}),
        widget.apiClient.dio.get('/v1/ops/backup-status'),
      ]);
      if (mounted) {
        setState(() {
          _report = DailyReport.fromJson(responses[0].data as Map<String, dynamic>);
          _backup = BackupStatus.fromJson(responses[1].data as Map<String, dynamic>);
          _loading = false;
        });
      }
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) {
        setState(() => _loading = false);
        AppToast.show(context, message: err?.message ?? 'Failed to load reports', type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        AppToast.show(context, message: 'Failed to load reports', type: ToastType.error);
      }
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final backup = _backup;
    return Scaffold(
      backgroundColor: AppColors.neutral50,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetch,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _DateCard(
                    label: _prettyDateFmt.format(_selectedDate),
                    onPick: _pickDate,
                  ),
                  const SizedBox(height: 12),
                  if (report != null) ...[
                    Row(
                      children: [
                        Expanded(child: _MetricCard(label: 'Appointments', value: '${report.totalAppointments}', color: AppColors.primary)),
                        const SizedBox(width: 10),
                        Expanded(child: _MetricCard(label: 'Completed', value: '${report.completedVisits}', color: AppColors.success)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _MetricCard(label: 'Collection', value: _moneyFmt.format(report.totalCollection), color: AppColors.accent)),
                        const SizedBox(width: 10),
                        Expanded(child: _MetricCard(label: 'Paid', value: _moneyFmt.format(report.paidCollection), color: AppColors.success)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _BreakdownCard(report: report, moneyFmt: _moneyFmt),
                  ],
                  const SizedBox(height: 12),
                  if (backup != null) _BackupCard(status: backup),
                ],
              ),
            ),
    );
  }
}

class _DateCard extends StatelessWidget {
  const _DateCard({required this.label, required this.onPick});
  final String label;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: const Icon(Icons.calendar_month_outlined, color: AppColors.primary),
        title: Text('Daily Report', style: AppTypography.heading3),
        subtitle: Text(label, style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
        trailing: TextButton(onPressed: onPick, child: const Text('Change')),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

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
            Text(value, style: AppTypography.heading2.copyWith(color: color)),
            const SizedBox(height: 4),
            Text(label, style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
          ],
        ),
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.report, required this.moneyFmt});
  final DailyReport report;
  final NumberFormat moneyFmt;

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
            Text('Breakdown', style: AppTypography.heading3),
            const SizedBox(height: 12),
            _row('Scheduled', '${report.scheduled}'),
            _row('In Progress', '${report.inProgress}'),
            _row('Cancelled', '${report.cancelled}'),
            _row('No Show', '${report.noShow}'),
            const Divider(height: 24, color: AppColors.neutral200),
            _row('Pending Collection', moneyFmt.format(report.pendingCollection)),
            _row('Partial Collection', moneyFmt.format(report.partialCollection)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTypography.body)),
            Text(value, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _BackupCard extends StatelessWidget {
  const _BackupCard({required this.status});
  final BackupStatus status;

  @override
  Widget build(BuildContext context) {
    final healthy = status.exists && status.count > 0;
    return Card(
      elevation: 1,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: (healthy ? AppColors.success : AppColors.danger).withValues(alpha: 0.12),
              child: Icon(
                healthy ? Icons.cloud_done_outlined : Icons.warning_amber_outlined,
                color: healthy ? AppColors.success : AppColors.danger,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Backup Status', style: AppTypography.heading3),
                  Text(
                    healthy ? 'Latest: ${status.latestFile}' : 'No backup found in ${status.backupDir}',
                    style: AppTypography.caption.copyWith(color: AppColors.neutral600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${status.count} backup file(s)',
                    style: AppTypography.caption.copyWith(color: AppColors.neutral600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
