import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/sse_client.dart';
import '../../../core/models/appointment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';

// ---------------------------------------------------------------------------
// Doctor model — passed in from the auth context
// ---------------------------------------------------------------------------

class DoctorInfo {
  const DoctorInfo({
    required this.doctorId,
    required this.name,
    required this.specialization,
  });

  final String doctorId;
  final String name;
  final String specialization;
}

// ---------------------------------------------------------------------------
// Queue Dashboard Screen
// ---------------------------------------------------------------------------

class DoctorQueueDashboardScreen extends StatefulWidget {
  const DoctorQueueDashboardScreen({
    super.key,
    required this.apiClient,
    required this.doctor,
    required this.onStartConsultation,
    required this.onLogout,
  });

  final ApiClient apiClient;
  final DoctorInfo doctor;

  /// Called with the in-progress [Appointment] when the doctor taps
  /// START CONSULTATION.
  final ValueChanged<Appointment> onStartConsultation;
  final VoidCallback onLogout;

  @override
  State<DoctorQueueDashboardScreen> createState() =>
      _DoctorQueueDashboardScreenState();
}

class _DoctorQueueDashboardScreenState
    extends State<DoctorQueueDashboardScreen> {
  List<Appointment> _queue = [];
  int _total = 0;
  int _done = 0;
  int _remaining = 0;
  Appointment? _inProgress;

  bool _callNextLoading = false;
  bool _queueEmpty = false;

  SseConnectionState _sseState = SseConnectionState.disconnected;
  SseClient? _sseClient;

  // Per-row expanded state for no-show / cancel actions
  final Set<String> _expandedRows = {};

  @override
  void initState() {
    super.initState();
    _fetchQueue();
    _connectSse();
  }

  @override
  void dispose() {
    _sseClient?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data fetching
  // ---------------------------------------------------------------------------

  Future<void> _fetchQueue() async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final resp = await widget.apiClient.dio.get(
        '/v1/appointments/today',
        queryParameters: {
          'doctor_id': widget.doctor.doctorId,
          'date': today,
        },
      );
      final data = resp.data as Map<String, dynamic>;
      final rawQueue = (data['queue'] as List<dynamic>? ?? [])
          .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
          .toList();

      rawQueue.sort((a, b) => a.queueNumber.compareTo(b.queueNumber));

      final inProgress = rawQueue
          .where((a) => a.status == 'in-progress')
          .firstOrNull;

      if (mounted) {
        setState(() {
          _queue = rawQueue;
          _total = data['total'] as int? ?? 0;
          _done = data['completed'] as int? ?? 0;
          _remaining = data['remaining'] as int? ?? 0;
          _inProgress = inProgress;
          _queueEmpty = _remaining == 0 && inProgress == null;
        });
      }
    } catch (_) {
      // silently ignore
    }
  }

  // ---------------------------------------------------------------------------
  // SSE
  // ---------------------------------------------------------------------------

  void _connectSse() async {
    final token = await widget.apiClient.getToken();
    final sseClient = SseClient(
      url: '${widget.apiClient.dio.options.baseUrl}/v1/events/doctor/${widget.doctor.doctorId}',
      headers: token != null ? {'Authorization': 'Bearer $token'} : {},
    );
    _sseClient = sseClient;

    sseClient.connectionState.listen((state) {
      if (mounted) setState(() => _sseState = state);
    });

    sseClient.events.listen((event) {
      if (event.eventType == 'appointment_created' ||
          event.eventType == 'queue_updated') {
        _fetchQueue();
      }
    });

    sseClient.connect();
  }

  // ---------------------------------------------------------------------------
  // Call Next
  // ---------------------------------------------------------------------------

  Future<void> _callNext() async {
    if (_callNextLoading) return;
    setState(() => _callNextLoading = true);

    try {
      // Use the in-progress appointment if available, otherwise use the first
      // scheduled appointment — the backend resolves doctor/date from the ID.
      final apptId = _inProgress?.appointmentId ??
          _queue.where((a) => a.status == 'scheduled').firstOrNull?.appointmentId;

      if (apptId == null) {
        setState(() { _queueEmpty = true; _callNextLoading = false; });
        return;
      }

      await widget.apiClient.dio.patch('/v1/appointments/$apptId/clinical');
      await _fetchQueue();
    } on DioException catch (e) {
      if (!mounted) return;
      final err = ApiClient.unwrapError(e);
      if (err?.errorCode == 'QUEUE_EMPTY') {
        setState(() => _queueEmpty = true);
      } else if (err?.errorCode == 'QUEUE_CONFLICT') {
        AppToast.show(context, message: 'Retry in a moment', type: ToastType.warning);
        await Future<void>.delayed(const Duration(seconds: 1));
      } else {
        AppToast.show(context, message: err?.message ?? 'Failed to advance queue', type: ToastType.error);
      }
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.errorCode == 'QUEUE_EMPTY') {
        setState(() => _queueEmpty = true);
      } else if (e.errorCode == 'QUEUE_CONFLICT') {
        AppToast.show(context, message: 'Retry in a moment', type: ToastType.warning);
        await Future<void>.delayed(const Duration(seconds: 1));
      } else {
        AppToast.show(context, message: e.message, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, message: 'Failed to advance queue', type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _callNextLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // No-show / Cancel
  // ---------------------------------------------------------------------------

  Future<void> _updateStatus(Appointment appt, String status) async {
    try {
      await widget.apiClient.dio.patch(
        '/v1/appointments/${appt.appointmentId}/status',
        data: {'status': status},
      );
      setState(() => _expandedRows.remove(appt.appointmentId));
      await _fetchQueue();
    } on ApiError catch (e) {
      if (mounted) {
        AppToast.show(context, message: e.message, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Failed to update status',
          type: ToastType.error,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('EEE, d MMM yyyy').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppColors.neutral50,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.doctor.name, style: AppTypography.heading3),
            Text(
              widget.doctor.specialization,
              style:
                  AppTypography.caption.copyWith(color: AppColors.primaryLight),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              today,
              style:
                  AppTypography.caption.copyWith(color: AppColors.primaryLight),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {},
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchQueue,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _statsRow()),
            SliverToBoxAdapter(child: _callNextButton()),
            if (_inProgress != null)
              SliverToBoxAdapter(child: _nowSeeingCard(_inProgress!)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'QUEUE',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.neutral600,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            _queueList(),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  // ---------------------------------------------------------------------------
  // Stats row
  // ---------------------------------------------------------------------------

  Widget _statsRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          _StatCard(label: 'Total', value: _total, color: AppColors.primary),
          const SizedBox(width: 8),
          _StatCard(label: 'Done', value: _done, color: AppColors.success),
          const SizedBox(width: 8),
          _StatCard(
              label: 'Remaining',
              value: _remaining,
              color: AppColors.accent),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Call Next button
  // ---------------------------------------------------------------------------

  Widget _callNextButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: _queueEmpty
            ? ElevatedButton.icon(
                onPressed: null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.neutral200,
                  foregroundColor: AppColors.neutral600,
                  disabledBackgroundColor: AppColors.neutral200,
                  disabledForegroundColor: AppColors.neutral600,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text(
                  'Queue Complete ✓',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              )
            : ElevatedButton(
                onPressed: _callNextLoading ? null : _callNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: AppColors.surface,
                  disabledBackgroundColor:
                      AppColors.accent.withValues(alpha: 0.7),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _callNextLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.surface,
                        ),
                      )
                    : const Text(
                        'CALL NEXT PATIENT',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Now Seeing card
  // ---------------------------------------------------------------------------

  Widget _nowSeeingCard(Appointment appt) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        elevation: 2,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFDBEAFE), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.play_circle_filled,
                      color: Color(0xFF1E40AF), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'NOW SEEING',
                    style: AppTypography.caption.copyWith(
                      color: const Color(0xFF1E40AF),
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '#${appt.queueNumber.toString().padLeft(3, '0')}',
                    style: AppTypography.mono.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appt.patientName ?? 'Patient',
                          style: AppTypography.heading3,
                        ),
                        const SizedBox(height: 4),
                        VisitTypeBadge(
                            type: visitTypeFromString(appt.visitType)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => widget.onStartConsultation(appt),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'START CONSULTATION',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Queue list
  // ---------------------------------------------------------------------------

  Widget _queueList() {
    if (_queue.isEmpty) {
      return const SliverFillRemaining(
        child: EmptyState(
          icon: Icons.event_available,
          message: 'No appointments today',
          subtitle: 'New appointments will appear here in real time',
        ),
      );
    }

    // Sort: emergency scheduled first, then by queue_number
    final sorted = List<Appointment>.from(_queue)
      ..sort((a, b) {
        final aIsEmergencyScheduled =
            a.visitType == 'emergency' && a.status == 'scheduled';
        final bIsEmergencyScheduled =
            b.visitType == 'emergency' && b.status == 'scheduled';
        if (aIsEmergencyScheduled && !bIsEmergencyScheduled) return -1;
        if (!aIsEmergencyScheduled && bIsEmergencyScheduled) return 1;
        return a.queueNumber.compareTo(b.queueNumber);
      });

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) {
          if (i.isOdd) {
            return const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: AppColors.neutral200,
            );
          }
          final appt = sorted[i ~/ 2];
          return _QueueRow(
            appt: appt,
            expanded: _expandedRows.contains(appt.appointmentId),
            onToggle: () => setState(() {
              if (_expandedRows.contains(appt.appointmentId)) {
                _expandedRows.remove(appt.appointmentId);
              } else {
                _expandedRows.add(appt.appointmentId);
              }
            }),
            onNoShow: () => _updateStatus(appt, 'no-show'),
            onCancel: () => _updateStatus(appt, 'cancelled'),
          );
        },
        childCount: sorted.length * 2 - 1,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom bar with SSE indicator
  // ---------------------------------------------------------------------------

  Widget _bottomBar() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [SseIndicator(state: _sseState)],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat card
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Card(
        elevation: 1,
        color: AppColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Text(
                value.toString(),
                style: AppTypography.heading1.copyWith(color: color),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style:
                    AppTypography.caption.copyWith(color: AppColors.neutral600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Queue row
// ---------------------------------------------------------------------------

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.appt,
    required this.expanded,
    required this.onToggle,
    required this.onNoShow,
    required this.onCancel,
  });

  final Appointment appt;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onNoShow;
  final VoidCallback onCancel;

  bool get _isTerminal =>
      appt.status == 'completed' ||
      appt.status == 'cancelled' ||
      appt.status == 'no-show';

  bool get _isScheduled => appt.status == 'scheduled';

  @override
  Widget build(BuildContext context) {
    final isEmergency = appt.visitType == 'emergency';

    return InkWell(
      onTap: _isScheduled ? onToggle : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: isEmergency && _isScheduled
            ? AppColors.danger.withValues(alpha: 0.04)
            : AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Queue number
                SizedBox(
                  width: 48,
                  child: Text(
                    '#${appt.queueNumber.toString().padLeft(3, '0')}',
                    style: AppTypography.mono.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _isTerminal
                          ? AppColors.neutral600
                          : AppColors.primary,
                    ),
                  ),
                ),
                if (isEmergency && _isScheduled) ...[
                  const Icon(Icons.bolt, color: AppColors.danger, size: 16),
                  const SizedBox(width: 4),
                ],
                // Patient name
                Expanded(
                  child: Text(
                    appt.patientName ?? 'Patient',
                    style: AppTypography.body.copyWith(
                      color: _isTerminal
                          ? AppColors.neutral600
                          : AppColors.neutral900,
                      decoration:
                          _isTerminal ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                VisitTypeBadge(type: visitTypeFromString(appt.visitType)),
                const SizedBox(width: 8),
                StatusChip(
                    status: appointmentStatusFromString(appt.status)),
                if (_isScheduled) ...[
                  const SizedBox(width: 4),
                  Icon(
                    expanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 18,
                    color: AppColors.neutral600,
                  ),
                ],
              ],
            ),
            // Expanded actions
            if (expanded && _isScheduled)
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 48),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: onNoShow,
                      icon: const Icon(Icons.person_off_outlined, size: 16),
                      label: const Text('No Show'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: const BorderSide(color: AppColors.danger),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        textStyle: AppTypography.caption,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('Cancel'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.neutral600,
                        side: const BorderSide(color: AppColors.neutral600),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        textStyle: AppTypography.caption,
                      ),
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
