import 'package:flutter/material.dart';
import '../theme.dart';

class TypingDots extends StatefulWidget {
  final Color color;
  final double size;
  const TypingDots({super.key, this.color = AppPalette.indigo, this.size = 7});

  @override
  State<TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size * 5,
      height: widget.size * 1.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final t = (_c.value + i * 0.18) % 1.0;
              final scale = 0.5 + (1 - (t * 2 - 1).abs()) * 0.6;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: widget.size * 0.2),
                child: Container(
                  width: widget.size,
                  height: widget.size * scale,
                  decoration: BoxDecoration(
                    color: widget.color,
                    borderRadius: BorderRadius.circular(widget.size),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
