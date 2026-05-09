import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Appointment status values.
enum AppointmentStatus {
  scheduled,
  inProgress,
  completed,
  cancelled,
  noShow,
}

/// Renders an appointment status badge with the correct background/text color
/// and icon per the design spec.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  final AppointmentStatus status;

  @override
  Widget build(BuildContext context) {
    final config = _configFor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: config.background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(config.icon, size: 12, color: config.foreground),
          const SizedBox(width: 4),
          Text(
            config.label,
            style: AppTypography.badge.copyWith(color: config.foreground),
          ),
        ],
      ),
    );
  }

  static _ChipConfig _configFor(AppointmentStatus status) {
    switch (status) {
      case AppointmentStatus.scheduled:
        return const _ChipConfig(
          label: 'Scheduled',
          background: Color(0xFFFEF3C7), // amber-100
          foreground: Color(0xFF92400E), // amber-800
          icon: Icons.schedule,
        );
      case AppointmentStatus.inProgress:
        return const _ChipConfig(
          label: 'In Progress',
          background: Color(0xFFDBEAFE), // blue-100
          foreground: Color(0xFF1E40AF), // blue-800
          icon: Icons.play_circle_outline,
        );
      case AppointmentStatus.completed:
        return const _ChipConfig(
          label: 'Completed',
          background: Color(0xFFD1FAE5), // green-100
          foreground: Color(0xFF065F46), // green-800
          icon: Icons.check_circle_outline,
        );
      case AppointmentStatus.cancelled:
        return const _ChipConfig(
          label: 'Cancelled',
          background: Color(0xFFF3F4F6), // grey-100
          foreground: Color(0xFF374151), // grey-700
          icon: Icons.cancel_outlined,
        );
      case AppointmentStatus.noShow:
        return const _ChipConfig(
          label: 'No Show',
          background: Color(0xFFFEE2E2), // red-100
          foreground: Color(0xFF991B1B), // red-800
          icon: Icons.person_off_outlined,
        );
    }
  }
}

class _ChipConfig {
  const _ChipConfig({
    required this.label,
    required this.background,
    required this.foreground,
    required this.icon,
  });

  final String label;
  final Color background;
  final Color foreground;
  final IconData icon;
}

/// Parses a raw status string (from API) into [AppointmentStatus].
AppointmentStatus appointmentStatusFromString(String value) {
  switch (value) {
    case 'scheduled':
      return AppointmentStatus.scheduled;
    case 'in-progress':
      return AppointmentStatus.inProgress;
    case 'completed':
      return AppointmentStatus.completed;
    case 'cancelled':
      return AppointmentStatus.cancelled;
    case 'no-show':
      return AppointmentStatus.noShow;
    default:
      return AppointmentStatus.scheduled;
  }
}
