import 'dart:async';
import 'package:flutter/material.dart';
import 'package:record/record.dart';
import '../theme.dart';

/// Replaces the chat composer while a voice note is being recorded.
/// Calls [onSend] with the local path/blob URL on stop, or [onCancel] on cancel.
class VoiceRecorder extends StatefulWidget {
  final void Function(String path, Duration duration) onSend;
  final VoidCallback onCancel;
  const VoiceRecorder({super.key, required this.onSend, required this.onCancel});

  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder>
    with SingleTickerProviderStateMixin {
  final _rec = AudioRecorder();
  Timer? _ticker;
  late final AnimationController _pulse;
  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _start();
  }

  Future<void> _start() async {
    try {
      if (!await _rec.hasPermission()) {
        setState(() => _error = 'Trình duyệt từ chối quyền microphone');
        return;
      }
      // Use a generic webm path; on web it is ignored, on mobile it's a real path.
      final path = 'voice_${DateTime.now().millisecondsSinceEpoch}.webm';
      await _rec.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          numChannels: 1,
          sampleRate: 24000,
        ),
        path: path,
      );
      _startedAt = DateTime.now();
      setState(() => _ready = true);
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted || _startedAt == null) return;
        setState(() => _elapsed = DateTime.now().difference(_startedAt!));
      });
    } catch (e) {
      setState(() => _error = 'Không khởi động được ghi âm: $e');
    }
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _pulse.stop();
    try {
      final path = await _rec.stop();
      if (path == null) {
        widget.onCancel();
        return;
      }
      widget.onSend(path, _elapsed);
    } catch (_) {
      widget.onCancel();
    }
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    _pulse.stop();
    try {
      await _rec.cancel();
    } catch (_) {}
    widget.onCancel();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pulse.dispose();
    _rec.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        color: Colors.red.withValues(alpha: 0.06),
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: widget.onCancel,
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 14),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Huỷ',
            onPressed: _cancel,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
          ),
          const SizedBox(width: 4),
          FadeTransition(
            opacity: Tween(begin: 0.3, end: 1.0).animate(_pulse),
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _ready ? _fmt(_elapsed) : 'Đang khởi động...',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppPalette.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Đang ghi âm — nhấn Gửi để chia sẻ',
              style: TextStyle(color: AppPalette.textSecondary, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: _ready ? _stop : null,
              child: Ink(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: _ready ? AppPalette.primaryGradient : null,
                  color: _ready ? null : AppPalette.divider,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send_rounded,
                  color: _ready ? Colors.white : AppPalette.textSecondary,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
