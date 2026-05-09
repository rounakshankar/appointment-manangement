import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/sse_client.dart';
import '../../../core/models/appointment.dart';
import '../../../core/models/consultation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';

// ---------------------------------------------------------------------------
// Patient status response model
// ---------------------------------------------------------------------------

enum _PatientStatusState { noAppointment, scheduled, inProgress, completed }

class _PatientStatus {
  const _PatientStatus({
    required this.state,
    this.appointment,
    this.consultation,
    this.queuePosition,
    this.doctorName,
    this.doctorSpecialization,
    this.lastVisitDate,
    this.lastVisitDoctorName,
    this.lastVisitDiagnosis,
    this.lastVisitNextDate,
  });

  final _PatientStatusState state;
  final Appointment? appointment;
  final Consultation? consultation;
  final int? queuePosition;
  final String? doctorName;
  final String? doctorSpecialization;

  // For no-appointment state
  final DateTime? lastVisitDate;
  final String? lastVisitDoctorName;
  final String? lastVisitDiagnosis;
  final DateTime? lastVisitNextDate;

  factory _PatientStatus.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String? ?? 'no_appointment';

    _PatientStatusState state;
    switch (statusStr) {
      case 'scheduled':
        state = _PatientStatusState.scheduled;
        break;
      case 'in-progress':
        state = _PatientStatusState.inProgress;
        break;
      case 'completed':
        state = _PatientStatusState.completed;
        break;
      default:
        state = _PatientStatusState.noAppointment;
    }

    Appointment? appt;
    if (json['appointment'] != null) {
      appt = Appointment.fromJson(json['appointment'] as Map<String, dynamic>);
    }

    Consultation? consult;
    if (json['consultation'] != null) {
      consult =
          Consultation.fromJson(json['consultation'] as Map<String, dynamic>);
    }

    final lastVisit = json['last_visit'] as Map<String, dynamic>?;

    return _PatientStatus(
      state: state,
      appointment: appt,
      consultation: consult,
      queuePosition: json['queue_position'] as int?,
      doctorName: json['doctor_name'] as String?,
      doctorSpecialization: json['doctor_specialization'] as String?,
      lastVisitDate: lastVisit?['date'] != null
          ? DateTime.tryParse(lastVisit!['date'] as String)
          : null,
      lastVisitDoctorName: lastVisit?['doctor_name'] as String?,
      lastVisitDiagnosis: lastVisit?['diagnosis'] as String?,
      lastVisitNextDate: lastVisit?['next_visit_date'] != null
          ? DateTime.tryParse(lastVisit!['next_visit_date'] as String)
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Live Status Screen
// ---------------------------------------------------------------------------

/// P3 — Patient live status screen with four distinct UI states.
///
/// Subscribes to `/events/patient/{patient_id}` SSE stream and transitions
/// between states on `status_changed` and `consultation_completed` events.
class PatientLiveStatusScreen extends StatefulWidget {
  const PatientLiveStatusScreen({
    super.key,
    required this.patientId,
    required this.apiClient,
    required this.onLogout,
    this.sseClientFactory,
  });

  final String patientId;
  final ApiClient apiClient;
  final VoidCallback onLogout;

  /// Optional factory for creating the [SseClient]. Defaults to the real
  /// implementation. Inject a stub in tests to avoid real network connections.
  final SseClient Function(String url)? sseClientFactory;

  @override
  State<PatientLiveStatusScreen> createState() =>
      _PatientLiveStatusScreenState();
}

class _PatientLiveStatusScreenState extends State<PatientLiveStatusScreen>
    with SingleTickerProviderStateMixin {
  _PatientStatus? _status;
  bool _isLoading = true;

  SseConnectionState _sseState = SseConnectionState.disconnected;
  SseClient? _sseClient;

  // Pulsing animation for in-progress card
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _fetchStatus();
    _connectSse();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _sseClient?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  Future<void> _fetchStatus() async {
    try {
      final resp = await widget.apiClient.dio.post(
        '/v1/patient/appointment-status',
        data: {'patient_id': widget.patientId},
      );
      if (mounted) {
        setState(() {
          _status = _PatientStatus.fromJson(
              resp.data as Map<String, dynamic>);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // SSE
  // ---------------------------------------------------------------------------

  void _connectSse() async {
    final baseUrl = widget.apiClient.dio.options.baseUrl;
    final url = '$baseUrl/v1/events/patient/${widget.patientId}';
    final factory = widget.sseClientFactory;
    final token = await widget.apiClient.getToken();
    final sseClient = factory != null
        ? factory(url)
        : SseClient(
            url: url,
            headers: token != null ? {'Authorization': 'Bearer $token'} : {},
          );
    _sseClient = sseClient;

    sseClient.connectionState.listen((state) {
      if (mounted) setState(() => _sseState = state);
    });

    sseClient.events.listen((event) {
      if (event.eventType == 'status_changed' ||
          event.eventType == 'consultation_completed') {
        _fetchStatus();
      }
    });

    sseClient.connect();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral50,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        title: const Text('My Appointment', style: AppTypography.heading3),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchStatus,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: widget.onLogout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchStatus,
              child: _buildBody(),
            ),
      bottomNavigationBar: _bottomBar(),
    );
  }

  Widget _buildBody() {
    final status = _status;
    if (status == null) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          EmptyState(
            icon: Icons.error_outline,
            message: 'Unable to load status',
            subtitle: 'Pull down to retry',
            action: TextButton(
              onPressed: _fetchStatus,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    switch (status.state) {
      case _PatientStatusState.noAppointment:
        return _NoAppointmentView(status: status);
      case _PatientStatusState.scheduled:
        return _ScheduledView(status: status, sseState: _sseState);
      case _PatientStatusState.inProgress:
        return _InProgressView(
          status: status,
          pulseAnimation: _pulseAnimation,
        );
      case _PatientStatusState.completed:
        return _CompletedView(status: status);
    }
  }

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
// State: No Appointment
// ---------------------------------------------------------------------------

class _NoAppointmentView extends StatelessWidget {
  const _NoAppointmentView({required this.status});
  final _PatientStatus status;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        const EmptyState(
          icon: Icons.event_busy_outlined,
          message: 'No appointment today',
          subtitle: 'Visit the clinic to book an appointment',
        ),
        if (status.lastVisitDate != null) ...[
          const SizedBox(height: 8),
          _LastVisitCard(status: status),
        ],
      ],
    );
  }
}

class _LastVisitCard extends StatelessWidget {
  const _LastVisitCard({required this.status});
  final _PatientStatus status;

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    return Card(
      elevation: 1,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'LAST VISIT',
              style: AppTypography.caption.copyWith(
                color: AppColors.neutral600,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            _InfoRow(
              label: 'Date',
              value: fmt.format(status.lastVisitDate!),
            ),
            if (status.lastVisitDoctorName != null)
              _InfoRow(label: 'Doctor', value: status.lastVisitDoctorName!),
            if (status.lastVisitDiagnosis != null)
              _InfoRow(label: 'Diagnosis', value: status.lastVisitDiagnosis!),
            if (status.lastVisitNextDate != null)
              _InfoRow(
                label: 'Next Visit',
                value: fmt.format(status.lastVisitNextDate!),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// State: Scheduled
// ---------------------------------------------------------------------------

class _ScheduledView extends StatelessWidget {
  const _ScheduledView({
    required this.status,
    required this.sseState,
  });

  final _PatientStatus status;
  final SseConnectionState sseState;

  @override
  Widget build(BuildContext context) {
    final appt = status.appointment;
    final queuePos = status.queuePosition ?? appt?.queueNumber ?? 0;
    final doctorQueuePos = status.queuePosition != null
        ? status.queuePosition! - 1
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 24),
        Center(
          child: QueueNumberDisplay(
            queueNumber: queuePos,
            label: 'Your Queue #',
            size: QueueNumberSize.large,
          ),
        ),
        const SizedBox(height: 16),
        if (status.doctorName != null)
          Center(
            child: Text(
              doctorQueuePos != null && doctorQueuePos > 0
                  ? 'Dr. ${status.doctorName} is on #${doctorQueuePos.toString().padLeft(3, '0')}'
                  : 'Dr. ${status.doctorName}',
              style: AppTypography.body.copyWith(color: AppColors.neutral600),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            'Please wait — you will be called shortly',
            style: AppTypography.caption.copyWith(color: AppColors.neutral600),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 32),
        Card(
          elevation: 1,
          color: AppColors.primaryLight,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.info_outline,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Stay nearby. You will receive a live update when it\'s your turn.',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// State: In-Progress
// ---------------------------------------------------------------------------

class _InProgressView extends StatelessWidget {
  const _InProgressView({
    required this.status,
    required this.pulseAnimation,
  });

  final _PatientStatus status;
  final Animation<double> pulseAnimation;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 40),
        ScaleTransition(
          scale: pulseAnimation,
          child: Card(
            elevation: 3,
            color: const Color(0xFF1E40AF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              child: Column(
                children: [
                  const Icon(
                    Icons.play_circle_filled,
                    color: AppColors.surface,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '▶ You are being seen now',
                    style: AppTypography.heading2.copyWith(
                      color: AppColors.surface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (status.doctorName != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      status.doctorName!,
                      style: AppTypography.body.copyWith(
                        color: AppColors.surface.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (status.doctorSpecialization != null)
                      Text(
                        status.doctorSpecialization!,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.surface.withValues(alpha: 0.7),
                        ),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// State: Completed
// ---------------------------------------------------------------------------

class _CompletedView extends StatelessWidget {
  const _CompletedView({required this.status});
  final _PatientStatus status;

  @override
  Widget build(BuildContext context) {
    final consult = status.consultation;
    final fmt = DateFormat('d MMM yyyy');
    final appt = status.appointment;

    double total = 0;
    if (consult != null) {
      for (final s in consult.services) {
        total += s.total ?? (s.priceApplied * s.quantity);
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 28),
            const SizedBox(width: 8),
            Text('Visit complete ✓', style: AppTypography.heading2),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 1,
          color: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VISIT SUMMARY',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.neutral600,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (appt != null)
                  _InfoRow(
                    label: 'Date',
                    value: fmt.format(appt.scheduledDate),
                  ),
                if (status.doctorName != null)
                  _InfoRow(label: 'Doctor', value: status.doctorName!),
                if (consult != null) ...[
                  _InfoRow(label: 'Diagnosis', value: consult.diagnosis),
                  if (consult.notes != null && consult.notes!.isNotEmpty)
                    _InfoRow(label: 'Notes', value: consult.notes!),
                ],
                if (consult != null && consult.services.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.neutral200),
                  const SizedBox(height: 8),
                  Text(
                    'Services',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.neutral600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...consult.services.map((s) => _ServiceLineItem(service: s)),
                  const Divider(color: AppColors.neutral200),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '₹${total.toStringAsFixed(2)}',
                          style: AppTypography.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (consult?.nextVisitDate != null) ...[
                  const Divider(color: AppColors.neutral200),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.event_outlined,
                          size: 16, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Text(
                        'Next Visit: ${fmt.format(consult!.nextVisitDate!)}',
                        style: AppTypography.body.copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared sub-widgets
// ---------------------------------------------------------------------------

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.neutral600,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: AppTypography.body),
          ),
        ],
      ),
    );
  }
}

class _ServiceLineItem extends StatelessWidget {
  const _ServiceLineItem({required this.service});
  final ConsultationService service;

  @override
  Widget build(BuildContext context) {
    final lineTotal = service.total ?? (service.priceApplied * service.quantity);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              service.serviceName ?? 'Service',
              style: AppTypography.body,
            ),
          ),
          Text(
            '${service.quantity} × ₹${service.priceApplied.toStringAsFixed(2)}',
            style: AppTypography.caption.copyWith(color: AppColors.neutral600),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 72,
            child: Text(
              '₹${lineTotal.toStringAsFixed(2)}',
              style: AppTypography.body,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
