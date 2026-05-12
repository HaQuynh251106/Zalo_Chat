import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import 'red_pocket_overlay.dart';

/// Red-envelope (lì xì) representation of a money message. Closed for the
/// receiver until they tap to reveal via [RedPocketOverlay]; once opened (or
/// for the sender), the amount is visible inline.
class MoneyMessageBubble extends StatelessWidget {
  final Message message;
  final bool mine;
  final VoidCallback? onLongPress;
  // Optional sender identity to forward to the open-overlay.
  final String? peerName;
  final String? peerAvatar;

  const MoneyMessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.onLongPress,
    this.peerName,
    this.peerAvatar,
  });

  @override
  Widget build(BuildContext context) {
    final cents = message.moneyAmountCents ?? 0;
    final opened = message.isMoneyOpened;
    final revealed = mine || opened;
    final memo = message.body.trim();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(
            MediaQuery.of(context).size.width * 0.72,
            AppLayout.bubbleMaxWidth,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
          child: GestureDetector(
            onLongPress: onLongPress,
            onTap: () => _onTap(context),
            child: Hero(
              tag: 'red-pocket-${message.id}',
              flightShuttleBuilder: (_, __, ___, ____, _____) =>
                  RedPocketCard(message: message, mine: mine, opened: opened),
              child: RedPocketCard(
                message: message,
                mine: mine,
                opened: opened,
                revealedAmountCents: revealed ? cents : null,
                memo: memo,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onTap(BuildContext context) async {
    if (mine) {
      _showSenderDetail(context);
      return;
    }
    if (message.isMoneyOpened) {
      _showReceiverDetail(context);
      return;
    }
    final me = context.read<AuthProvider>().user?.id;
    if (me == message.senderId) {
      _showSenderDetail(context);
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: false,
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => RedPocketOverlay(
          message: message,
          senderName: peerName,
          senderAvatar: peerAvatar,
        ),
      ),
    );
  }

  void _showSenderDetail(BuildContext context) {
    final cents = message.moneyAmountCents ?? 0;
    final fmt = NumberFormat('#,###', 'vi_VN').format(cents ~/ 100);
    final opened = message.isMoneyOpened;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Lì xì đã gửi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$fmt ₫',
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (message.body.isNotEmpty)
              Text(message.body,
                  style: const TextStyle(color: AppPalette.textSecondary)),
            const SizedBox(height: 8),
            Text(
              opened
                  ? 'Đã được mở lúc ${DateFormat('HH:mm dd/MM/yyyy').format(message.moneyOpenedAt!.toLocal())}'
                  : 'Người nhận chưa mở.',
              style: const TextStyle(
                  color: AppPalette.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng')),
        ],
      ),
    );
  }

  void _showReceiverDetail(BuildContext context) {
    final cents = message.moneyAmountCents ?? 0;
    final fmt = NumberFormat('#,###', 'vi_VN').format(cents ~/ 100);
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Lì xì đã nhận'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$fmt ₫',
                style: const TextStyle(
                    fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            if (message.body.isNotEmpty)
              Text(message.body,
                  style: const TextStyle(color: AppPalette.textSecondary)),
            const SizedBox(height: 8),
            if (message.moneyOpenedAt != null)
              Text(
                'Đã mở lúc ${DateFormat('HH:mm dd/MM/yyyy').format(message.moneyOpenedAt!.toLocal())}',
                style: const TextStyle(
                    color: AppPalette.textSecondary, fontSize: 12),
              ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng')),
        ],
      ),
    );
  }
}

/// The visual pocket itself, used as both the chat bubble and the
/// hero-flight shuttle. Public so [RedPocketOverlay] can reuse it as its
/// destination widget.
class RedPocketCard extends StatelessWidget {
  final Message message;
  final bool mine;
  final bool opened;
  final int? revealedAmountCents;
  final String memo;

  const RedPocketCard({
    super.key,
    required this.message,
    required this.mine,
    required this.opened,
    this.revealedAmountCents,
    this.memo = '',
  });

  @override
  Widget build(BuildContext context) {
    final width = math.min(
      MediaQuery.of(context).size.width * 0.66,
      280.0,
    );
    final fmt = NumberFormat('#,###', 'vi_VN');
    final revealed = revealedAmountCents != null;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: width,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFC8102E),
              Color(0xFFE63946),
              Color(0xFFB00020),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFB00020).withValues(alpha: 0.38),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _goldSeal(opened: opened),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'LÌ XÌ MAY MẮN',
                        style: TextStyle(
                          color: Color(0xFFFFE6A8),
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        revealed
                            ? '${fmt.format(revealedAmountCents! ~/ 100)} ₫'
                            : (opened
                                ? 'Đã được mở'
                                : (mine ? 'Đang chờ mở' : 'Nhấn để mở')),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: revealed ? 22 : 16,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (memo.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  memo,
                  style: const TextStyle(
                    color: Color(0xFFFFE6A8),
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.celebration_outlined,
                    color: Color(0xFFFFE6A8), size: 14),
                const SizedBox(width: 6),
                Text(
                  mine ? 'Bạn đã gửi lì xì' : 'Lumo Lì xì',
                  style: const TextStyle(
                      color: Color(0xFFFFE6A8), fontSize: 11),
                ),
                const Spacer(),
                Text(
                  DateFormat('HH:mm').format(message.createdAt.toLocal()),
                  style:
                      const TextStyle(color: Color(0xFFFFE6A8), fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _goldSeal({required bool opened}) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [Color(0xFFFFF3B0), Color(0xFFFFCC33), Color(0xFFC9A227)],
          stops: [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFCC33).withValues(alpha: 0.55),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: opened
            ? const Icon(Icons.lock_open_rounded,
                color: Color(0xFF8B0000), size: 22)
            : const Text(
                '福',
                style: TextStyle(
                  color: Color(0xFF8B0000),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
      ),
    );
  }
}
