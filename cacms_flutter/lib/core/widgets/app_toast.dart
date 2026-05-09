import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Toast severity levels.
enum ToastType { success, warning, error }

/// Shows a themed toast notification.
///
/// Auto-dismiss durations per design spec:
/// - success: 3 s
/// - warning: 2 s
/// - error: 5 s (with manual dismiss button)
class AppToast {
  const AppToast._();

  static void show(
    BuildContext context, {
    required String message,
    required ToastType type,
  }) {
    final config = _configFor(type);
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: config.duration,
        backgroundColor: config.background,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: Row(
          children: [
            Icon(config.icon, color: config.foreground, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: AppTypography.body.copyWith(color: config.foreground),
              ),
            ),
          ],
        ),
        action: type == ToastType.error
            ? SnackBarAction(
                label: 'Dismiss',
                textColor: config.foreground,
                onPressed: () => messenger.hideCurrentSnackBar(),
              )
            : null,
      ),
    );
  }

  static _ToastConfig _configFor(ToastType type) {
    switch (type) {
      case ToastType.success:
        return _ToastConfig(
          background: AppColors.success,
          foreground: AppColors.surface,
          icon: Icons.check_circle_outline,
          duration: const Duration(seconds: 3),
        );
      case ToastType.warning:
        return _ToastConfig(
          background: AppColors.warning,
          foreground: AppColors.neutral900,
          icon: Icons.warning_amber_outlined,
          duration: const Duration(seconds: 2),
        );
      case ToastType.error:
        return _ToastConfig(
          background: AppColors.danger,
          foreground: AppColors.surface,
          icon: Icons.error_outline,
          duration: const Duration(seconds: 5),
        );
    }
  }
}

class _ToastConfig {
  const _ToastConfig({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.duration,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
  final Duration duration;
}
