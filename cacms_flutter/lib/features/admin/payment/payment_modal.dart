import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/models/consultation.dart';
import '../../../core/models/payment.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_toast.dart';

/// Payment modal dialog matching screen A3 from the UI/UX design.
class PaymentModal extends StatefulWidget {
  const PaymentModal({
    super.key,
    required this.apiClient,
    required this.consultation,
    required this.patientName,
  });

  final ApiClient apiClient;
  final Consultation consultation;
  final String patientName;

  /// Shows the payment modal and returns the recorded [Payment] on success,
  /// or `null` if the user cancelled.
  static Future<Payment?> show(
    BuildContext context, {
    required ApiClient apiClient,
    required Consultation consultation,
    required String patientName,
  }) {
    return showDialog<Payment>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PaymentModal(
        apiClient: apiClient,
        consultation: consultation,
        patientName: patientName,
      ),
    );
  }

  @override
  State<PaymentModal> createState() => _PaymentModalState();
}

class _PaymentModalState extends State<PaymentModal> {
  static final _currencyFmt = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  // Payment mode options
  static const _modes = ['Cash', 'UPI', 'Card'];

  int _selectedModeIndex = 0;
  String _selectedStatus = 'paid';
  bool _loading = false;

  late final TextEditingController _amountController;
  final _formKey = GlobalKey<FormState>();

  double get _total => widget.consultation.services.fold(
        0,
        (sum, s) => sum + (s.total ?? s.priceApplied * s.quantity),
      );

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _total.toStringAsFixed(0),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String get _shortId {
    final id = widget.consultation.consultationId;
    return id.length > 6 ? 'C-${id.substring(0, 6).toUpperCase()}' : 'C-$id';
  }

  Future<void> _recordPayment() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    try {
      final amount = double.tryParse(_amountController.text.trim()) ?? _total;
      final response = await widget.apiClient.dio.post(
        '/v1/payments',
        data: {
          'consultation_id': widget.consultation.consultationId,
          'total_amount': amount,
          'payment_mode': _modes[_selectedModeIndex].toLowerCase(),
          'status': _selectedStatus,
        },
      );

      final payment = Payment.fromJson(response.data as Map<String, dynamic>);

      if (mounted) {
        AppToast.show(
          context,
          message: 'Payment recorded',
          type: ToastType.success,
        );
        Navigator.of(context).pop(payment);
      }
    } on ApiError catch (e) {
      if (mounted) {
        AppToast.show(context, message: e.message, type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildServicesCard(),
                  const SizedBox(height: 20),
                  _buildPaymentMode(),
                  const SizedBox(height: 16),
                  _buildAmountField(),
                  const SizedBox(height: 16),
                  _buildStatusDropdown(),
                  const SizedBox(height: 24),
                  _buildActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment — ${widget.patientName}',
          style: AppTypography.heading2.copyWith(color: AppColors.neutral900),
        ),
        const SizedBox(height: 4),
        Text(
          'Consultation #$_shortId',
          style: AppTypography.caption.copyWith(color: AppColors.neutral600),
        ),
      ],
    );
  }

  Widget _buildServicesCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Services Rendered:',
              style: AppTypography.body.copyWith(
                color: AppColors.neutral600,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ...widget.consultation.services.map(_buildServiceRow),
            const Divider(height: 24, color: AppColors.neutral200),
            _buildTotalRow(),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceRow(ConsultationService s) {
    final lineTotal = s.total ?? s.priceApplied * s.quantity;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.serviceName ?? 'Service',
              style: AppTypography.body.copyWith(color: AppColors.neutral900),
            ),
          ),
          Text(
            _currencyFmt.format(lineTotal),
            style: AppTypography.body.copyWith(color: AppColors.neutral900),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Total',
            style: AppTypography.heading3.copyWith(color: AppColors.neutral900),
          ),
        ),
        Text(
          _currencyFmt.format(_total),
          style: AppTypography.heading3.copyWith(color: AppColors.neutral900),
        ),
      ],
    );
  }

  Widget _buildPaymentMode() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Mode:',
          style: AppTypography.body.copyWith(color: AppColors.neutral600),
        ),
        const SizedBox(height: 8),
        ToggleButtons(
          isSelected: List.generate(
            _modes.length,
            (i) => i == _selectedModeIndex,
          ),
          onPressed: _loading
              ? null
              : (i) => setState(() => _selectedModeIndex = i),
          borderRadius: BorderRadius.circular(8),
          selectedColor: AppColors.surface,
          fillColor: AppColors.primary,
          color: AppColors.neutral600,
          borderColor: AppColors.neutral200,
          selectedBorderColor: AppColors.primary,
          constraints: const BoxConstraints(minWidth: 80, minHeight: 40),
          children: _modes
              .map(
                (m) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(m, style: AppTypography.body),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _buildAmountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Amount:',
          style: AppTypography.body.copyWith(color: AppColors.neutral600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _amountController,
          enabled: !_loading,
          keyboardType: TextInputType.number,
          style: AppTypography.body.copyWith(color: AppColors.neutral900),
          decoration: InputDecoration(
            prefixText: '₹ ',
            prefixStyle:
                AppTypography.body.copyWith(color: AppColors.neutral600),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.neutral200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.neutral200),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Enter an amount';
            if (double.tryParse(v.trim()) == null) return 'Enter a valid number';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildStatusDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Status:',
          style: AppTypography.body.copyWith(color: AppColors.neutral600),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedStatus,
          onChanged: _loading
              ? null
              : (v) => setState(() => _selectedStatus = v ?? 'paid'),
          style: AppTypography.body.copyWith(color: AppColors.neutral900),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.neutral200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.neutral200),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: const [
            DropdownMenuItem(value: 'paid', child: Text('Paid')),
            DropdownMenuItem(value: 'partial', child: Text('Partial')),
            DropdownMenuItem(value: 'pending', child: Text('Pending')),
          ],
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _loading ? null : _recordPayment,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.surface,
                    ),
                  )
                : Text(
                    'RECORD PAYMENT',
                    style: AppTypography.body.copyWith(
                      color: AppColors.surface,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: Text(
              'Cancel',
              style: AppTypography.body.copyWith(color: AppColors.neutral600),
            ),
          ),
        ),
      ],
    );
  }
}
