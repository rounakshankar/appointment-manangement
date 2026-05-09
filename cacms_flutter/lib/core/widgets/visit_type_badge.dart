import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Visit type values.
enum VisitType {
  normal,
  followUp,
  emergency,
}

/// Badge showing the visit type with appropriate colors.
/// Emergency is rendered in red/accent per the design spec.
class VisitTypeBadge extends StatelessWidget {
  const VisitTypeBadge({super.key, required this.type});

  final VisitType type;

  @override
  Widget build(BuildContext context) {
    final config = _configFor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: config.background,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: config.border, width: 1),
      ),
      child: Text(
        config.label,
        style: AppTypography.badge.copyWith(color: config.foreground),
      ),
    );
  }

  static _BadgeConfig _configFor(VisitType type) {
    switch (type) {
      case VisitType.normal:
        return const _BadgeConfig(
          label: 'Normal',
          background: AppColors.primaryLight,
          foreground: AppColors.primary,
          border: AppColors.primary,
        );
      case VisitType.followUp:
        return _BadgeConfig(
          label: 'Follow-Up',
          background: AppColors.accent.withValues(alpha: 0.12),
          foreground: AppColors.accent,
          border: AppColors.accent,
        );
      case VisitType.emergency:
        return _BadgeConfig(
          label: 'Emergency',
          background: AppColors.danger.withValues(alpha: 0.12),
          foreground: AppColors.danger,
          border: AppColors.danger,
        );
    }
  }
}

class _BadgeConfig {
  const _BadgeConfig({
    required this.label,
    required this.background,
    required this.foreground,
    required this.border,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color border;
}

/// Parses a raw visit type string (from API) into [VisitType].
VisitType visitTypeFromString(String value) {
  switch (value) {
    case 'normal':
      return VisitType.normal;
    case 'follow-up':
      return VisitType.followUp;
    case 'emergency':
      return VisitType.emergency;
    default:
      return VisitType.normal;
  }
}
