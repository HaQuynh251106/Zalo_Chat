import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
import '../widgets/forward_picker.dart';
import '../widgets/message_action_sheet.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_dots.dart';
import '../widgets/user_avatar.dart';
import '../widgets/voice_recorder.dart';
import 'call_screen.dart';
import 'group_info_screen.dart';
import 'wallet_transfer_screen.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String title;
  final String peerAvatar;
  final String? peerId;
  final bool isGroup;
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.peerAvatar = '',
    this.peerId,
    this.isGroup = false,
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
  bool _muted = false;
  bool _blocked = false;
  bool _recording = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _searching = false;
  String _searchQuery = '';
  Message? _replyingTo;
  Message? _pinnedHead; // latest pinned message shown in banner
  DateTime? _peerLastRead;
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
    _scroll.addListener(_onScroll);
    _load();
  }

  void _onScroll() {
    // List is reversed, so scrolling "up" visually = approaching maxScrollExtent.
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels > pos.maxScrollExtent - 240) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _messages.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final oldest = _messages.last.createdAt.toUtc().toIso8601String();
      final api = context.read<ApiClient>();
      final data = await api.get(
        '/conversations/${widget.conversationId}/messages',
        query: {'limit': '30', 'before': oldest},
      ) as List<dynamic>;
      final older = data
          .map((e) => Message.fromJson(e as Map<String, dynamic>))
          .where((m) => !_messages.any((x) => x.id == m.id))
          .toList();
      setState(() {
        _messages.addAll(older);
        if (older.length < 30) _hasMore = false;
      });
    } catch (_) {
      // silent fail; user can scroll again later
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onWs(Map<String, dynamic> ev) {
    final t = ev['type'];
    final p = ev['payload'];
    if (p is! Map<String, dynamic>) return;
    if (t == 'message.new' || t == 'message.created') {
      if (p['conversation_id'] != widget.conversationId) return;
      final incoming = Message.fromJson(p);
      if (_messages.any((m) => m.id == incoming.id)) return;
      setState(() => _messages.insert(0, incoming));
      _markRead();
    } else if (t == 'message.recalled') {
      if (p['conversation_id'] != widget.conversationId) return;
      final id = p['id'] as String;
      final i = _messages.indexWhere((m) => m.id == id);
      if (i >= 0) {
        setState(() =>
            _messages[i] = _messages[i].copyWith(recalled: true, body: ''));
      }
    } else if (t == 'message.reaction') {
      if (p['conversation_id'] != widget.conversationId) return;
      final msgId = p['message_id'] as String?;
      final userId = p['user_id'] as String?;
      final emoji = (p['emoji'] ?? '') as String;
      if (msgId == null || userId == null) return;
      final i = _messages.indexWhere((m) => m.id == msgId);
      if (i < 0) return;
      final current = List<MessageReaction>.from(_messages[i].reactions);
      current.removeWhere((r) => r.userId == userId);
      if (emoji.isNotEmpty) {
        current.add(MessageReaction(userId: userId, emoji: emoji));
      }
      setState(() => _messages[i] = _messages[i].copyWith(reactions: current));
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
    } else if (t == 'message.pinned') {
      if (p['conversation_id'] != widget.conversationId) return;
      final id = p['id'] as String?;
      final pinned = (p['pinned'] ?? false) as bool;
      if (id == null) return;
      final i = _messages.indexWhere((m) => m.id == id);
      if (i >= 0) {
        setState(() => _messages[i] = _messages[i].copyWith(
              pinnedAt: pinned ? DateTime.now() : null,
            ));
      }
      _loadPinned();
    } else if (t == 'money.opened') {
      // The receiver tapped to open a Lì xì. Update the matching message
      // bubble so the sender's UI flips from "Đang chờ mở" → "Đã được mở".
      if (p['conversation_id'] != widget.conversationId) return;
      final id = p['message_id'] as String?;
      final openedAt = DateTime.tryParse(p['opened_at'] as String? ?? '');
      if (id == null || openedAt == null) return;
      final i = _messages.indexWhere((m) => m.id == id);
      if (i >= 0) {
        setState(() => _messages[i] =
            _messages[i].copyWith(moneyOpenedAt: openedAt));
      }
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
      final data = await api.get(
          '/conversations/${widget.conversationId}/messages',
          query: {'limit': '30'}) as List<dynamic>;
      setState(() {
        _messages
          ..clear()
          ..addAll(
              data.map((e) => Message.fromJson(e as Map<String, dynamic>)));
        _hasMore = data.length >= 30;
        _loading = false;
      });
      _markRead();
      _loadPinned();
      // Hydrate block state for direct chats.
      if (widget.peerId != null) {
        try {
          final blocked = await api.get('/users/blocked') as List<dynamic>;
          if (!mounted) return;
          setState(() => _blocked = blocked
              .any((u) => (u as Map<String, dynamic>)['id'] == widget.peerId));
        } catch (_) {}
      }
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

  Future<void> _loadPinned() async {
    try {
      final api = context.read<ApiClient>();
      final data =
          await api.get('/conversations/${widget.conversationId}/pinned')
              as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _pinnedHead = data.isEmpty
            ? null
            : Message.fromJson(data.first as Map<String, dynamic>);
      });
    } catch (_) {}
  }

  Future<void> _togglePin(Message m) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post(
          m.isPinned ? '/messages/${m.id}/unpin' : '/messages/${m.id}/pin');
      // optimistic: server will broadcast message.pinned and we'll refresh.
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _hideForMe(Message m) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    // optimistic local hide
    setState(() => _messages.removeWhere((x) => x.id == m.id));
    try {
      await api.post('/messages/${m.id}/hide');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      _load();
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty) return;
    _input.clear();
    final replyTo = _replyingTo?.id;
    setState(() => _replyingTo = null);
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post(
        '/conversations/${widget.conversationId}/messages',
        body: {
          'type': 'text',
          'body': body,
          if (replyTo != null) 'reply_to_id': replyTo,
        },
      );
      _sendTyping(false);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('BLOCKED') || s.contains('blocked')) {
      return 'You cannot send messages to this user';
    }
    return s;
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
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
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

  Future<void> _onBubbleLongPress(Message m) async {
    final mine = m.senderId == _myId;
    final result = await MessageActionSheet.show(
      context,
      message: m,
      mine: mine,
    );
    if (result == null || !mounted) return;
    switch (result.key) {
      case 'react':
        await _react(m, result.value ?? '');
        break;
      case 'reply':
        setState(() => _replyingTo = m);
        break;
      case 'forward':
        await _forward(m);
        break;
      case 'pin':
        await _togglePin(m);
        break;
      case 'hide':
        await _hideForMe(m);
        break;
      case 'recall':
        await _recall(m);
        break;
      case 'copy':
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Copied'), duration: Duration(seconds: 1)),
        );
        break;
    }
  }

  Future<void> _forward(Message m) async {
    final target = await ForwardPicker.show(
      context,
      excludeConversationId: widget.conversationId,
    );
    if (target == null || !mounted) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post('/conversations/${target.id}/messages', body: {
        'type': m.type,
        'body': m.recalled ? '' : m.body,
        if (m.mediaUrl.isNotEmpty) 'media_url': m.mediaUrl,
      });
      messenger.showSnackBar(
        SnackBar(content: Text('Forwarded to ${target.title}')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    }
  }

  Future<void> _react(Message m, String emoji) async {
    // Optimistic: update local then call API
    final myId = _myId;
    if (myId == null) return;
    final current = List<MessageReaction>.from(m.reactions);
    final existing = current.indexWhere((r) => r.userId == myId);
    final isSameEmoji = existing >= 0 && current[existing].emoji == emoji;
    final newEmoji = isSameEmoji ? '' : emoji;
    if (existing >= 0) current.removeAt(existing);
    if (newEmoji.isNotEmpty) {
      current.add(MessageReaction(userId: myId, emoji: newEmoji));
    }
    final i = _messages.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      setState(() => _messages[i] = _messages[i].copyWith(reactions: current));
    }
    try {
      await context
          .read<ApiClient>()
          .post('/messages/${m.id}/reactions', body: {'emoji': newEmoji});
    } catch (e) {
      // best-effort rollback by reload
      _load();
    }
  }

  Future<void> _recall(Message m) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post('/messages/${m.id}/recall');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _sendVoice(String pathOrUrl, Duration duration) async {
    setState(() => _recording = false);
    if (duration.inMilliseconds < 500) return; // discard tap-too-short
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      // record returns blob:// URL on web and a real path on native.
      // Both are fetchable via http to obtain bytes.
      final res = await http.get(Uri.parse(pathOrUrl));
      if (res.statusCode != 200) {
        throw 'Could not read audio (HTTP ${res.statusCode})';
      }
      final filename = 'voice_${DateTime.now().millisecondsSinceEpoch}.webm';
      final uploaded = await api.upload(
        bytes: res.bodyBytes,
        filename: filename,
        mimeType: 'audio/webm',
      );
      final mediaUrl = _absUrl((uploaded['url'] ?? uploaded['path']) as String);
      await api.post('/conversations/${widget.conversationId}/messages', body: {
        'type': 'audio',
        'body': '',
        'media_url': mediaUrl,
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    }
  }

  Future<void> _openMoneyTransfer() async {
    if (widget.peerId == null || widget.isGroup) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Money transfer is available for direct chats only'),
        ),
      );
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => WalletTransferScreen(
          initialUserId: widget.peerId,
          initialName: widget.title,
          initialAvatar: widget.peerAvatar,
        ),
      ),
    );
  }

  Future<void> _toggleBlock() async {
    if (widget.peerId == null) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_blocked) {
        await api.post('/users/unblock', body: {'user_id': widget.peerId});
        messenger.showSnackBar(const SnackBar(content: Text('User unblocked')));
      } else {
        await api.post('/users/block', body: {'user_id': widget.peerId});
        messenger.showSnackBar(const SnackBar(content: Text('User blocked')));
      }
      setState(() => _blocked = !_blocked);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _toggleMute() async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final until = _muted
        ? null
        : DateTime.now()
            .add(const Duration(days: 365))
            .toUtc()
            .toIso8601String();
    try {
      await api.post('/conversations/${widget.conversationId}/mute',
          body: {'until': until});
      setState(() => _muted = !_muted);
      messenger.showSnackBar(SnackBar(
          content:
              Text(_muted ? 'Notifications muted' : 'Notifications enabled')));
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
          muted: _muted,
          blocked: _blocked,
          canBlock: widget.peerId != null && !widget.isGroup,
          isGroup: widget.isGroup,
          onToggleSearch: () => setState(() => _searching = !_searching),
          onTapHeader: widget.isGroup
              ? () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupInfoScreen(
                        conversationId: widget.conversationId,
                        title: widget.title,
                        avatarUrl: widget.peerAvatar,
                      ),
                    ),
                  )
              : null,
          onVoiceCall: () => _startCall('voice'),
          onVideoCall: () => _startCall('video'),
          onToggleMute: _toggleMute,
          onToggleBlock: _toggleBlock,
        ),
      ),
      body: ChatBackground(
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: AppLayout.chatContentMaxWidth),
            child: Column(
              children: [
                if (_searching) _searchBar(),
                if (_pinnedHead != null && !_searching)
                  _pinnedBanner(_pinnedHead!),
                Expanded(
                  child: _loading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppPalette.indigo))
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
                        Text('Typing...',
                            style: TextStyle(
                                color: AppPalette.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                if (_replyingTo != null && !_recording)
                  _ReplyPreview(
                    message: _replyingTo!,
                    onClose: () => setState(() => _replyingTo = null),
                  ),
                if (_recording)
                  VoiceRecorder(
                    onSend: _sendVoice,
                    onCancel: () => setState(() => _recording = false),
                  )
                else
                  _Composer(
                    controller: _input,
                    onChanged: _handleInputChanged,
                    onSend: _send,
                    onAttachImage: _attachImage,
                    onSendMoney: _openMoneyTransfer,
                    onStartVoice: () => setState(() => _recording = true),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList() {
    final df = DateFormat('EEE, dd/MM');
    final visible = _searching && _searchQuery.trim().isNotEmpty
        ? _messages
            .where((m) =>
                !m.recalled &&
                m.body.toLowerCase().contains(_searchQuery.toLowerCase()))
            .toList()
        : _messages;
    if (_searching && visible.isEmpty && _searchQuery.trim().isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            'No messages match "$_searchQuery"',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppPalette.textSecondary),
          ),
        ),
      );
    }
    final extra = (_hasMore || _loadingMore) && !_searching ? 1 : 0;
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
      itemCount: visible.length + extra,
      itemBuilder: (_, i) {
        if (i == visible.length) {
          // Top sentinel (because list is reversed): older-messages spinner.
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: _hasMore
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppPalette.indigo),
                    )
                  : const Text('- End of history -',
                      style: TextStyle(
                          color: AppPalette.textSecondary, fontSize: 11)),
            ),
          );
        }
        final m = visible[i];
        final mine = m.senderId == _myId;
        final older = i < visible.length - 1 ? visible[i + 1] : null;
        final showDayHeader = older == null ||
            !_sameDay(older.createdAt.toLocal(), m.createdAt.toLocal());
        final newer = i > 0 ? visible[i - 1] : null;
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
            MessageBubble(
              message: m,
              mine: mine,
              showTail: showTail,
              seen: seen,
              onLongPress: () => _onBubbleLongPress(m),
              peerName: widget.title,
              peerAvatar: widget.peerAvatar,
            ),
          ],
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _pinnedBanner(Message m) {
    final preview =
        m.recalled ? '[recalled]' : (m.type == 'text' ? m.body : '[${m.type}]');
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.coral.withValues(alpha: 0.08),
        border: const Border(
          bottom: BorderSide(color: AppPalette.divider),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 30,
            decoration: BoxDecoration(
              color: AppPalette.coral,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.push_pin, size: 14, color: AppPalette.coral),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Pinned Message',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.coral,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppPalette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Unpin',
            icon: const Icon(Icons.close,
                size: 18, color: AppPalette.textSecondary),
            onPressed: () => _togglePin(m),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppPalette.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppPalette.indigo),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _searchQuery = v),
              decoration: const InputDecoration(
                hintText: 'Search this chat...',
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppPalette.textSecondary),
            onPressed: () => setState(() {
              _searching = false;
              _searchQuery = '';
            }),
          ),
        ],
      ),
    );
  }
}

class _ChatAppBar extends StatelessWidget {
  final String title;
  final String avatarUrl;
  final bool online;
  final bool typing;
  final bool muted;
  final bool blocked;
  final bool canBlock; // false for group chats
  final bool isGroup;
  final VoidCallback? onTapHeader; // open group info
  final VoidCallback onVoiceCall;
  final VoidCallback onVideoCall;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleBlock;
  final VoidCallback onToggleSearch;
  const _ChatAppBar({
    required this.title,
    required this.avatarUrl,
    required this.online,
    required this.typing,
    required this.muted,
    required this.blocked,
    required this.canBlock,
    required this.isGroup,
    required this.onTapHeader,
    required this.onVoiceCall,
    required this.onVideoCall,
    required this.onToggleMute,
    required this.onToggleBlock,
    required this.onToggleSearch,
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
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => Navigator.pop(context),
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: AppPalette.textPrimary, size: 20),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onTapHeader,
                child: UserAvatar(
                    name: title, url: avatarUrl, size: 42, online: online),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: onTapHeader,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ),
                            if (muted) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.notifications_off,
                                  size: 14, color: AppPalette.textSecondary),
                            ],
                            if (isGroup) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right,
                                  size: 16, color: AppPalette.textSecondary),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          typing
                              ? 'Typing...'
                              : (isGroup
                                  ? 'Tap to view members'
                                  : (online ? 'Online' : 'Offline')),
                          style: TextStyle(
                            fontSize: 11,
                            color: typing
                                ? AppPalette.indigo
                                : (isGroup
                                    ? AppPalette.textSecondary
                                    : (online
                                        ? AppPalette.mint
                                        : AppPalette.textSecondary)),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _AppBarIconBtn(
                icon: Icons.call_outlined,
                tooltip: 'Voice Call',
                onPressed: onVoiceCall,
              ),
              _AppBarIconBtn(
                icon: Icons.videocam_outlined,
                tooltip: 'Video Call',
                onPressed: onVideoCall,
              ),
              PopupMenuButton<String>(
                icon:
                    const Icon(Icons.more_vert, color: AppPalette.textPrimary),
                tooltip: 'Options',
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'search') onToggleSearch();
                  if (v == 'mute') onToggleMute();
                  if (v == 'block') onToggleBlock();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'search',
                    child: Row(
                      children: [
                        Icon(Icons.search,
                            size: 18, color: AppPalette.textPrimary),
                        SizedBox(width: 10),
                        Text('Search Messages'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'mute',
                    child: Row(
                      children: [
                        Icon(
                            muted
                                ? Icons.notifications_active
                                : Icons.notifications_off,
                            size: 18,
                            color: AppPalette.textPrimary),
                        const SizedBox(width: 10),
                        Text(muted
                            ? 'Unmute Notifications'
                            : 'Mute Notifications'),
                      ],
                    ),
                  ),
                  if (canBlock)
                    PopupMenuItem(
                      value: 'block',
                      child: Row(
                        children: [
                          Icon(blocked ? Icons.lock_open : Icons.block,
                              size: 18,
                              color: blocked ? AppPalette.indigo : Colors.red),
                          const SizedBox(width: 10),
                          Text(
                            blocked ? 'Unblock User' : 'Block User',
                            style: TextStyle(
                              color: blocked ? AppPalette.indigo : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reliable AppBar icon button: explicit constraints so it always renders.
/// Plain IconButton inside crowded AppBar Rows can collapse to zero width
/// on some web/desktop layouts; this guarantees a 40x40 hit area.
class _AppBarIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _AppBarIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: AppPalette.indigo, size: 22),
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
  final VoidCallback onSendMoney;
  final VoidCallback onStartVoice;
  const _Composer({
    required this.controller,
    required this.onChanged,
    required this.onSend,
    required this.onAttachImage,
    required this.onSendMoney,
    required this.onStartVoice,
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
            _circleIcon(Icons.payments_outlined, onSendMoney),
            const SizedBox(width: 6),
            _circleIcon(Icons.mic_none_rounded, onStartVoice),
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
                          hintText: 'Type a message...',
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

class _ReplyPreview extends StatelessWidget {
  final Message message;
  final VoidCallback onClose;
  const _ReplyPreview({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final body = message.recalled
        ? '[recalled]'
        : (message.type == 'text' ? message.body : '[${message.type}]');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: AppPalette.divider),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: AppPalette.indigo,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.reply_rounded, size: 16, color: AppPalette.indigo),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Replying',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.indigo,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppPalette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close,
                size: 18, color: AppPalette.textSecondary),
            onPressed: onClose,
          ),
        ],
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
          const Text('Say hello!',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          const Text('Long-press a message to react',
              style: TextStyle(color: AppPalette.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
