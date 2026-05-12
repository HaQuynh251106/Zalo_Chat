import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../theme.dart';

/// Gold gradient card shown in-line in a chat when one user transfers money
/// to another. Tapping it opens a detail dialog.
class MoneyMessageBubble extends StatelessWidget {
  final Message message;
  final bool mine;
  final VoidCallback? onLongPress;

  const MoneyMessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final cents = message.moneyAmountCents ?? 0;
    final vnd = cents ~/ 100;
    final fmt = NumberFormat('#,###', 'vi_VN');
    final amount = fmt.format(vnd);
    final timeFmt = DateFormat('HH:mm');
    final label = mine ? 'Đã gửi' : 'Đã nhận';
    final memo = message.body.trim();

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(
            MediaQuery.of(context).size.width * 0.78,
            AppLayout.bubbleMaxWidth,
          ),
        ),
        child: GestureDetector(
          onLongPress: onLongPress,
          onTap: () => _showDetail(context, amount, label),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [
                  Color(0xFFFFB347),
                  Color(0xFFFFCC33),
                  Color(0xFFFF8C42)
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF8C42).withValues(alpha: 0.32),
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
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.payments_outlined,
                          color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$amount ₫',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 22,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (memo.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      memo,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    timeFmt.format(message.createdAt.toLocal()),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDetail(
      BuildContext context, String amount, String label) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.payments, color: Color(0xFFFF8C42)),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: AppPalette.textPrimary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$amount ₫',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            if (message.body.isNotEmpty) ...[
              Text(message.body,
                  style: const TextStyle(
                      color: AppPalette.textSecondary, fontSize: 13)),
              const SizedBox(height: 6),
            ],
            Text(
              DateFormat('dd/MM/yyyy HH:mm')
                  .format(message.createdAt.toLocal()),
              style: const TextStyle(
                  color: AppPalette.textSecondary, fontSize: 12),
            ),
            if (message.moneyTxnId != null) ...[
              const SizedBox(height: 6),
              Text(
                'Mã giao dịch: ${message.moneyTxnId}',
                style: const TextStyle(
                    color: AppPalette.textSecondary, fontSize: 11),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}
