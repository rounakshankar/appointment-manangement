import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Displays a large monospace queue number, using the mono font from
/// [AppTypography] as specified in the design system.
class QueueNumberDisplay extends StatelessWidget {
  const QueueNumberDisplay({
    super.key,
    required this.queueNumber,
    this.label = 'Queue #',
    this.size = QueueNumberSize.large,
  });

  final int queueNumber;
  final String label;
  final QueueNumberSize size;

  @override
  Widget build(BuildContext context) {
    final numberStyle = _numberStyleFor(size);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(color: AppColors.neutral600),
        ),
        const SizedBox(height: 2),
        Text(
          queueNumber.toString().padLeft(3, '0'),
          style: numberStyle.copyWith(color: AppColors.primary),
        ),
      ],
    );
  }

  static TextStyle _numberStyleFor(QueueNumberSize size) {
    switch (size) {
      case QueueNumberSize.small:
        return AppTypography.mono.copyWith(fontSize: 20, fontWeight: FontWeight.w700);
      case QueueNumberSize.medium:
        return AppTypography.mono.copyWith(fontSize: 32, fontWeight: FontWeight.w700);
      case QueueNumberSize.large:
        return AppTypography.mono.copyWith(fontSize: 48, fontWeight: FontWeight.w700);
    }
  }
}

enum QueueNumberSize { small, medium, large }
