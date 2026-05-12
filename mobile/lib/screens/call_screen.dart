import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../models/call.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/rtc_client.dart';
import '../services/ws_client.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';

/// Full 1-1 voice/video call screen with real WebRTC media.
/// Uses the existing signaling layer (/calls/{id}/signal + ws call.signal).
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
  bool _hasRemoteVideo = false;

  RtcClient? _rtc;
  String? _rtcError;
  String? _myId;

  @override
  void initState() {
    super.initState();
    _call = widget.initial;
    _videoOn = _call.kind == 'video';
    _pulse =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat();

    _myId = context.read<AuthProvider>().user?.id;
    final ws = context.read<WsClient>();
    _wsSub = ws.events.listen(_onWs);

    if (_call.status == 'accepted') {
      _startTicker();
      _initRtc();
    } else if (!widget.isIncoming) {
      // Caller: prep media early so the offer goes out the moment callee accepts.
      _initRtc();
    }
  }

  Future<void> _initRtc() async {
    if (_rtc != null) return;
    final api = context.read<ApiClient>();
    final rtc = RtcClient(
      api: api,
      callId: _call.id,
      isCaller: !widget.isIncoming,
    );
    try {
      await rtc.init(withVideo: _call.kind == 'video');
      rtc.onRemoteStream.listen((_) {
        if (!mounted) return;
        setState(() => _hasRemoteVideo = true);
      });
      if (!mounted) {
        await rtc.dispose();
        return;
      }
      setState(() {
        _rtc = rtc;
        _rtcError = null;
      });
    } catch (e) {
      await rtc.dispose();
      if (mounted) {
        setState(() => _rtcError = 'Không truy cập được camera/mic: $e');
      }
    }
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
    final t = ev['type'];

    // Inbound signaling for THIS call only.
    if (t == 'call.signal') {
      if (p['call_id'] != _call.id) return;
      if (p['from'] == _myId) return; // skip self-echo
      _rtc?.handleSignal(p);
      return;
    }

    // Lifecycle events: server includes either id or conversation_id.
    if (p['id'] != _call.id && p['conversation_id'] != _call.conversationId) {
      return;
    }
    if (t == 'call.answered') {
      setState(() => _call = CallSession.fromJson(p));
      _startTicker();
      // Caller now starts offering media.
      _rtc?.startIfCaller();
    } else if (t == 'call.rejected' || t == 'call.ended') {
      _ticker?.cancel();
      setState(() => _call = CallSession.fromJson(p));
      _autoClose(
        reason:
            t == 'call.rejected' ? 'Cuộc gọi bị từ chối' : 'Cuộc gọi đã kết thúc',
      );
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
    _rtc?.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    // Callee inits RTC right at the accept gesture (browser permission OK here).
    await _initRtc();
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

  Future<void> _toggleMic() async {
    setState(() => _muted = !_muted);
    await _rtc?.setMic(!_muted);
  }

  Future<void> _toggleVideo() async {
    setState(() => _videoOn = !_videoOn);
    await _rtc?.setVideo(_videoOn);
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
    final isVideo = _call.kind == 'video';

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Layer 0: background gradient (visible for voice call / pre-connect)
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF1E1B2E),
                  Color(0xFF3B2D6E),
                  Color(0xFF5B4ABE),
                ],
              ),
            ),
          ),
          // Layer 1: remote stream. ALWAYS in tree (even if voice-only) so
          // the underlying <video> element exists and browser autoplays
          // its audio track. For voice-only we hide it at 1x1.
          if (_rtc != null)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: Opacity(
                  opacity: isVideo && ongoing && _hasRemoteVideo ? 1.0 : 0.0,
                  child: RTCVideoView(
                    _rtc!.remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: false,
                  ),
                ),
              ),
            ),

          // Layer 2: dim overlay only when remote video is on (so controls remain readable)
          if (isVideo && ongoing && _hasRemoteVideo)
            Container(color: Colors.black.withValues(alpha: 0.35)),

          SafeArea(
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
                              isVideo ? Icons.videocam : Icons.call,
                              color: Colors.white,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              isVideo ? 'Video' : 'Thoại',
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

                // Big avatar / pulse: hide when remote video is showing
                if (!(isVideo && ongoing && _hasRemoteVideo)) ...[
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
                ],

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
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 14),
                ),
                if (_rtcError != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      _rtcError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.orangeAccent, fontSize: 12),
                    ),
                  ),
                ],

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
                          onTap: _toggleMic,
                        ),
                        _toggleBtn(
                          icon:
                              _speaker ? Icons.volume_up : Icons.volume_down,
                          label: 'Loa',
                          active: _speaker,
                          onTap: () => setState(() => _speaker = !_speaker),
                        ),
                        if (isVideo)
                          _toggleBtn(
                            icon: _videoOn
                                ? Icons.videocam
                                : Icons.videocam_off,
                            label: 'Camera',
                            active: _videoOn,
                            onTap: _toggleVideo,
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

          // Layer 3: local video PIP (top-right) when video call + ongoing + we have a renderer
          if (isVideo && ongoing && _rtc != null && _videoOn)
            Positioned(
              top: 80,
              right: 16,
              child: Container(
                width: 110,
                height: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: RTCVideoView(
                    _rtc!.localRenderer,
                    objectFit:
                        RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    mirror: true,
                  ),
                ),
              ),
            ),
        ],
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
              child: Icon(icon,
                  color: active ? AppPalette.indigo : Colors.white),
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
