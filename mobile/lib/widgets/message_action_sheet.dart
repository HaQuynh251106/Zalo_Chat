import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/message.dart';
import '../theme.dart';

const _emojiBar = ['❤️', '👍', '😂', '😮', '😢', '🔥'];

/// Bottom sheet shown on long-press of a message bubble.
/// Returns one of: ('react', emoji) | ('recall', null) | ('copy', null) | null
class MessageActionSheet extends StatelessWidget {
  final Message message;
  final bool mine;
  const MessageActionSheet({super.key, required this.message, required this.mine});

  static Future<MapEntry<String, String?>?> show(
    BuildContext context, {
    required Message message,
    required bool mine,
  }) {
    return showModalBottomSheet<MapEntry<String, String?>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => MessageActionSheet(message: message, mine: mine),
    );
  }

  bool get _canRecall {
    if (!mine || message.recalled) return false;
    return DateTime.now().difference(message.createdAt).inHours < 24;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppPalette.divider,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 14),
            // Emoji react bar
            if (!message.recalled)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: _emojiBar.map((e) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(40),
                      onTap: () => Navigator.pop(
                          context, MapEntry('react', e)),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Text(e, style: const TextStyle(fontSize: 28)),
                      ),
                    );
                  }).toList(),
                ),
              ),
            const Divider(height: 24),
            if (!message.recalled)
              _action(
                context,
                Icons.reply_rounded,
                'Trả lời',
                () => Navigator.pop(context, const MapEntry('reply', null)),
              ),
            if (!message.recalled)
              _action(
                context,
                Icons.send_to_mobile_rounded,
                'Chuyển tiếp',
                () => Navigator.pop(context, const MapEntry('forward', null)),
              ),
            if (!message.recalled)
              _action(
                context,
                message.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin,
                message.isPinned ? 'Bỏ ghim' : 'Ghim tin nhắn',
                () => Navigator.pop(context, const MapEntry('pin', null)),
              ),
            if (!message.recalled)
              _action(
                context,
                Icons.content_copy_rounded,
                'Sao chép',
                () async {
                  await Clipboard.setData(ClipboardData(text: message.body));
                  if (context.mounted) {
                    Navigator.pop(context, const MapEntry('copy', null));
                  }
                },
              ),
            _action(
              context,
              Icons.visibility_off_outlined,
              'Xoá ở phía tôi',
              () => Navigator.pop(context, const MapEntry('hide', null)),
            ),
            if (_canRecall)
              _action(
                context,
                Icons.undo_rounded,
                'Thu hồi tin nhắn',
                () => Navigator.pop(context, const MapEntry('recall', null)),
                danger: true,
              ),
            _action(
              context,
              Icons.close_rounded,
              'Huỷ',
              () => Navigator.pop(context),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final color = danger ? Colors.red : AppPalette.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
