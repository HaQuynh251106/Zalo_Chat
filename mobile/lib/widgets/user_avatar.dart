import 'package:flutter/material.dart';
import '../theme.dart';

/// Circular avatar with optional gradient ring + presence dot.
/// Falls back to initial letter on coloured background if no URL.
class UserAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final bool online;
  final bool showRing;

  const UserAvatar({
    super.key,
    required this.name,
    this.url,
    this.size = 48,
    this.online = false,
    this.showRing = false,
  });

  @override
  Widget build(BuildContext context) {
    final initial = (name.isNotEmpty ? name[0] : '?').toUpperCase();
    final ringWidth = showRing ? 2.5 : 0.0;
    final inner = size - ringWidth * 2;

    final avatar = ClipOval(
      child: (url != null && url!.isNotEmpty)
          ? Image.network(
              url!,
              width: inner,
              height: inner,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _initialBubble(inner, initial),
            )
          : _initialBubble(inner, initial),
    );

    final ringed = showRing
        ? Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(ringWidth),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppPalette.avatarRing,
            ),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              padding: const EdgeInsets.all(2),
              child: avatar,
            ),
          )
        : SizedBox(width: size, height: size, child: avatar);

    if (!online) return ringed;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ringed,
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 0.28,
            height: size * 0.28,
            decoration: BoxDecoration(
              color: AppPalette.mint,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _initialBubble(double s, String initial) {
    // pick a deterministic hue from the name for variety
    final hue = (name.codeUnits.fold<int>(0, (a, b) => a + b) * 47) % 360;
    final base = HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.65).toColor();
    return Container(
      width: s,
      height: s,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [base, AppPalette.violet.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: s * 0.42,
        ),
      ),
    );
  }
}
