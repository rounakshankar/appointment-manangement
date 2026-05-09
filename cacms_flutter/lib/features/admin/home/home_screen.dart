import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/sse_client.dart';
import '../../../core/auth/token_storage.dart';
import '../../../core/models/appointment.dart';
import '../../../core/models/consultation.dart';
import '../../../core/models/patient.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../common/export_text_screen.dart';
import '../payment/payment_modal.dart';

// ---------------------------------------------------------------------------
// Internal doctor model
// ---------------------------------------------------------------------------

class _Doctor {
  const _Doctor({
    required this.doctorId,
    required this.name,
    required this.specialization,
  });
  final String doctorId;
  final String name;
  final String specialization;
}

// ---------------------------------------------------------------------------
// Patient lookup state machine
// ---------------------------------------------------------------------------

enum _LookupState { empty, searching, found, notFound }

// ---------------------------------------------------------------------------
// Admin Home Screen
// ---------------------------------------------------------------------------

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({
    super.key,
    required this.apiClient,
    required this.tokenStorage,
    required this.onLogout,
  });

  final ApiClient apiClient;
  final TokenStorage tokenStorage;
  final VoidCallback onLogout;

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  List<_Doctor> _doctors = [];
  bool _doctorsLoading = true;

  _Doctor? _selectedQueueDoctor;
  List<Appointment> _queue = [];
  int _total = 0;
  int _done = 0;
  int _remaining = 0;
  SseConnectionState _sseState = SseConnectionState.disconnected;
  SseClient? _sseClient;

  @override
  void initState() {
    super.initState();
    _fetchDoctors();
  }

  @override
  void dispose() {
    _sseClient?.dispose();
    super.dispose();
  }

  Future<void> _fetchDoctors() async {
    try {
      final resp = await widget.apiClient.dio.get('/v1/doctors');
      final list = (resp.data as List<dynamic>)
          .map((e) => _Doctor(
                doctorId: (e as Map<String, dynamic>)['doctor_id'] as String,
                name: e['name'] as String,
                specialization: e['specialization'] as String? ?? '',
              ))
          .where((d) => !d.name.startsWith('Dr. Property'))
          .toList();
      if (mounted) setState(() { _doctors = list; _doctorsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _doctorsLoading = false);
    }
  }

  Future<void> _selectQueueDoctor(_Doctor? doctor) async {
    if (doctor == null) {
      setState(() {
        _selectedQueueDoctor = null;
        _queue = [];
        _total = 0;
        _done = 0;
        _remaining = 0;
      });
      _sseClient?.dispose();
      _sseClient = null;
      return;
    }
    setState(() => _selectedQueueDoctor = doctor);
    _sseClient?.dispose();
    _sseClient = null;
    await _fetchQueue(doctor);
    _connectSse(doctor);
  }

  Future<void> _fetchQueue(_Doctor doctor) async {
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final resp = await widget.apiClient.dio.get(
        '/v1/appointments/today',
        queryParameters: {'doctor_id': doctor.doctorId, 'date': today},
      );
      final data = resp.data as Map<String, dynamic>;
      final rawQueue = (data['queue'] as List<dynamic>? ?? [])
          .map((e) => Appointment.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) {
        setState(() {
          _queue = rawQueue;
          _total = data['total'] as int? ?? 0;
          _done = data['completed'] as int? ?? 0;
          _remaining = data['remaining'] as int? ?? 0;
        });
      }
    } catch (_) {}
  }

  void _connectSse(_Doctor doctor) async {
    final token = await widget.tokenStorage.getToken();
    final sseClient = SseClient(
      url: '${widget.apiClient.dio.options.baseUrl}/v1/events/doctor/${doctor.doctorId}',
      headers: token != null ? {'Authorization': 'Bearer $token'} : {},
    );
    _sseClient = sseClient;
    sseClient.connectionState.listen((s) {
      if (mounted) setState(() => _sseState = s);
    });
    sseClient.events.listen((event) {
      if (event.eventType == 'appointment_created' ||
          event.eventType == 'queue_updated' ||
          event.eventType == 'consultation_completed') {
        _fetchQueue(doctor);
      }
    });
    sseClient.connect();
  }

  void _openQueueBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, sc) => _RightPanel(
          apiClient: widget.apiClient,
          doctors: _doctors,
          selectedDoctorId: _selectedQueueDoctor?.doctorId,
          onDoctorChanged: (id) {
            final doc = id == null ? null : _doctors.firstWhere((d) => d.doctorId == id);
            _selectQueueDoctor(doc);
          },
          queue: _queue,
          total: _total,
          done: _done,
          remaining: _remaining,
          sseState: _sseState,
          scrollController: sc,
          onQueueRefresh: () {
            if (_selectedQueueDoctor != null) _fetchQueue(_selectedQueueDoctor!);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: AppColors.neutral50,
      body: isTablet ? _tabletLayout() : _phoneLayout(),
      floatingActionButton: isTablet
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _openQueueBottomSheet(context),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surface,
              label: const Text('View Queue →'),
              icon: const Icon(Icons.queue),
            ),
    );
  }

  Widget _tabletLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 6,
          child: _LeftPanel(
            apiClient: widget.apiClient,
            doctors: _doctors,
            doctorsLoading: _doctorsLoading,
            onAppointmentCreated: () {
              if (_selectedQueueDoctor != null) _fetchQueue(_selectedQueueDoctor!);
            },
          ),
        ),
        const VerticalDivider(width: 1, color: AppColors.neutral200),
        Expanded(
          flex: 4,
          child: _RightPanel(
            apiClient: widget.apiClient,
            doctors: _doctors,
            selectedDoctorId: _selectedQueueDoctor?.doctorId,
            onDoctorChanged: (id) {
              final doc = id == null ? null : _doctors.firstWhere((d) => d.doctorId == id);
              _selectQueueDoctor(doc);
            },
            queue: _queue,
            total: _total,
            done: _done,
            remaining: _remaining,
            sseState: _sseState,
            onQueueRefresh: () {
              if (_selectedQueueDoctor != null) _fetchQueue(_selectedQueueDoctor!);
            },
          ),
        ),
      ],
    );
  }

  Widget _phoneLayout() {
    return _LeftPanel(
      apiClient: widget.apiClient,
      doctors: _doctors,
      doctorsLoading: _doctorsLoading,
      onAppointmentCreated: () {
        if (_selectedQueueDoctor != null) _fetchQueue(_selectedQueueDoctor!);
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Left Panel — patient lookup + appointment creation
// ---------------------------------------------------------------------------

class _LeftPanel extends StatefulWidget {
  const _LeftPanel({
    required this.apiClient,
    required this.doctors,
    required this.doctorsLoading,
    required this.onAppointmentCreated,
  });

  final ApiClient apiClient;
  final List<_Doctor> doctors;
  final bool doctorsLoading;
  final VoidCallback onAppointmentCreated;

  @override
  State<_LeftPanel> createState() => _LeftPanelState();
}

class _LeftPanelState extends State<_LeftPanel> {
  final _phoneController = TextEditingController();
  _LookupState _lookupState = _LookupState.empty;
  Patient? _foundPatient;

  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  String _gender = 'male';
  bool _consentGiven = false;
  bool _registering = false;

  _Doctor? _selectedDoctor;
  DateTime _selectedDate = DateTime.now();
  String _visitType = 'normal';
  bool _creatingAppointment = false;
  String? _capacityError;

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  // Normalise phone: strip leading +91 / 0, keep 10 digits
  String _normalisePhone(String raw) {
    var p = raw.trim().replaceAll(RegExp(r'\s+'), '');
    if (p.startsWith('+91')) p = p.substring(3);
    if (p.startsWith('91') && p.length == 12) p = p.substring(2);
    if (p.startsWith('0')) p = p.substring(1);
    return '+91$p';
  }

  Future<void> _lookupPatient() async {
    final raw = _phoneController.text.trim();
    if (raw.isEmpty) return;
    final phone = _normalisePhone(raw);

    setState(() {
      _lookupState = _LookupState.searching;
      _foundPatient = null;
      _capacityError = null;
    });

    try {
      final resp = await widget.apiClient.dio.get(
        '/v1/patients',
        queryParameters: {'phone': phone},
      );
      final patient = Patient.fromJson(resp.data as Map<String, dynamic>);
      setState(() { _foundPatient = patient; _lookupState = _LookupState.found; });
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      setState(() => _lookupState = (err?.statusCode == 404) ? _LookupState.notFound : _LookupState.empty);
    } catch (_) {
      setState(() => _lookupState = _LookupState.empty);
    }
  }

  Future<void> _registerPatient() async {
    final name = _nameController.text.trim();
    final age = int.tryParse(_ageController.text.trim());
    if (name.isEmpty || age == null || !_consentGiven) {
      AppToast.show(context, message: 'Fill all fields and accept consent', type: ToastType.error);
      return;
    }

    setState(() => _registering = true);
    try {
      final resp = await widget.apiClient.dio.post('/v1/patients', data: {
        'name': name,
        'phone': _normalisePhone(_phoneController.text),
        'age': age,
        'gender': _gender,
      });
      final patient = Patient.fromJson(resp.data as Map<String, dynamic>);
      setState(() { _foundPatient = patient; _lookupState = _LookupState.found; });
      if (mounted) AppToast.show(context, message: 'Patient registered', type: ToastType.success);
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) AppToast.show(context, message: err?.message ?? 'Registration failed', type: ToastType.error);
    } catch (_) {
      if (mounted) AppToast.show(context, message: 'Registration failed', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _createAppointment() async {
    if (_foundPatient == null || _selectedDoctor == null) return;
    setState(() { _creatingAppointment = true; _capacityError = null; });

    try {
      final resp = await widget.apiClient.dio.post('/v1/appointments', data: {
        'patient_id': _foundPatient!.patientId,
        'doctor_id': _selectedDoctor!.doctorId,
        'scheduled_date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'visit_type': _visitType,
      });
      final appt = Appointment.fromJson(resp.data as Map<String, dynamic>);
      if (mounted) {
        AppToast.show(
          context,
          message: 'Queue #${appt.queueNumber} assigned to ${_foundPatient!.name}',
          type: ToastType.success,
        );
        widget.onAppointmentCreated();
        setState(() {
          _phoneController.clear();
          _lookupState = _LookupState.empty;
          _foundPatient = null;
          _selectedDoctor = null;
          _visitType = 'normal';
          _selectedDate = DateTime.now();
        });
      }
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (err?.errorCode == 'DOCTOR_CAPACITY_REACHED') {
        setState(() => _capacityError = '${_selectedDoctor!.name} has reached today\'s limit');
      } else {
        if (mounted) AppToast.show(context, message: err?.message ?? 'Failed to create appointment', type: ToastType.error);
      }
    } catch (_) {
      if (mounted) AppToast.show(context, message: 'Failed to create appointment', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _creatingAppointment = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('PATIENT LOOKUP'),
          const SizedBox(height: 8),
          _phoneField(),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _lookupStateWidget(),
          ),
          if (_foundPatient != null) ...[
            const SizedBox(height: 24),
            _sectionLabel('NEW APPOINTMENT'),
            const SizedBox(height: 12),
            _appointmentForm(),
          ],
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: AppTypography.caption.copyWith(color: AppColors.neutral600, letterSpacing: 0.8),
      );

  Widget _phoneField() {
    return TextField(
      controller: _phoneController,
      keyboardType: TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d+]'))],
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: 'Phone Number',
        hintText: '9876543210',
        prefixText: '+91 ',
        suffixIcon: _lookupState == _LookupState.searching
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : IconButton(icon: const Icon(Icons.search), onPressed: _lookupPatient),
      ),
      onSubmitted: (_) => _lookupPatient(),
    );
  }

  Widget _lookupStateWidget() {
    switch (_lookupState) {
      case _LookupState.empty:
      case _LookupState.searching:
        return const SizedBox.shrink(key: ValueKey('empty'));
      case _LookupState.found:
        return _patientCard(key: const ValueKey('found'));
      case _LookupState.notFound:
        return _registrationForm(key: const ValueKey('notFound'));
    }
  }

  Widget _patientCard({Key? key}) {
    final p = _foundPatient!;
    return Card(
      key: key,
      color: AppColors.primaryLight,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.primary, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name, style: AppTypography.heading3),
                  const SizedBox(height: 4),
                  Text(
                    'Age: ${p.age ?? '—'}  •  ${_capitalize(p.gender ?? '—')}',
                    style: AppTypography.body,
                  ),
                  Text(
                    p.phone,
                    style: AppTypography.caption.copyWith(color: AppColors.neutral600),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              color: AppColors.neutral600,
              tooltip: 'Clear',
              onPressed: () => setState(() {
                _foundPatient = null;
                _lookupState = _LookupState.empty;
                _phoneController.clear();
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _registrationForm({Key? key}) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Card(
        key: key,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_add_outlined, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text('New Patient Registration',
                      style: AppTypography.heading3.copyWith(color: AppColors.neutral900)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ageController,
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
                    value: _consentGiven,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => _consentGiven = v ?? false),
                  ),
                  const Expanded(
                    child: Text('Patient consents to data collection and use', style: AppTypography.body),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _registering ? null : _registerPatient,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.surface,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _registering
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                      : const Text('REGISTER & CONTINUE →'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _appointmentForm() {
    final isEmergency = _visitType == 'emergency';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.doctorsLoading
            ? const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
            : DropdownButtonFormField<String>(
                value: _selectedDoctor?.doctorId,
                decoration: const InputDecoration(labelText: 'Doctor', border: OutlineInputBorder()),
                items: widget.doctors
                    .map((d) => DropdownMenuItem(
                          value: d.doctorId,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(d.name, style: AppTypography.body),
                              if (d.specialization.isNotEmpty)
                                Text(d.specialization,
                                    style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (id) {
                  if (id == null) return;
                  setState(() {
                    _selectedDoctor = widget.doctors.firstWhere((d) => d.doctorId == id);
                    _capacityError = null;
                  });
                },
              ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _pickDate,
          borderRadius: BorderRadius.circular(4),
          child: InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Date',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_today, size: 18),
            ),
            child: Text(DateFormat('d MMM yyyy').format(_selectedDate), style: AppTypography.body),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _visitTypeChip('normal', 'Normal', AppColors.primary),
            const SizedBox(width: 8),
            _visitTypeChip('follow-up', 'Follow-Up', AppColors.accent),
            const SizedBox(width: 8),
            _visitTypeChip('emergency', '⚡ Emergency', AppColors.danger),
          ],
        ),
        if (isEmergency) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.danger),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, color: AppColors.danger, size: 16),
                SizedBox(width: 4),
                Text('Emergency — placed at front of queue',
                    style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
        if (_capacityError != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.danger),
            ),
            child: Text(_capacityError!, style: AppTypography.body.copyWith(color: AppColors.danger)),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: (_creatingAppointment || _selectedDoctor == null) ? null : _createAppointment,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.surface,
              disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: _creatingAppointment
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.surface))
                : const Text('CREATE APPOINTMENT →', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _visitTypeChip(String value, String label, Color color) {
    final selected = _visitType == value;
    return GestureDetector(
      onTap: () => setState(() { _visitType = value; _capacityError = null; }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color, width: selected ? 2 : 1),
        ),
        child: Text(label, style: AppTypography.badge.copyWith(color: selected ? AppColors.surface : color)),
      ),
    );
  }

  String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ---------------------------------------------------------------------------
// Right Panel — live queue with actions
// ---------------------------------------------------------------------------

class _RightPanel extends StatelessWidget {
  const _RightPanel({
    required this.apiClient,
    required this.doctors,
    required this.selectedDoctorId,
    required this.onDoctorChanged,
    required this.queue,
    required this.total,
    required this.done,
    required this.remaining,
    required this.sseState,
    required this.onQueueRefresh,
    this.scrollController,
  });

  final ApiClient apiClient;
  final List<_Doctor> doctors;
  final String? selectedDoctorId;
  final ValueChanged<String?> onDoctorChanged;
  final List<Appointment> queue;
  final int total;
  final int done;
  final int remaining;
  final SseConnectionState sseState;
  final VoidCallback onQueueRefresh;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('LIVE QUEUE',
                  style: AppTypography.caption.copyWith(color: AppColors.neutral600, letterSpacing: 0.8)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: selectedDoctorId,
                decoration: const InputDecoration(
                  labelText: 'Doctor',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: doctors
                    .map((d) => DropdownMenuItem(value: d.doctorId, child: Text(d.name)))
                    .toList(),
                onChanged: onDoctorChanged,
              ),
              if (selectedDoctorId != null) ...[
                const SizedBox(height: 12),
                _statsRow(),
              ],
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.neutral200),
        Expanded(
          child: selectedDoctorId == null
              ? const EmptyState(icon: Icons.people_outline, message: 'Select a doctor to view their queue')
              : queue.isEmpty
                  ? const EmptyState(icon: Icons.event_available, message: 'No appointments yet')
                  : ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: queue.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.neutral200),
                      itemBuilder: (_, i) => _AdminQueueRow(
                        appt: queue[i],
                        apiClient: apiClient,
                        onRefresh: onQueueRefresh,
                      ),
                    ),
        ),
        const Divider(height: 1, color: AppColors.neutral200),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SseIndicator(state: sseState),
        ),
      ],
    );
  }

  Widget _statsRow() {
    return Row(
      children: [
        _StatCard(label: 'Total', value: total),
        const SizedBox(width: 8),
        _StatCard(label: 'Done', value: done, color: AppColors.success),
        const SizedBox(width: 8),
        _StatCard(label: 'Remaining', value: remaining, color: AppColors.accent),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Stat card
// ---------------------------------------------------------------------------

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.neutral200),
        ),
        child: Column(
          children: [
            Text('$value',
                style: AppTypography.heading2.copyWith(color: color ?? AppColors.neutral900)),
            Text(label, style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Admin queue row — with no-show, cancel, and payment actions
// ---------------------------------------------------------------------------

class _AdminQueueRow extends StatefulWidget {
  const _AdminQueueRow({
    required this.appt,
    required this.apiClient,
    required this.onRefresh,
  });

  final Appointment appt;
  final ApiClient apiClient;
  final VoidCallback onRefresh;

  @override
  State<_AdminQueueRow> createState() => _AdminQueueRowState();
}

class _AdminQueueRowState extends State<_AdminQueueRow> {
  bool _expanded = false;
  bool _actionLoading = false;

  bool get _isTerminal =>
      widget.appt.status == 'completed' ||
      widget.appt.status == 'cancelled' ||
      widget.appt.status == 'no-show';

  bool get _isScheduled => widget.appt.status == 'scheduled';
  bool get _isCompleted => widget.appt.status == 'completed';

  Future<void> _updateStatus(String status) async {
    setState(() => _actionLoading = true);
    try {
      await widget.apiClient.dio.patch(
        '/v1/appointments/${widget.appt.appointmentId}/status',
        data: {'status': status},
      );
      widget.onRefresh();
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) AppToast.show(context, message: err?.message ?? 'Failed', type: ToastType.error);
    } catch (_) {
      if (mounted) AppToast.show(context, message: 'Failed to update status', type: ToastType.error);
    } finally {
      if (mounted) setState(() { _actionLoading = false; _expanded = false; });
    }
  }

  Future<void> _openPayment() async {
    setState(() => _actionLoading = true);
    try {
      // Fetch consultation for this appointment
      final resp = await widget.apiClient.dio.get(
        '/v1/consultations/${widget.appt.appointmentId}',
      );
      final consultation = Consultation.fromJson(resp.data as Map<String, dynamic>);
      if (!mounted) return;

      final payment = await PaymentModal.show(
        context,
        apiClient: widget.apiClient,
        consultation: consultation,
        patientName: widget.appt.patientName ?? 'Patient',
      );
      if (payment != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExportTextScreen(
              apiClient: widget.apiClient,
              title: 'Receipt',
              endpoint: '/v1/exports/receipt/${payment.paymentId}',
            ),
          ),
        );
      }
      widget.onRefresh();
    } on DioException catch (e) {
      final err = ApiClient.unwrapError(e);
      if (mounted) {
        final msg = err?.statusCode == 404
            ? 'No consultation found for this appointment'
            : err?.message ?? 'Failed to load consultation';
        AppToast.show(context, message: msg, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) AppToast.show(context, message: 'Failed to load consultation', type: ToastType.error);
    } finally {
      if (mounted) setState(() { _actionLoading = false; _expanded = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final appt = widget.appt;
    final isEmergency = appt.visitType == 'emergency';
    final canExpand = _isScheduled || _isCompleted;

    return InkWell(
      onTap: canExpand ? () => setState(() => _expanded = !_expanded) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        color: isEmergency && _isScheduled
            ? AppColors.danger.withValues(alpha: 0.04)
            : AppColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isEmergency && _isScheduled)
                  const Padding(
                    padding: EdgeInsets.only(right: 2),
                    child: Icon(Icons.bolt, color: AppColors.danger, size: 14),
                  ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '#${appt.queueNumber.toString().padLeft(3, '0')}',
                    style: AppTypography.mono.copyWith(
                      color: _isTerminal ? AppColors.neutral600 : AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    appt.patientName ?? '—',
                    style: AppTypography.body.copyWith(
                      color: _isTerminal ? AppColors.neutral600 : AppColors.neutral900,
                      decoration: _isTerminal ? TextDecoration.lineThrough : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                VisitTypeBadge(type: visitTypeFromString(appt.visitType)),
                const SizedBox(width: 4),
                StatusChip(status: appointmentStatusFromString(appt.status)),
                if (canExpand) ...[
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColors.neutral600,
                  ),
                ],
              ],
            ),
            // Expanded action row
            if (_expanded && !_actionLoading)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 42),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (_isScheduled) ...[
                      _ActionChip(
                        label: 'No Show',
                        icon: Icons.person_off_outlined,
                        color: AppColors.danger,
                        onTap: () => _updateStatus('no-show'),
                      ),
                      _ActionChip(
                        label: 'Cancel',
                        icon: Icons.cancel_outlined,
                        color: AppColors.neutral600,
                        onTap: () => _updateStatus('cancelled'),
                      ),
                    ],
                    if (_isCompleted)
                      _ActionChip(
                        label: 'Record Payment',
                        icon: Icons.payment_outlined,
                        color: AppColors.success,
                        onTap: _openPayment,
                      ),
                  ],
                ),
              ),
            if (_expanded && _actionLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8, left: 42),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Small action chip button
// ---------------------------------------------------------------------------

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
