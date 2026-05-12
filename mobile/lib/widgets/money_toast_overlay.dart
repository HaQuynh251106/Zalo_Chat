import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/wallet.dart';
import '../screens/chat_screen.dart';
import '../services/ws_client.dart';
import '../theme.dart';
import 'user_avatar.dart';

class MoneyToastOverlay extends StatefulWidget {
  final Widget child;
  const MoneyToastOverlay({super.key, required this.child});

  @override
  State<MoneyToastOverlay> createState() => _MoneyToastOverlayState();
}

class _MoneyToastOverlayState extends State<MoneyToastOverlay> {
  StreamSubscription? _sub;
  OverlayEntry? _entry;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sub = context.read<WsClient>().events.listen(_onEvent);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _entry?.remove();
    _sub?.cancel();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> ev) {
    if (ev['type'] != 'money.received') return;
    final payload = ev['payload'];
    if (payload is! Map<String, dynamic>) return;
    final from = payload['from'];
    if (from is! Map<String, dynamic>) return;
    final amount = (payload['amount_cents'] as num? ?? 0).toInt();
    final conversationId = payload['conversation_id'] as String?;
    final peerId = from['id'] as String?;
    final name = (from['name'] ?? from['display_name'] ?? 'Bạn bè') as String;
    final avatar = (from['avatar'] ?? from['avatar_url'] ?? '') as String;
    if (amount <= 0 || conversationId == null || peerId == null) return;
    _showToast(
      name: name,
      avatar: avatar,
      amountCents: amount,
      conversationId: conversationId,
      peerId: peerId,
    );
  }

  void _showToast({
    required String name,
    required String avatar,
    required int amountCents,
    required String conversationId,
    required String peerId,
  }) {
    _timer?.cancel();
    _entry?.remove();
    _entry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 12,
        left: 14,
        right: 14,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              _entry?.remove();
              _entry = null;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    conversationId: conversationId,
                    title: name,
                    peerAvatar: avatar,
                    peerId: peerId,
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  UserAvatar(name: name, url: avatar, size: 42),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$name vừa chuyển bạn ${formatVndCents(amountCents)}',
                      style: const TextStyle(
                        color: AppPalette.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: AppPalette.indigo),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
    _timer = Timer(const Duration(seconds: 4), () {
      _entry?.remove();
      _entry = null;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
