import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/call.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';

/// One screen handling both incoming-ringing and ongoing call states.
/// MVP: signalling only (UI + status), no real WebRTC media engine.
class CallScreen extends StatefulWidget {
  final CallSession initial;
  final bool isIncoming;
  final String peerName;
  final String peerAvatar;

  const CallScreen({
    super.key,
    required this.initial,
    required this.isIncoming,
    required this.peerName,
    required this.peerAvatar,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  late CallSession _call;
  late final AnimationController _pulse;
  StreamSubscription? _wsSub;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  bool _muted = false;
  bool _speaker = true;
  bool _videoOn = false;

  @override
  void initState() {
    super.initState();
    _call = widget.initial;
    _videoOn = _call.kind == 'video';
    _pulse =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();

    if (_call.status == 'accepted') _startTicker();

    final ws = context.read<WsClient>();
    _wsSub = ws.events.listen(_onWs);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(_call.startedAt));
    });
  }

  void _onWs(Map<String, dynamic> ev) {
    final p = ev['payload'];
    if (p is! Map<String, dynamic>) return;
    if (p['id'] != _call.id && p['conversation_id'] != _call.conversationId)
      return;
    final t = ev['type'];
    if (t == 'call.answered') {
      setState(() => _call = CallSession.fromJson(p));
      _startTicker();
    } else if (t == 'call.rejected' || t == 'call.ended') {
      _ticker?.cancel();
      setState(() => _call = CallSession.fromJson(p));
      _autoClose(
          reason: t == 'call.rejected'
              ? 'Cuộc gọi bị từ chối'
              : 'Cuộc gọi đã kết thúc');
    }
  }

  void _autoClose({required String reason}) {
    final messenger = ScaffoldMessenger.of(context);
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(reason)));
      Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _wsSub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data =
          await api.post('/calls/${_call.id}/accept') as Map<String, dynamic>;
      setState(() => _call = CallSession.fromJson(data));
      _startTicker();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _reject() async {
    final api = context.read<ApiClient>();
    final nav = Navigator.of(context);
    try {
      await api.post('/calls/${_call.id}/reject');
    } catch (_) {}
    if (mounted) nav.pop();
  }

  Future<void> _end() async {
    final api = context.read<ApiClient>();
    final nav = Navigator.of(context);
    try {
      await api.post('/calls/${_call.id}/end');
    } catch (_) {}
    if (mounted) nav.pop();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  String _formatElapsed(Duration d) {
    final m = _two(d.inMinutes.remainder(60));
    final s = _two(d.inSeconds.remainder(60));
    return d.inHours > 0 ? '${_two(d.inHours)}:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ringing = _call.status == 'ringing';
    final ongoing = _call.status == 'accepted';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E1B2E), Color(0xFF3B2D6E), Color(0xFF5B4ABE)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white, size: 30),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _call.kind == 'video' ? Icons.videocam : Icons.call,
                            color: Colors.white,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _call.kind == 'video' ? 'Video' : 'Thoại',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AnimatedBuilder(
                animation: _pulse,
                builder: (_, child) {
                  final t = (_pulse.value * 2) % 1.0;
                  return SizedBox(
                    width: 220,
                    height: 220,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (ringing)
                          Container(
                            width: 180 + (60 * t),
                            height: 180 + (60 * t),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white
                                    .withValues(alpha: 0.3 * (1 - t)),
                                width: 2,
                              ),
                            ),
                          ),
                        child!,
                      ],
                    ),
                  );
                },
                child: UserAvatar(
                  name: widget.peerName,
                  url: widget.peerAvatar,
                  size: 140,
                ),
              ),
              const SizedBox(height: 26),
              Text(
                widget.peerName,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                ringing
                    ? (widget.isIncoming
                        ? 'Đang gọi đến bạn...'
                        : 'Đang đổ chuông...')
                    : ongoing
                        ? _formatElapsed(_elapsed)
                        : 'Đã kết thúc',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
              ),
              const Spacer(),
              if (ongoing)
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _toggleBtn(
                        icon: _muted ? Icons.mic_off : Icons.mic,
                        label: _muted ? 'Bật mic' : 'Tắt mic',
                        active: _muted,
                        onTap: () => setState(() => _muted = !_muted),
                      ),
                      _toggleBtn(
                        icon: _speaker ? Icons.volume_up : Icons.volume_down,
                        label: 'Loa',
                        active: _speaker,
                        onTap: () => setState(() => _speaker = !_speaker),
                      ),
                      if (_call.kind == 'video')
                        _toggleBtn(
                          icon: _videoOn ? Icons.videocam : Icons.videocam_off,
                          label: 'Camera',
                          active: _videoOn,
                          onTap: () => setState(() => _videoOn = !_videoOn),
                        ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 36),
                child: ringing && widget.isIncoming
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _bigBtn(
                              icon: Icons.call_end,
                              color: Colors.red,
                              onTap: _reject,
                              label: 'Từ chối'),
                          _bigBtn(
                              icon: Icons.call,
                              color: const Color(0xFF34D399),
                              onTap: _accept,
                              label: 'Chấp nhận'),
                        ],
                      )
                    : Align(
                        alignment: Alignment.center,
                        child: _bigBtn(
                          icon: Icons.call_end,
                          color: Colors.red,
                          onTap: _end,
                          label: 'Kết thúc',
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleBtn(
      {required IconData icon,
      required String label,
      required bool active,
      required VoidCallback onTap}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.15),
              ),
              child:
                  Icon(icon, color: active ? AppPalette.indigo : Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }

  Widget _bigBtn(
      {required IconData icon,
      required Color color,
      required VoidCallback onTap,
      required String label}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          elevation: 8,
          shadowColor: color.withValues(alpha: 0.5),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(icon, color: Colors.white, size: 32),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
