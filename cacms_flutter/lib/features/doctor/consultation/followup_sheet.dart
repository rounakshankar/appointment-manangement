import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/widgets.dart';

/// Bottom sheet shown after a consultation is saved with a non-null
/// `next_visit_date`. Displays pre-filled follow-up appointment data and
/// lets the doctor book or skip.
///
/// Requirements: 11.1, 11.2, 11.3
class FollowUpSheet extends StatefulWidget {
  const FollowUpSheet({
    super.key,
    required this.apiClient,
    required this.patientId,
    required this.patientName,
    required this.doctorId,
    required this.scheduledDate,
  });

  final ApiClient apiClient;
  final String patientId;
  final String patientName;
  final String doctorId;
  final DateTime scheduledDate;

  @override
  State<FollowUpSheet> createState() => _FollowUpSheetState();
}

class _FollowUpSheetState extends State<FollowUpSheet> {
  bool _booking = false;
  bool _booked = false;

  Future<void> _bookFollowUp() async {
    setState(() => _booking = true);

    try {
      await widget.apiClient.dio.post(
        '/v1/appointments',
        data: {
          'patient_id': widget.patientId,
          'doctor_id': widget.doctorId,
          'scheduled_date':
              DateFormat('yyyy-MM-dd').format(widget.scheduledDate),
          'visit_type': 'follow-up',
        },
      );

      if (!mounted) return;
      setState(() => _booked = true);

      AppToast.show(
        context,
        message: 'Follow-up booked for ${DateFormat('d MMM yyyy').format(widget.scheduledDate)}',
        type: ToastType.success,
      );

      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (!mounted) return;
      if (e.errorCode == 'FOLLOWUP_CONFLICT') {
        AppToast.show(
          context,
          message: 'A follow-up already exists for this date',
          type: ToastType.warning,
        );
        if (mounted) Navigator.of(context).pop();
      } else {
        AppToast.show(context, message: e.message, type: ToastType.error);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          message: 'Failed to book follow-up',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate =
        DateFormat('EEEE, d MMMM yyyy').format(widget.scheduledDate);

    return Padding(
      // Ensure sheet clears the keyboard
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.event_repeat,
                        color: AppColors.accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Schedule Follow-Up',
                            style: AppTypography.heading2,
                          ),
                          Text(
                            'Pre-filled from consultation',
                            style: AppTypography.caption
                                .copyWith(color: AppColors.neutral600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Pre-filled details card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.neutral50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.neutral200),
                  ),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: Icons.person_outline,
                        label: 'Patient',
                        value: widget.patientName,
                      ),
                      const SizedBox(height: 10),
                      _DetailRow(
                        icon: Icons.calendar_today_outlined,
                        label: 'Date',
                        value: formattedDate,
                      ),
                      const SizedBox(height: 10),
                      _DetailRow(
                        icon: Icons.repeat_outlined,
                        label: 'Visit Type',
                        value: 'Follow-Up',
                        valueWidget: const VisitTypeBadge(
                          type: VisitType.followUp,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Book button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: (_booking || _booked) ? null : _bookFollowUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.surface,
                      disabledBackgroundColor:
                          AppColors.primary.withValues(alpha: 0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _booking
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: AppColors.surface,
                            ),
                          )
                        : _booked
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_outline, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Follow-Up Booked',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              )
                            : const Text(
                                'BOOK FOLLOW-UP',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                  ),
                ),
                const SizedBox(height: 12),

                // Skip link
                Center(
                  child: TextButton(
                    onPressed: _booking
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.neutral600,
                      textStyle: AppTypography.body,
                    ),
                    child: const Text('Skip for now'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail row helper
// ---------------------------------------------------------------------------

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueWidget,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? valueWidget;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.neutral600),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: AppTypography.caption.copyWith(color: AppColors.neutral600),
          ),
        ),
        Expanded(
          child: valueWidget ??
              Text(
                value,
                style: AppTypography.body
                    .copyWith(fontWeight: FontWeight.w600),
              ),
        ),
      ],
    );
  }
}
