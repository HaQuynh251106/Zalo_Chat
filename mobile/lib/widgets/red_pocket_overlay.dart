import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../services/api_client.dart';
import 'money_message_bubble.dart';
import 'user_avatar.dart';

/// Fullscreen reveal animation for a Lì xì (red pocket).
///
/// Stages:
///  1. closed   — envelope is shown enlarged, gold seal pulses, "Mở" CTA at the bottom.
///  2. opening  — user taps Mở. We call POST /wallet/red-pocket/{id}/open,
///                play the seal-burst + envelope-flip animation in parallel,
///                then transition to revealed.
///  3. revealed — amount fades + scales up with a gold particle burst.
///                Auto-pops after a short hold (and can be dismissed by tap).
///
/// The animation is intentionally implemented with only stock Flutter widgets
/// (no Lottie/Rive) so it adds zero deps.
class RedPocketOverlay extends StatefulWidget {
  final Message message;
  // The sender display info shown above the pocket; if not provided we fall
  // back to the message.senderId. Optional because the chat screen may or may
  // not have it cached.
  final String? senderName;
  final String? senderAvatar;

  const RedPocketOverlay({
    super.key,
    required this.message,
    this.senderName,
    this.senderAvatar,
  });

  @override
  State<RedPocketOverlay> createState() => _RedPocketOverlayState();
}

enum _Stage { closed, opening, revealed, error }

class _RedPocketOverlayState extends State<RedPocketOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _idle; // breathing pulse on the seal
  late final AnimationController _open; // 0..1 burst + flip
  late final AnimationController _reveal; // 0..1 amount reveal

  _Stage _stage = _Stage.closed;
  int? _amountCents;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _idle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
    _open =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _reveal =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    // If sender already revealed (shouldn't happen since the bubble guards
    // against this, but be defensive), surface the amount immediately.
    if (widget.message.isMoneyOpened) {
      _amountCents = widget.message.moneyAmountCents;
      _stage = _Stage.revealed;
      _open.value = 1;
      _reveal.value = 1;
    }
  }

  @override
  void dispose() {
    _idle.dispose();
    _open.dispose();
    _reveal.dispose();
    super.dispose();
  }

  Future<void> _onOpen() async {
    if (_stage != _Stage.closed) return;
    setState(() => _stage = _Stage.opening);
    _idle.stop();
    final api = context.read<ApiClient>();

    // Kick off the animation immediately; the network call runs in parallel.
    final animFuture = _open.forward(from: 0);
    Map<String, dynamic>? data;
    Object? networkError;
    try {
      data = await api.post('/wallet/red-pocket/${widget.message.id}/open')
          as Map<String, dynamic>;
    } catch (e) {
      networkError = e;
    }
    await animFuture;

    if (!mounted) return;
    if (networkError != null) {
      setState(() {
        _stage = _Stage.error;
        _errorText = networkError.toString();
      });
      return;
    }

    setState(() {
      _amountCents = (data?['amount_cents'] as num?)?.toInt() ??
          widget.message.moneyAmountCents;
      _stage = _Stage.revealed;
    });
    await _reveal.forward(from: 0);

    // Auto-dismiss after a short hold so the user has time to read.
    await Future<void>.delayed(const Duration(milliseconds: 1700));
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _stage == _Stage.revealed || _stage == _Stage.error
          ? () => Navigator.of(context).maybePop()
          : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Backdrop
          Container(
            color: const Color(0xFF200000).withValues(alpha: 0.85),
          ),
          // Soft radial gold glow behind the envelope.
          Center(
            child: AnimatedBuilder(
              animation:
                  Listenable.merge([_open, _reveal, _idle]),
              builder: (_, __) {
                final glow = math.max(_open.value, _reveal.value);
                return Container(
                  width: size.shortestSide * (0.85 + 0.15 * glow),
                  height: size.shortestSide * (0.85 + 0.15 * glow),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFFFFCC33)
                            .withValues(alpha: 0.28 + 0.25 * glow),
                        const Color(0xFFFF8C42)
                            .withValues(alpha: 0.15 + 0.2 * glow),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.55, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),
          // Center column: sender, pocket, CTA / amount
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Spacer(),
                  _senderHeader(),
                  const SizedBox(height: 18),
                  _animatedPocket(),
                  const SizedBox(height: 28),
                  _bottomArea(),
                  const Spacer(),
                ],
              ),
            ),
          ),
          // Close button (top-left).
          Positioned(
            top: MediaQuery.of(context).padding.top + 6,
            right: 12,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _senderHeader() {
    final name = widget.senderName ?? 'Người gửi lì xì';
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFFFFCC33), Color(0xFFFF8C42)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFCC33).withValues(alpha: 0.5),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: UserAvatar(
            name: name,
            url: widget.senderAvatar,
            size: 56,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          style: const TextStyle(
            color: Color(0xFFFFE6A8),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'gửi bạn một lì xì may mắn',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }

  Widget _animatedPocket() {
    return SizedBox(
      width: 280,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _particles(),
          _pocketBody(),
          _seal(),
        ],
      ),
    );
  }

  /// The pocket card itself, flipping on Y axis as it "opens".
  Widget _pocketBody() {
    return AnimatedBuilder(
      animation: _open,
      builder: (_, __) {
        // Quarter-turn flip during the open animation; settles back at 0.
        final t = Curves.easeInOutCubic.transform(_open.value);
        final flip = math.sin(t * math.pi) * 0.55; // peaks mid-animation
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012) // perspective
            ..rotateY(flip),
          child: Hero(
            tag: 'red-pocket-${widget.message.id}',
            child: RedPocketCard(
              message: widget.message,
              mine: false,
              opened: _stage == _Stage.revealed,
            ),
          ),
        );
      },
    );
  }

  /// Pulsing gold seal in front of the pocket (closed state); explodes during
  /// the open animation.
  Widget _seal() {
    return AnimatedBuilder(
      animation: Listenable.merge([_idle, _open]),
      builder: (_, __) {
        final pulse = 1 + 0.06 * math.sin(_idle.value * math.pi * 2);
        final burst = Curves.easeOutCubic.transform(_open.value);
        final scale = pulse * (1 + 0.8 * burst);
        final opacity = (1 - burst).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.scale(
            scale: scale,
            child: Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  colors: [
                    Color(0xFFFFF8C8),
                    Color(0xFFFFCC33),
                    Color(0xFFC9A227),
                  ],
                  stops: [0.0, 0.6, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFCC33).withValues(alpha: 0.6),
                    blurRadius: 22,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  '福',
                  style: TextStyle(
                    color: Color(0xFF8B0000),
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Gold particles bursting out from the seal during the open animation.
  Widget _particles() {
    return AnimatedBuilder(
      animation: _open,
      builder: (_, __) {
        return CustomPaint(
          painter: _ParticlesPainter(progress: _open.value),
          size: const Size(280, 220),
        );
      },
    );
  }

  Widget _bottomArea() {
    switch (_stage) {
      case _Stage.closed:
        return _openButton();
      case _Stage.opening:
        return const SizedBox(
          height: 56,
          child: Center(
            child: Text(
              'Đang mở...',
              style: TextStyle(color: Color(0xFFFFE6A8), fontSize: 16),
            ),
          ),
        );
      case _Stage.revealed:
        return _amountReveal();
      case _Stage.error:
        return Column(
          children: [
            Text(
              _errorText ?? 'Không mở được lì xì.',
              style: const TextStyle(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Đóng',
                  style: TextStyle(color: Color(0xFFFFE6A8))),
            ),
          ],
        );
    }
  }

  Widget _openButton() {
    return AnimatedBuilder(
      animation: _idle,
      builder: (_, __) {
        final s = 1 + 0.04 * math.sin(_idle.value * math.pi * 2);
        return Transform.scale(
          scale: s,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _onOpen,
              borderRadius: BorderRadius.circular(40),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(40),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFCC33), Color(0xFFFF8C42)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFCC33).withValues(alpha: 0.55),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Text(
                  'Mở lì xì',
                  style: TextStyle(
                    color: Color(0xFF8B0000),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _amountReveal() {
    final cents = _amountCents ?? widget.message.moneyAmountCents ?? 0;
    final vnd = cents ~/ 100;
    final fmt = NumberFormat('#,###', 'vi_VN').format(vnd);
    return AnimatedBuilder(
      animation: _reveal,
      builder: (_, __) {
        final t = Curves.easeOutBack.transform(_reveal.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: _reveal.value,
          child: Transform.scale(
            scale: 0.4 + 0.6 * t,
            child: Column(
              children: [
                ShaderMask(
                  shaderCallback: (rect) => const LinearGradient(
                    colors: [Color(0xFFFFF3B0), Color(0xFFFFCC33), Color(0xFFFF8C42)],
                  ).createShader(rect),
                  child: Text(
                    '+$fmt ₫',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 38,
                      height: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Đã vào ví của bạn',
                  style: TextStyle(color: Color(0xFFFFE6A8), fontSize: 14),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Draws ~16 gold coins / sparkles radiating outward from the centre as the
/// animation progresses. progress goes 0..1.
class _ParticlesPainter extends CustomPainter {
  final double progress;
  _ParticlesPainter({required this.progress});

  static const int _count = 18;
  static const double _maxRadius = 140;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final c = Offset(size.width / 2, size.height / 2);
    final rng = math.Random(7);
    for (int i = 0; i < _count; i++) {
      final baseAngle = (i / _count) * math.pi * 2;
      final jitter = (rng.nextDouble() - 0.5) * 0.4;
      final angle = baseAngle + jitter;
      final t = Curves.easeOutCubic.transform(progress);
      final radius = _maxRadius * t * (0.7 + rng.nextDouble() * 0.6);
      final pos = c + Offset(math.cos(angle), math.sin(angle)) * radius;
      final opacity = (1 - t).clamp(0.0, 1.0);
      final size0 = 4 + rng.nextDouble() * 5;

      // Halo
      final halo = Paint()
        ..color = const Color(0xFFFFCC33).withValues(alpha: 0.35 * opacity)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(pos, size0 * 1.6, halo);

      // Core
      final core = Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFF8C8), Color(0xFFFFCC33), Color(0xFFC9A227)],
        ).createShader(Rect.fromCircle(center: pos, radius: size0))
        ..isAntiAlias = true;
      core.color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(pos, size0, core);
    }
  }

  @override
  bool shouldRepaint(_ParticlesPainter old) => old.progress != progress;
}
