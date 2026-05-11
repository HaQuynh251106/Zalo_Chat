import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Subtle dotted-pattern chat background — Telegram-inspired but distinct
/// (uses our indigo/violet wash instead of warm khaki). Reusable across chats.
class ChatBackground extends StatelessWidget {
  final Widget child;
  const ChatBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppPalette.bgLight,
                AppPalette.indigo.withValues(alpha: 0.05),
                AppPalette.violet.withValues(alpha: 0.04),
              ],
            ),
          ),
        ),
        IgnorePointer(
          child: CustomPaint(
            painter: _DotPainter(),
            size: Size.infinite,
          ),
        ),
        child,
      ],
    );
  }
}

class _DotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppPalette.indigo.withValues(alpha: 0.06);
    const step = 28.0;
    final rng = math.Random(7);
    for (double y = 0; y < size.height; y += step) {
      for (double x = 0; x < size.width; x += step) {
        final dx = (rng.nextDouble() - 0.5) * 8;
        final dy = (rng.nextDouble() - 0.5) * 8;
        canvas.drawCircle(Offset(x + dx, y + dy), 1.6, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
