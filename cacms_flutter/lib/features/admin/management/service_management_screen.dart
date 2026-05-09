import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_toast.dart';

// ---------------------------------------------------------------------------
// Service item model
// ---------------------------------------------------------------------------

class ServiceItem {
  ServiceItem({
    required this.serviceId,
    required this.name,
    required this.category,
    required this.basePrice,
    required this.active,
  });

  final String serviceId;
  String name;
  String category;
  double basePrice;
  bool active;

  factory ServiceItem.fromJson(Map<String, dynamic> j) => ServiceItem(
        serviceId: j['service_id'] as String,
        name: j['name'] as String,
        category: j['category'] as String,
        basePrice: (j['base_price'] as num).toDouble(),
        active: j['active'] as bool? ?? true,
      );
}

// ---------------------------------------------------------------------------
// Service Management Screen
// ---------------------------------------------------------------------------

class ServiceManagementScreen extends StatefulWidget {
  const ServiceManagementScreen({super.key, required this.apiClient});
  final ApiClient apiClient;

  @override
  State<ServiceManagementScreen> createState() => _ServiceManagementScreenState();
}

class _ServiceManagementScreenState extends State<ServiceManagementScreen> {
  List<ServiceItem> _services = [];
  bool _loading = true;
  String _filterCategory = 'all';

  static const _categories = ['all', 'consultation', 'test', 'procedure'];
  static const _categoryLabels = {
    'all': 'All',
    'consultation': 'Consultation',
    'test': 'Tests',
    'procedure': 'Procedures',
  };

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final resp = await widget.apiClient.dio.get('/v1/services/all');
      final list = (resp.data as List<dynamic>)
          .map((e) => ServiceItem.fromJson(e as Map<String, dynamic>))
          .toList();
      if (mounted) setState(() { _services = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ServiceItem> get _filtered => _filterCategory == 'all'
      ? _services
      : _services.where((s) => s.category == _filterCategory).toList();

  Future<void> _openForm({ServiceItem? existing}) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => _ServiceForm(apiClient: widget.apiClient, existing: existing),
    );
    if (result == true) _fetch();
  }

  Future<void> _toggleActive(ServiceItem svc) async {
    try {
      await widget.apiClient.dio.patch(
        '/v1/services/${svc.serviceId}',
        data: {'active': !svc.active},
      );
      if (mounted) AppToast.show(
        context,
        message: svc.active ? 'Service deactivated' : 'Service activated',
        type: ToastType.success,
      );
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
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppColors.neutral50,
      body: Column(
        children: [
          // Category filter chips
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((cat) {
                  final selected = _filterCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(_categoryLabels[cat]!),
                      selected: selected,
                      onSelected: (_) => setState(() => _filterCategory = cat),
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      checkmarkColor: AppColors.primary,
                      labelStyle: AppTypography.caption.copyWith(
                        color: selected ? AppColors.primary : AppColors.neutral600,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.neutral200),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _fetch,
                    child: filtered.isEmpty
                        ? ListView(children: const [
                            SizedBox(height: 80),
                            Center(child: Text('No services', style: AppTypography.body)),
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _ServiceCard(
                              service: filtered[i],
                              onEdit: () => _openForm(existing: filtered[i]),
                              onToggle: () => _toggleActive(filtered[i]),
                            ),
                          ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.surface,
        icon: const Icon(Icons.add),
        label: const Text('Add Service'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Service card
// ---------------------------------------------------------------------------

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onEdit, required this.onToggle});
  final ServiceItem service;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  static const _catColors = {
    'consultation': Color(0xFF1A6B8A),
    'test': Color(0xFF5B21B6),
    'procedure': Color(0xFFF4A261),
  };

  static const _catLabels = {
    'consultation': 'Consultation',
    'test': 'Test',
    'procedure': 'Procedure',
  };

  @override
  Widget build(BuildContext context) {
    final catColor = _catColors[service.category] ?? AppColors.neutral600;
    return Card(
      elevation: 1,
      color: service.active ? AppColors.surface : AppColors.neutral50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: catColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _catLabels[service.category] ?? service.category,
                style: AppTypography.caption.copyWith(
                  color: catColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(service.name, style: AppTypography.body.copyWith(
                          color: service.active ? AppColors.neutral900 : AppColors.neutral600,
                          decoration: service.active ? null : TextDecoration.lineThrough,
                        )),
                      ),
                      if (!service.active)
                        Container(
                          margin: const EdgeInsets.only(left: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.neutral200,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('Inactive',
                              style: AppTypography.caption.copyWith(color: AppColors.neutral600)),
                        ),
                    ],
                  ),
                  Text(
                    '₹${service.basePrice.toStringAsFixed(2)}',
                    style: AppTypography.body.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                service.active ? Icons.toggle_on : Icons.toggle_off,
                size: 28,
                color: service.active ? AppColors.success : AppColors.neutral600,
              ),
              onPressed: onToggle,
              tooltip: service.active ? 'Deactivate' : 'Activate',
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Service form (create / edit)
// ---------------------------------------------------------------------------

class _ServiceForm extends StatefulWidget {
  const _ServiceForm({required this.apiClient, this.existing});
  final ApiClient apiClient;
  final ServiceItem? existing;

  @override
  State<_ServiceForm> createState() => _ServiceFormState();
}

class _ServiceFormState extends State<_ServiceForm> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  String _category = 'consultation';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _nameCtrl.text = widget.existing!.name;
      _priceCtrl.text = widget.existing!.basePrice.toStringAsFixed(2);
      _category = widget.existing!.category;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim());
    if (name.isEmpty) {
      AppToast.show(context, message: 'Name is required', type: ToastType.error);
      return;
    }
    if (price == null || price < 0) {
      AppToast.show(context, message: 'Enter a valid price', type: ToastType.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final body = {'name': name, 'category': _category, 'base_price': price};
      if (widget.existing == null) {
        await widget.apiClient.dio.post('/v1/services', data: body);
        if (mounted) AppToast.show(context, message: 'Service added', type: ToastType.success);
      } else {
        await widget.apiClient.dio.patch('/v1/services/${widget.existing!.serviceId}', data: body);
        if (mounted) AppToast.show(context, message: 'Service updated', type: ToastType.success);
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
          Text(isEdit ? 'Edit Service' : 'Add Service', style: AppTypography.heading2),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Service Name *', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'consultation', child: Text('Consultation')),
              DropdownMenuItem(value: 'test', child: Text('Test')),
              DropdownMenuItem(value: 'procedure', child: Text('Procedure')),
            ],
            onChanged: (v) { if (v != null) setState(() => _category = v); },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
            decoration: const InputDecoration(
              labelText: 'Base Price (₹) *',
              prefixText: '₹ ',
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
                  : Text(isEdit ? 'SAVE CHANGES' : 'ADD SERVICE'),
            ),
          ),
        ],
      ),
    );
  }
}
