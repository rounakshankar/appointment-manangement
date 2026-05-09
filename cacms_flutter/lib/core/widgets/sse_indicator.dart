import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// SSE connection states.
enum SseConnectionState {
  live,
  reconnecting,
  disconnected,
}

/// Dot indicator showing the current SSE connection state.
/// - live → green dot
/// - reconnecting → amber dot
/// - disconnected → grey dot
class SseIndicator extends StatelessWidget {
  const SseIndicator({super.key, required this.state});

  final SseConnectionState state;

  @override
  Widget build(BuildContext context) {
    final config = _configFor(state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: config.color, pulse: state == SseConnectionState.live),
        const SizedBox(width: 6),
        Text(
          config.label,
          style: AppTypography.caption.copyWith(color: config.color),
        ),
      ],
    );
  }

  static _IndicatorConfig _configFor(SseConnectionState state) {
    switch (state) {
      case SseConnectionState.live:
        return const _IndicatorConfig(label: 'Live', color: AppColors.success);
      case SseConnectionState.reconnecting:
        return const _IndicatorConfig(label: 'Reconnecting', color: AppColors.warning);
      case SseConnectionState.disconnected:
        return const _IndicatorConfig(label: 'Disconnected', color: AppColors.neutral600);
    }
  }
}

class _IndicatorConfig {
  const _IndicatorConfig({required this.label, required this.color});
  final String label;
  final Color color;
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _opacity = Tween<double>(begin: 1.0, end: 0.3).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.pulse) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_Dot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
