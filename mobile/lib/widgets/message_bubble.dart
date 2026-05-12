import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../theme.dart';
import 'audio_message_bubble.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool mine;
  final bool showTail;
  final bool seen;
  final VoidCallback? onLongPress;

  const MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.showTail = true,
    this.seen = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('HH:mm');
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine || !showTail ? 18 : 4),
      bottomRight: Radius.circular(mine && showTail ? 4 : 18),
    );

    final isRecalled = message.recalled;
    final isImage =
        message.type == 'image' && message.mediaUrl.isNotEmpty && !isRecalled;
    final isAudio =
        message.type == 'audio' && message.mediaUrl.isNotEmpty && !isRecalled;
    final hasReply = message.replyToSnippet.isNotEmpty;

    final timeAndStatus = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          df.format(message.createdAt.toLocal()),
          style: TextStyle(
            color: mine
                ? Colors.white.withValues(alpha: 0.85)
                : AppPalette.textSecondary,
            fontSize: 10.5,
          ),
        ),
        if (mine) ...[
          const SizedBox(width: 4),
          Icon(
            seen ? Icons.done_all : Icons.done,
            size: 13,
            color: seen
                ? const Color(0xFFB5E5FF)
                : Colors.white.withValues(alpha: 0.85),
          ),
        ],
      ],
    );

    final content = isImage
        ? ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              message.mediaUrl,
              fit: BoxFit.cover,
              width: 240,
              errorBuilder: (_, __, ___) =>
                  Container(width: 240, height: 180, color: Colors.black12),
            ),
          )
        : isAudio
            ? AudioMessageBubble(url: message.mediaUrl, mine: mine)
            : Text(
            isRecalled ? 'Tin nhắn đã được thu hồi' : message.body,
            style: TextStyle(
              color: isRecalled
                  ? (mine ? Colors.white70 : AppPalette.textSecondary)
                  : (mine ? Colors.white : AppPalette.textPrimary),
              fontStyle: isRecalled ? FontStyle.italic : FontStyle.normal,
              fontSize: 15,
              height: 1.35,
            ),
          );

    final decoration = BoxDecoration(
      borderRadius: radius,
      gradient: mine && !isRecalled ? AppPalette.primaryGradient : null,
      color: mine
          ? (isRecalled ? AppPalette.indigo.withValues(alpha: 0.6) : null)
          : Colors.white,
      boxShadow: mine
          ? [
              BoxShadow(
                color: AppPalette.indigo.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: math.min(
              MediaQuery.of(context).size.width * 0.78,
              AppLayout.bubbleMaxWidth,
            ),
          ),
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 6),
                padding: isImage
                    ? const EdgeInsets.all(4)
                    : const EdgeInsets.fromLTRB(14, 8, 12, 6),
                decoration: decoration,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasReply && !isRecalled) _replyQuote(),
                    content,
                    Padding(
                      padding: EdgeInsets.only(
                          top: isImage ? 6 : 2, right: isImage ? 6 : 0),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: timeAndStatus,
                      ),
                    ),
                  ],
                ),
              ),
              if (message.reactions.isNotEmpty && !isRecalled)
                _reactionsFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _replyQuote() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: mine
            ? Colors.white.withValues(alpha: 0.15)
            : AppPalette.indigo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: mine ? Colors.white : AppPalette.indigo,
            width: 3,
          ),
        ),
      ),
      child: Text(
        message.replyToSnippet,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          color: mine
              ? Colors.white.withValues(alpha: 0.9)
              : AppPalette.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _reactionsFooter() {
    // Group by emoji + count
    final grouped = <String, int>{};
    for (final r in message.reactions) {
      grouped[r.emoji] = (grouped[r.emoji] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2, left: 12, right: 12),
      child: Wrap(
        spacing: 4,
        children: grouped.entries.map((e) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e.key, style: const TextStyle(fontSize: 14)),
                if (e.value > 1) ...[
                  const SizedBox(width: 4),
                  Text(
                    '${e.value}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppPalette.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
