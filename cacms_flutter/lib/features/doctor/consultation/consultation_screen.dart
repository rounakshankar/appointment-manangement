import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/appointment.dart';
import '../../../core/models/service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';
import '../../common/export_text_screen.dart';
import 'followup_sheet.dart';

// ---------------------------------------------------------------------------
// Selected service line item (local state)
// ---------------------------------------------------------------------------

class _SelectedService {
  _SelectedService({
    required this.service,
    this.quantity = 1,
  });

  final Service service;
  int quantity;

  double get total => service.basePrice * quantity;
}

// ---------------------------------------------------------------------------
// Consultation Screen
// ---------------------------------------------------------------------------

class DoctorConsultationScreen extends StatefulWidget {
  const DoctorConsultationScreen({
    super.key,
    required this.apiClient,
    required this.appointment,
    required this.onConsultationComplete,
  });

  final ApiClient apiClient;
  final Appointment appointment;

  /// Called after a consultation is successfully saved.
  final VoidCallback onConsultationComplete;

  @override
  State<DoctorConsultationScreen> createState() =>
      _DoctorConsultationScreenState();
}

class _DoctorConsultationScreenState extends State<DoctorConsultationScreen> {
  final _symptomsController = TextEditingController();
  final _diagnosisController = TextEditingController();
  final _notesController = TextEditingController();

  final List<_SelectedService> _selectedServices = [];
  DateTime? _nextVisitDate;
  bool _submitting = false;

  @override
  void dispose() {
    _symptomsController.dispose();
    _diagnosisController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _runningTotal =>
      _selectedServices.fold(0, (sum, s) => sum + s.total);

  // ---------------------------------------------------------------------------
  // Submit consultation
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    final symptoms = _symptomsController.text.trim();
    final diagnosis = _diagnosisController.text.trim();

    if (symptoms.isEmpty || diagnosis.isEmpty) {
      AppToast.show(
        context,
        message: 'Symptoms and diagnosis are required',
        type: ToastType.error,
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final resp = await widget.apiClient.dio.post(
        '/v1/consultations',
        data: {
          'appointment_id': widget.appointment.appointmentId,
          'symptoms': symptoms,
          'diagnosis': diagnosis,
          if (_notesController.text.trim().isNotEmpty)
            'notes': _notesController.text.trim(),
          if (_nextVisitDate != null)
            'next_visit_date':
                DateFormat('yyyy-MM-dd').format(_nextVisitDate!),
          'services': _selectedServices
              .map((s) => {
                    'service_id': s.service.serviceId,
                    'quantity': s.quantity,
                    'price_applied': s.service.basePrice,
                  })
              .toList(),
        },
      );

      if (!mounted) return;

      final followUpPrompt =
          resp.data['follow_up_prompt'] as Map<String, dynamic>?;

      if (followUpPrompt != null && _nextVisitDate != null) {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => FollowUpSheet(
            apiClient: widget.apiClient,
            patientId: followUpPrompt['patient_id'] as String,
            patientName: widget.appointment.patientName ?? 'Patient',
            doctorId: followUpPrompt['doctor_id'] as String,
            scheduledDate: _nextVisitDate!,
          ),
        );
      }

      final consultationId = resp.data['consultation_id'] as String?;
      if (consultationId != null && mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ExportTextScreen(
              apiClient: widget.apiClient,
              title: 'Consultation Summary',
              endpoint: '/v1/exports/prescription/$consultationId',
            ),
          ),
        );
      }

      widget.onConsultationComplete();
    } on ApiError catch (e) {
      if (mounted) {
        AppToast.show(context, message: e.message, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Failed to save consultation',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Add service bottom sheet
  // ---------------------------------------------------------------------------

  Future<void> _openAddServiceSheet() async {
    List<Service> services = [];
    try {
      final resp = await widget.apiClient.dio.get('/v1/services');
      services = (resp.data as List<dynamic>)
          .map((e) => Service.fromJson(e as Map<String, dynamic>))
          .toList();
    } on ApiError catch (e) {
      if (mounted) {
        AppToast.show(context, message: e.message, type: ToastType.error);
      }
      return;
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Failed to load services',
          type: ToastType.error,
        );
      }
      return;
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _AddServiceSheet(
        services: services,
        alreadySelected:
            _selectedServices.map((s) => s.service.serviceId).toSet(),
        onAdd: (service) {
          setState(() {
            final existing = _selectedServices
                .where((s) => s.service.serviceId == service.serviceId)
                .firstOrNull;
            if (existing != null) {
              existing.quantity++;
            } else {
              _selectedServices.add(_SelectedService(service: service));
            }
          });
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Date picker
  // ---------------------------------------------------------------------------

  Future<void> _pickNextVisitDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _nextVisitDate = picked);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final appt = widget.appointment;

    return Scaffold(
      backgroundColor: AppColors.neutral50,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        leading: const BackButton(),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appt.patientName ?? 'Patient',
                    style: AppTypography.heading3
                        .copyWith(color: AppColors.surface),
                  ),
                  Text(
                    'Queue #${appt.queueNumber.toString().padLeft(3, '0')}',
                    style: AppTypography.caption
                        .copyWith(color: AppColors.primaryLight),
                  ),
                ],
              ),
            ),
            VisitTypeBadge(type: visitTypeFromString(appt.visitType)),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel('SYMPTOMS *'),
            const SizedBox(height: 8),
            TextField(
              controller: _symptomsController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Describe patient symptoms...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            _sectionLabel('DIAGNOSIS *'),
            const SizedBox(height: 8),
            TextField(
              controller: _diagnosisController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                hintText: 'Enter diagnosis...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            _sectionLabel('NOTES'),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Optional notes...',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 24),
            _servicesSection(),
            const SizedBox(height: 24),
            _sectionLabel('NEXT VISIT DATE'),
            const SizedBox(height: 8),
            InkWell(
              onTap: _pickNextVisitDate,
              borderRadius: BorderRadius.circular(4),
              child: InputDecorator(
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.calendar_today, size: 18),
                ),
                child: Text(
                  _nextVisitDate != null
                      ? DateFormat('d MMM yyyy').format(_nextVisitDate!)
                      : 'Select date (optional)',
                  style: AppTypography.body.copyWith(
                    color: _nextVisitDate != null
                        ? AppColors.neutral900
                        : AppColors.neutral600,
                  ),
                ),
              ),
            ),
            if (_nextVisitDate != null) ...[
              const SizedBox(height: 4),
              TextButton.icon(
                onPressed: () => setState(() => _nextVisitDate = null),
                icon: const Icon(Icons.clear, size: 14),
                label: const Text('Clear date'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.neutral600,
                  padding: EdgeInsets.zero,
                  textStyle: AppTypography.caption,
                ),
              ),
            ],
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.surface,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.surface,
                        ),
                      )
                    : const Text(
                        'COMPLETE CONSULTATION',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Services section
  // ---------------------------------------------------------------------------

  Widget _servicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel('SERVICES'),
            TextButton.icon(
              onPressed: _openAddServiceSheet,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Service'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                textStyle: AppTypography.body
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (_selectedServices.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No services added yet',
              style: AppTypography.body.copyWith(color: AppColors.neutral600),
            ),
          )
        else ...[
          const SizedBox(height: 8),
          ...(_selectedServices.map((s) => _ServiceLineItem(
                item: s,
                onRemove: () => setState(() => _selectedServices.remove(s)),
                onQuantityChanged: (q) => setState(() => s.quantity = q),
              ))),
          const Divider(color: AppColors.neutral200),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: AppTypography.body
                    .copyWith(fontWeight: FontWeight.w600),
              ),
              Text(
                '₹${_runningTotal.toStringAsFixed(2)}',
                style: AppTypography.heading3.copyWith(color: AppColors.primary),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: AppTypography.caption.copyWith(
          color: AppColors.neutral600,
          letterSpacing: 0.8,
        ),
      );
}

// ---------------------------------------------------------------------------
// Service line item widget
// ---------------------------------------------------------------------------

class _ServiceLineItem extends StatelessWidget {
  const _ServiceLineItem({
    required this.item,
    required this.onRemove,
    required this.onQuantityChanged,
  });

  final _SelectedService item;
  final VoidCallback onRemove;
  final ValueChanged<int> onQuantityChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.service.name, style: AppTypography.body),
                Text(
                  '₹${item.service.basePrice.toStringAsFixed(2)} each',
                  style: AppTypography.caption
                      .copyWith(color: AppColors.neutral600),
                ),
              ],
            ),
          ),
          // Quantity stepper
          Row(
            children: [
              _StepperButton(
                icon: Icons.remove,
                onPressed: item.quantity > 1
                    ? () => onQuantityChanged(item.quantity - 1)
                    : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  item.quantity.toString(),
                  style: AppTypography.body
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _StepperButton(
                icon: Icons.add,
                onPressed: () => onQuantityChanged(item.quantity + 1),
              ),
            ],
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: Text(
              '₹${item.total.toStringAsFixed(2)}',
              style: AppTypography.body.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onRemove,
            color: AppColors.neutral600,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          side: BorderSide(
            color: onPressed != null
                ? AppColors.primary
                : AppColors.neutral200,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        child: Icon(
          icon,
          size: 14,
          color: onPressed != null ? AppColors.primary : AppColors.neutral200,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add Service bottom sheet
// ---------------------------------------------------------------------------

class _AddServiceSheet extends StatefulWidget {
  const _AddServiceSheet({
    required this.services,
    required this.alreadySelected,
    required this.onAdd,
  });

  final List<Service> services;
  final Set<String> alreadySelected;
  final ValueChanged<Service> onAdd;

  @override
  State<_AddServiceSheet> createState() => _AddServiceSheetState();
}

class _AddServiceSheetState extends State<_AddServiceSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Service> get _filtered {
    if (_query.isEmpty) return widget.services;
    final q = _query.toLowerCase();
    return widget.services
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.category.toLowerCase().contains(q))
        .toList();
  }

  Map<String, List<Service>> get _grouped {
    final map = <String, List<Service>>{};
    for (final s in _filtered) {
      map.putIfAbsent(s.category, () => []).add(s);
    }
    return map;
  }

  String _categoryLabel(String cat) {
    switch (cat) {
      case 'consultation':
        return 'Consultation';
      case 'test':
        return 'Tests';
      case 'procedure':
        return 'Procedures';
      default:
        return cat;
    }
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;
    final categories = ['consultation', 'test', 'procedure']
        .where((c) => grouped.containsKey(c))
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) => Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.neutral200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add Service', style: AppTypography.heading2),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search services...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.neutral200),
          Expanded(
            child: categories.isEmpty
                ? const EmptyState(
                    icon: Icons.search_off,
                    message: 'No services found',
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: categories.fold<int>(
                      0,
                      (sum, c) => sum + 1 + (grouped[c]?.length ?? 0),
                    ),
                    itemBuilder: (_, i) {
                      // Build flat list with category headers
                      int cursor = 0;
                      for (final cat in categories) {
                        if (i == cursor) {
                          return _CategoryHeader(
                              label: _categoryLabel(cat));
                        }
                        cursor++;
                        final items = grouped[cat]!;
                        if (i < cursor + items.length) {
                          final service = items[i - cursor];
                          return _ServiceRow(
                            service: service,
                            onAdd: () {
                              widget.onAdd(service);
                              AppToast.show(
                                context,
                                message: '${service.name} added',
                                type: ToastType.success,
                              );
                            },
                          );
                        }
                        cursor += items.length;
                      }
                      return const SizedBox.shrink();
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.neutral50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        label.toUpperCase(),
        style: AppTypography.caption.copyWith(
          color: AppColors.neutral600,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.service, required this.onAdd});

  final Service service;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(service.name, style: AppTypography.body),
      subtitle: Text(
        '₹${service.basePrice.toStringAsFixed(2)}',
        style: AppTypography.caption.copyWith(color: AppColors.neutral600),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline),
        color: AppColors.primary,
        onPressed: onAdd,
        tooltip: 'Add',
      ),
    );
  }
}
