import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/call.dart';
import '../providers/auth_provider.dart';
import '../screens/call_screen.dart';
import '../services/ws_client.dart';

/// Sits above the app and intercepts `call.incoming` WS events.
/// When triggered (and the current user is not the initiator), it pushes
/// the CallScreen onto the navigator.
class IncomingCallOverlay extends StatefulWidget {
  final Widget child;
  const IncomingCallOverlay({super.key, required this.child});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  StreamSubscription? _sub;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    final ws = context.read<WsClient>();
    _sub = ws.events.listen(_onEvent);
  }

  void _onEvent(Map<String, dynamic> ev) {
    if (ev['type'] != 'call.incoming' || _showing) return;
    final p = ev['payload'];
    if (p is! Map<String, dynamic>) return;
    final session = CallSession.fromJson(p);
    final me = context.read<AuthProvider>().user?.id;
    if (me == null || session.initiatorId == me) return; // ignore self echo
    _push(session);
  }

  Future<void> _push(CallSession s) async {
    _showing = true;
    final nav = Navigator.of(context, rootNavigator: true);
    await nav.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          initial: s,
          isIncoming: true,
          peerName: s.initiatorName.isEmpty ? 'Cuộc gọi đến' : s.initiatorName,
          peerAvatar: s.initiatorAvatar,
        ),
      ),
    );
    _showing = false;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
