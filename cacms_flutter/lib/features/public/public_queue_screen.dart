import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/api/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_toast.dart';
import '../../features/setup/server_setup_screen.dart' show kServerUrlStorageKey;
import 'record_request_screen.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _QueueStatus {
  _QueueStatus({
    required this.clinicName,
    required this.doctorName,
    this.specialization,
    this.currentQueueNumber,
    required this.totalScheduled,
    required this.estimatedWaitMinutes,
  });

  final String clinicName;
  final String doctorName;
  final String? specialization;
  final int? currentQueueNumber;
  final int totalScheduled;
  final int estimatedWaitMinutes;

  factory _QueueStatus.fromJson(Map<String, dynamic> j) => _QueueStatus(
        clinicName: j['clinic_name'] as String,
        doctorName: j['doctor_name'] as String,
        specialization: j['specialization'] as String?,
        currentQueueNumber: j['current_queue_number'] as int?,
        totalScheduled: (j['total_scheduled'] as num).toInt(),
        estimatedWaitMinutes: (j['estimated_wait_minutes'] as num).toInt(),
      );
}

class _DoctorInfo {
  _DoctorInfo({
    required this.doctorId,
    required this.name,
    this.specialization,
    required this.isAccepting,
  });

  final String doctorId;
  final String name;
  final String? specialization;
  final bool isAccepting;

  factory _DoctorInfo.fromJson(Map<String, dynamic> j) => _DoctorInfo(
        doctorId: j['doctor_id'] as String,
        name: j['name'] as String,
        specialization: j['specialization'] as String?,
        isAccepting: j['is_accepting_patients'] as bool? ?? false,
      );
}

// ---------------------------------------------------------------------------
// SSE connection state
// ---------------------------------------------------------------------------

enum _SseState { connecting, live, reconnecting, disconnected }

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class PublicQueueScreen extends StatefulWidget {
  const PublicQueueScreen({
    super.key,
    required this.clinicId,
    this.doctorId,
  });

  final String clinicId;
  final String? doctorId;

  @override
  State<PublicQueueScreen> createState() => _PublicQueueScreenState();
}

class _PublicQueueScreenState extends State<PublicQueueScreen> {
  String? _baseUrl;
  Dio? _dio;

  String? _clinicName;
  List<_DoctorInfo> _doctors = [];
  String? _selectedDoctorId;
  _QueueStatus? _queueStatus;

  bool _loadingClinic = true;
  bool _loadingQueue = false;
  _SseState _sseState = _SseState.disconnected;

  StreamSubscription<String>? _sseSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    const storage = FlutterSecureStorage();
    final url = await storage.read(key: kServerUrlStorageKey) ?? '';
    _baseUrl = url;
    _dio = Dio(BaseOptions(baseUrl: url));

    if (widget.doctorId != null) {
      _selectedDoctorId = widget.doctorId;
    }

    await _fetchClinicInfo();
    if (_selectedDoctorId != null) {
      await _fetchQueue();
      _connectSse();
    }
  }

  Future<void> _fetchClinicInfo() async {
    setState(() => _loadingClinic = true);
    try {
      final resp = await _dio!.get('/v1/public/clinic/${widget.clinicId}');
      final data = resp.data as Map<String, dynamic>;
      final doctors = (data['doctors'] as List<dynamic>)
          .map((e) => _DoctorInfo.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _clinicName = data['clinic_name'] as String;
          _doctors = doctors;
          _loadingClinic = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingClinic = false);
    }
  }

  Future<void> _fetchQueue() async {
    if (_selectedDoctorId == null) return;
    setState(() => _loadingQueue = true);
    try {
      final resp = await _dio!
          .get('/v1/public/queue/${widget.clinicId}/$_selectedDoctorId');
      final status = _QueueStatus.fromJson(resp.data as Map<String, dynamic>);
      if (mounted) setState(() { _queueStatus = status; _loadingQueue = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingQueue = false);
    }
  }

  void _connectSse() {
    if (_selectedDoctorId == null || _baseUrl == null) return;
    _sseSub?.cancel();
    setState(() => _sseState = _SseState.connecting);

    final url =
        '$_baseUrl/v1/public/events/queue/${widget.clinicId}/$_selectedDoctorId';

    // Use Dio's response stream for SSE
    _dio!
        .get<ResponseBody>(
          url,
          options: Options(responseType: ResponseType.stream),
        )
        .then((response) {
      if (!mounted) return;
      setState(() => _sseState = _SseState.live);
      _sseSub = response.data!.stream
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (line.startsWith('data:')) {
            try {
              final payload =
                  jsonDecode(line.substring(5).trim()) as Map<String, dynamic>;
              // Refresh queue on any event
              _fetchQueue();
            } catch (_) {}
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() => _sseState = _SseState.reconnecting);
            Future.delayed(const Duration(seconds: 5), _connectSse);
          }
        },
        onDone: () {
          if (mounted) {
            setState(() => _sseState = _SseState.reconnecting);
            Future.delayed(const Duration(seconds: 5), _connectSse);
          }
        },
      );
    }).catchError((_) {
      if (mounted) {
        setState(() => _sseState = _SseState.reconnecting);
        Future.delayed(const Duration(seconds: 5), _connectSse);
      }
    });
  }

  void _selectDoctor(String doctorId) {
    _sseSub?.cancel();
    setState(() {
      _selectedDoctorId = doctorId;
      _queueStatus = null;
    });
    _fetchQueue();
    _connectSse();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.neutral50,
      appBar: AppBar(
        title: Text(_clinicName ?? 'Queue Status'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        actions: [
          _SseIndicator(state: _sseState),
          const SizedBox(width: 8),
        ],
      ),
      body: _loadingClinic
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Doctor picker
                if (_doctors.isNotEmpty) ...[
                  Text('Select Doctor', style: AppTypography.heading3),
                  const SizedBox(height: 8),
                  ..._doctors.map((doc) => _DoctorTile(
                        doctor: doc,
                        isSelected: doc.doctorId == _selectedDoctorId,
                        onTap: () => _selectDoctor(doc.doctorId),
                      )),
                  const SizedBox(height: 16),
                ],

                // Queue status
                if (_selectedDoctorId != null) ...[
                  if (_loadingQueue)
                    const Center(child: CircularProgressIndicator())
                  else if (_queueStatus != null)
                    _QueueCard(status: _queueStatus!),
                  const SizedBox(height: 16),
                ],

                // Request records button
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RecordRequestScreen(
                        baseUrl: _baseUrl ?? '',
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Request My Records'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _SseIndicator extends StatelessWidget {
  const _SseIndicator({required this.state});
  final _SseState state;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (state) {
      _SseState.live => (AppColors.success, 'Live'),
      _SseState.connecting => (Colors.orange, 'Connecting'),
      _SseState.reconnecting => (Colors.orange, 'Reconnecting'),
      _SseState.disconnected => (AppColors.neutral400, 'Offline'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: AppTypography.caption.copyWith(color: AppColors.surface)),
      ],
    );
  }
}

class _DoctorTile extends StatelessWidget {
  const _DoctorTile({
    required this.doctor,
    required this.isSelected,
    required this.onTap,
  });

  final _DoctorInfo doctor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: isSelected ? 2 : 1,
      color: isSelected ? AppColors.primary.withValues(alpha: 0.08) : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isSelected
            ? const BorderSide(color: AppColors.primary)
            : BorderSide.none,
      ),
      child: ListTile(
        onTap: onTap,
        title: Text(doctor.name, style: AppTypography.body.copyWith(fontWeight: FontWeight.w600)),
        subtitle: doctor.specialization != null
            ? Text(doctor.specialization!, style: AppTypography.caption)
            : null,
        trailing: doctor.isAccepting
            ? const Chip(
                label: Text('Accepting', style: TextStyle(fontSize: 11)),
                backgroundColor: Color(0xFFE8F5E9),
              )
            : const Chip(
                label: Text('Full', style: TextStyle(fontSize: 11)),
                backgroundColor: Color(0xFFFFEBEE),
              ),
      ),
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.status});
  final _QueueStatus status;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(status.doctorName, style: AppTypography.heading3),
            if (status.specialization != null)
              Text(status.specialization!,
                  style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Stat(
                  label: 'Now Serving',
                  value: status.currentQueueNumber != null
                      ? '#${status.currentQueueNumber}'
                      : '—',
                  color: AppColors.primary,
                ),
                _Stat(
                  label: 'Ahead of You',
                  value: '${status.totalScheduled}',
                  color: AppColors.accent,
                ),
                _Stat(
                  label: 'Est. Wait',
                  value: '~${status.estimatedWaitMinutes}m',
                  color: AppColors.neutral600,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: AppTypography.heading2.copyWith(color: color, fontSize: 28)),
        const SizedBox(height: 4),
        Text(label,
            style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
      ],
    );
  }
}
