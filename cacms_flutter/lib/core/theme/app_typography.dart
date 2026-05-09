import 'package:flutter/material.dart';

/// Typography scale for the CACMS design system.
/// All text uses Inter except [mono] which uses JetBrains Mono.
abstract final class AppTypography {
  static const String _inter = 'Inter';
  static const String _mono = 'JetBrainsMono';

  static const TextStyle heading1 = TextStyle(
    fontFamily: _inter,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.3,
  );

  static const TextStyle heading2 = TextStyle(
    fontFamily: _inter,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle heading3 = TextStyle(
    fontFamily: _inter,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  static const TextStyle body = TextStyle(
    fontFamily: _inter,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: _inter,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.4,
  );

  static const TextStyle badge = TextStyle(
    fontFamily: _inter,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );

  /// Used for queue numbers — JetBrains Mono, 13sp / weight 500.
  static const TextStyle mono = TextStyle(
    fontFamily: _mono,
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.4,
  );
}
