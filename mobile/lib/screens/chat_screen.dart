import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/call.dart';
import '../models/message.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';
import '../theme.dart';
import '../widgets/chat_background.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_dots.dart';
import '../widgets/user_avatar.dart';
import 'call_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String title;
  final String peerAvatar;
  final String? peerId;
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.peerAvatar = '',
    this.peerId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Message> _messages = [];
  final Set<String> _typingUsers = <String>{};
  bool _loading = true;
  bool _sentTyping = false;
  bool _peerOnline = false;
  DateTime? _peerLastRead; // for read-receipt check on my messages
  late final WsClient _ws;
  String? _myId;
  Timer? _typingOffTimer;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _ws = context.read<WsClient>();
    _myId = context.read<AuthProvider>().user?.id;
    _wsSub = _ws.events.listen(_onWs);
    _load();
  }

  void _onWs(Map<String, dynamic> ev) {
    final t = ev['type'];
    final p = ev['payload'];
    if (p is! Map<String, dynamic>) return;
    if (t == 'message.new') {
      if (p['conversation_id'] != widget.conversationId) return;
      final incoming = Message.fromJson(p);
      if (_messages.any((m) => m.id == incoming.id)) return;
      setState(() => _messages.insert(0, incoming));
      // auto mark-read if I'm viewing the chat
      _markRead();
    } else if (t == 'message.recalled') {
      if (p['conversation_id'] != widget.conversationId) return;
      final id = p['id'] as String;
      final i = _messages.indexWhere((m) => m.id == id);
      if (i >= 0) {
        final old = _messages[i];
        setState(() => _messages[i] = Message(
              id: old.id,
              conversationId: old.conversationId,
              senderId: old.senderId,
              type: old.type,
              body: '',
              mediaUrl: old.mediaUrl,
              recalled: true,
              createdAt: old.createdAt,
            ));
      }
    } else if (t == 'typing') {
      if (p['conversation_id'] != widget.conversationId) return;
      final userId = p['user_id'] as String?;
      if (userId == null || userId == _myId) return;
      final isTyping = (p['is_typing'] ?? true) as bool;
      setState(() =>
          isTyping ? _typingUsers.add(userId) : _typingUsers.remove(userId));
    } else if (t == 'presence.update') {
      final id = p['user_id'] as String?;
      if (id != null && id == widget.peerId) {
        setState(() => _peerOnline = (p['online'] ?? false) as bool);
      }
    } else if (t == 'read.receipt') {
      if (p['conversation_id'] != widget.conversationId) return;
      final uid = p['user_id'] as String?;
      if (uid == _myId) return;
      final at = DateTime.tryParse(p['read_at'] as String? ?? '');
      if (at != null) setState(() => _peerLastRead = at);
    }
  }

  @override
  void dispose() {
    _sendTyping(false);
    _typingOffTimer?.cancel();
    _wsSub?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiClient>();
      final data =
          await api.get('/conversations/${widget.conversationId}/messages')
              as List<dynamic>;
      setState(() {
        _messages
          ..clear()
          ..addAll(
              data.map((e) => Message.fromJson(e as Map<String, dynamic>)));
        _loading = false;
      });
      _markRead();
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _markRead() async {
    try {
      final api = context.read<ApiClient>();
      await api.post('/conversations/${widget.conversationId}/read');
    } catch (_) {}
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    _input.clear();
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post(
        '/conversations/${widget.conversationId}/messages',
        body: {'type': 'text', 'body': body},
      );
      _sendTyping(false);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _attachImage() async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final res = await api.upload(bytes: bytes, filename: picked.name);
      final mediaUrl = _absUrl((res['url'] ?? res['path']) as String);
      await api.post('/conversations/${widget.conversationId}/messages', body: {
        'type': 'image',
        'body': '',
        'media_url': mediaUrl,
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  String _absUrl(String pathOrUrl) => pathOrUrl.startsWith('http')
      ? pathOrUrl
      : '${AppConfig.apiBase}$pathOrUrl';

  void _handleInputChanged(String value) {
    if (value.trim().isEmpty) {
      _typingOffTimer?.cancel();
      _sendTyping(false);
      return;
    }
    _sendTyping(true);
    _typingOffTimer?.cancel();
    _typingOffTimer =
        Timer(const Duration(seconds: 2), () => _sendTyping(false));
  }

  void _sendTyping(bool isTyping) {
    if (_sentTyping == isTyping) return;
    _sentTyping = isTyping;
    _ws.send('typing',
        {'conversation_id': widget.conversationId, 'is_typing': isTyping});
  }

  Future<void> _recall(Message m) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Thu hồi tin nhắn?'),
        content:
            const Text('Tin nhắn sẽ bị xoá ở cả 2 phía. Không thể hoàn tác.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Thu hồi'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    if (!mounted) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post('/messages/${m.id}/recall');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _startCall(String kind) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final data = await api.post('/calls',
              body: {'conversation_id': widget.conversationId, 'kind': kind})
          as Map<String, dynamic>;
      final session = CallSession.fromJson(data);
      nav.push(MaterialPageRoute(
        builder: (_) => CallScreen(
          initial: session,
          isIncoming: false,
          peerName: widget.title,
          peerAvatar: widget.peerAvatar,
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: _ChatAppBar(
          title: widget.title,
          avatarUrl: widget.peerAvatar,
          online: _peerOnline,
          typing: _typingUsers.isNotEmpty,
          onVoiceCall: () => _startCall('voice'),
          onVideoCall: () => _startCall('video'),
        ),
      ),
      body: ChatBackground(
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppPalette.indigo))
                  : _messages.isEmpty
                      ? const _EmptyChat()
                      : _buildList(),
            ),
            if (_typingUsers.isNotEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 16, 6),
                child: Row(
                  children: [
                    TypingDots(),
                    SizedBox(width: 8),
                    Text('Đang nhập...',
                        style: TextStyle(
                            color: AppPalette.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
            _Composer(
              controller: _input,
              onChanged: _handleInputChanged,
              onSend: _send,
              onAttachImage: _attachImage,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    final df = DateFormat('EEE, dd/MM');
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
      itemCount: _messages.length,
      itemBuilder: (_, i) {
        final m = _messages[i];
        final mine = m.senderId == _myId;
        final older = i < _messages.length - 1 ? _messages[i + 1] : null;
        final showDayHeader = older == null ||
            !_sameDay(older.createdAt.toLocal(), m.createdAt.toLocal());
        final newer = i > 0 ? _messages[i - 1] : null;
        final showTail = newer == null || newer.senderId != m.senderId;
        final seen = mine &&
            _peerLastRead != null &&
            !m.createdAt.isAfter(_peerLastRead!);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (showDayHeader)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppPalette.indigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    df.format(m.createdAt.toLocal()),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppPalette.indigo,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Dismissible(
              key: ValueKey(m.id),
              direction: mine && !m.recalled
                  ? DismissDirection.endToStart
                  : DismissDirection.none,
              confirmDismiss: (_) async {
                _recall(m);
                return false;
              },
              background: const SizedBox.shrink(),
              secondaryBackground: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.undo, color: Colors.red),
                  ),
                ),
              ),
              child: MessageBubble(
                message: m,
                mine: mine,
                showTail: showTail,
                seen: seen,
                onLongPress: mine && !m.recalled ? () => _recall(m) : null,
              ),
            ),
          ],
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _ChatAppBar extends StatelessWidget {
  final String title;
  final String avatarUrl;
  final bool online;
  final bool typing;
  final VoidCallback onVoiceCall;
  final VoidCallback onVideoCall;
  const _ChatAppBar({
    required this.title,
    required this.avatarUrl,
    required this.online,
    required this.typing,
    required this.onVoiceCall,
    required this.onVideoCall,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: AppPalette.textPrimary),
              ),
              UserAvatar(name: title, url: avatarUrl, size: 42, online: online),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      typing
                          ? 'Đang soạn tin...'
                          : (online ? 'Đang hoạt động' : 'Ngoại tuyến'),
                      style: TextStyle(
                        fontSize: 11,
                        color: typing
                            ? AppPalette.indigo
                            : (online
                                ? AppPalette.mint
                                : AppPalette.textSecondary),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onVoiceCall,
                icon: const Icon(Icons.call_outlined, color: AppPalette.indigo),
                tooltip: 'Gọi thoại',
              ),
              IconButton(
                onPressed: onVideoCall,
                icon: const Icon(Icons.videocam_outlined,
                    color: AppPalette.indigo),
                tooltip: 'Gọi video',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onAttachImage;
  const _Composer({
    required this.controller,
    required this.onChanged,
    required this.onSend,
    required this.onAttachImage,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, -4)),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 12),
        child: Row(
          children: [
            _circleIcon(Icons.image_outlined, onAttachImage),
            const SizedBox(width: 6),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppPalette.bgLight,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        onChanged: onChanged,
                        onSubmitted: (_) => onSend(),
                        minLines: 1,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          hintText: 'Nhắn gì đó dễ thương...',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.emoji_emotions_outlined,
                          color: AppPalette.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onSend,
                child: Ink(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    gradient: AppPalette.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleIcon(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppPalette.bgLight,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: AppPalette.indigo),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppPalette.coral.withValues(alpha: 0.7),
                  AppPalette.violet.withValues(alpha: 0.7)
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.waving_hand, color: Colors.white, size: 34),
          ),
          const SizedBox(height: 14),
          const Text('Hãy gửi lời chào!',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Vuốt trái để thu hồi tin của mình',
              style: TextStyle(color: AppPalette.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
