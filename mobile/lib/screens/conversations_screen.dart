import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';
import '../theme.dart';
import '../widgets/hide_pin_gate.dart';
import '../widgets/pin_dialog.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';
import 'new_group_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});
  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

enum _ConvFilter { all, unread }

class _ConversationsScreenState extends State<ConversationsScreen> {
  static const _kPinnedKey = 'pinned_conversations_v1';

  List<Conversation> _items = [];
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  _ConvFilter _filter = _ConvFilter.all;
  final Set<String> _onlineUsers = {};
  final Set<String> _pinned = {};
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _loadPinned();
    _load();
    final ws = context.read<WsClient>();
    _wsSub = ws.events.listen((ev) {
      final t = ev['type'];
      if (t == 'message.new' ||
          t == 'message.recalled' ||
          t == 'read.receipt') {
        _load();
      } else if (t == 'presence.update') {
        final p = ev['payload'] as Map<String, dynamic>;
        final id = p['user_id'] as String?;
        final online = (p['online'] ?? false) as bool;
        if (id == null) return;
        setState(() => online ? _onlineUsers.add(id) : _onlineUsers.remove(id));
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadPinned() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_kPinnedKey) ?? [];
    if (!mounted) return;
    setState(() => _pinned
      ..clear()
      ..addAll(list));
  }

  Future<void> _togglePin(String convId) async {
    setState(() {
      if (_pinned.contains(convId)) {
        _pinned.remove(convId);
      } else {
        _pinned.add(convId);
      }
    });
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kPinnedKey, _pinned.toList());
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiClient>();
      // Load conversations + contacts in parallel for the online row.
      final results = await Future.wait([
        api.get('/conversations'),
        api.get('/contacts'),
      ]);
      final convs = results[0] as List<dynamic>;
      final contacts = results[1] as List<dynamic>;
      setState(() {
        _items = convs
            .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
            .toList();
        _friends = contacts
            .cast<Map<String, dynamic>>()
            .where((c) => c['status'] == 'accepted')
            .toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _showNewMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.divider,
                  borderRadius: BorderRadius.circular(8),
                )),
            const SizedBox(height: 8),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                    gradient: AppPalette.primaryGradient,
                    shape: BoxShape.circle),
                child: const Icon(Icons.person, color: Colors.white, size: 18),
              ),
              title: const Text('Trò chuyện 1-1'),
              subtitle: const Text('Tìm theo số điện thoại'),
              onTap: () => Navigator.pop(context, 'direct'),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppPalette.coral,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.group, color: Colors.white, size: 18),
              ),
              title: const Text('Tạo nhóm mới'),
              subtitle:
                  const Text('Mời nhiều người vào cùng một cuộc trò chuyện'),
              onTap: () => Navigator.pop(context, 'group'),
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: AppPalette.violet,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.link, color: Colors.white, size: 18),
              ),
              title: const Text('Tham gia bằng mã'),
              subtitle: const Text('Dán mã mời bạn nhận được'),
              onTap: () => Navigator.pop(context, 'join'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == 'direct') _startNewDirect();
    if (choice == 'group') _createGroup();
    if (choice == 'join') _joinByToken();
  }

  Future<void> _joinByToken() async {
    final token = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Tham gia nhóm'),
          content: TextField(
            controller: c,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'Dán mã mời ở đây',
              prefixIcon: Icon(Icons.link),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Huỷ')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppPalette.indigo),
              onPressed: () =>
                  Navigator.pop(ctx, c.text.trim().toUpperCase()),
              child: const Text('Tham gia'),
            ),
          ],
        );
      },
    );
    if (token == null || token.isEmpty || !mounted) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await api.post('/conversations/join',
          body: {'token': token}) as Map<String, dynamic>;
      final convId = res['conversation_id'] as String;
      messenger.showSnackBar(
        const SnackBar(content: Text('Đã tham gia nhóm')),
      );
      // Refresh list and open the joined conversation.
      await _load();
      final target = _items.firstWhere(
        (c) => c.id == convId,
        orElse: () => Conversation(id: convId, type: 'group', title: 'Nhóm'),
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: target.id,
            title: target.title,
            peerAvatar: target.avatarUrl,
            isGroup: true,
          ),
        ),
      ).then((_) => _load());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _createGroup() async {
    final nav = Navigator.of(context);
    final conv = await nav.push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (_) => const NewGroupScreen()),
    );
    if (conv == null) return;
    if (!mounted) return;
    nav
        .push(MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conv['id'] as String,
            title: (conv['title'] ?? 'Nhóm') as String,
            peerAvatar: '',
            isGroup: true,
          ),
        ))
        .then((_) => _load());
  }

  Future<void> _startNewDirect() async {
    final phone = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController();
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Bắt đầu cuộc trò chuyện'),
          content: TextField(
            controller: c,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              hintText: 'Số điện thoại',
              prefixIcon: Icon(Icons.phone_iphone),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Huỷ')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Tìm'),
            ),
          ],
        );
      },
    );
    if (phone == null || phone.isEmpty) return;
    if (!mounted) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final user = await api.get('/users/search', query: {'phone': phone})
          as Map<String, dynamic>;
      final conv =
          await api.post('/conversations/direct', body: {'peer_id': user['id']})
              as Map<String, dynamic>;
      final isHidden = (conv['is_hidden'] ?? false) as bool;
      if (!mounted) return;
      if (!blockIfHidden(context, isHidden: isHidden)) return;
      navigator
          .push(
            MaterialPageRoute(
              builder: (_) => ChatScreen(
                conversationId: conv['id'] as String,
                title: (user['display_name'] ?? user['phone']) as String,
                peerAvatar: (user['avatar_url'] ?? '') as String,
                peerId: user['id'] as String,
              ),
            ),
          )
          .then((_) => _load());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  List<Conversation> get _visible {
    Iterable<Conversation> list = _items;
    if (_filter == _ConvFilter.unread) {
      list = list.where((c) => c.unreadCount > 0);
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list.where((c) =>
          c.title.toLowerCase().contains(q) ||
          c.lastMessagePreview.toLowerCase().contains(q));
    }
    final all = list.toList();
    // Pinned to top, otherwise preserve server order (last_message_at DESC).
    all.sort((a, b) {
      final ap = _pinned.contains(a.id) ? 0 : 1;
      final bp = _pinned.contains(b.id) ? 0 : 1;
      if (ap != bp) return ap - bp;
      return 0;
    });
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      body: RefreshIndicator(
        color: AppPalette.indigo,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
                child: _Header(name: auth.user?.displayName ?? '')),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _searchBar(),
              ),
            ),
            SliverToBoxAdapter(child: _friendsStrip()),
            SliverToBoxAdapter(child: _filterChips()),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                    child: CircularProgressIndicator(color: AppPalette.indigo)),
              )
            else if (_error != null)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text(_error!)),
              )
            else if (_visible.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else
              SliverList.separated(
                itemCount: _visible.length,
                separatorBuilder: (_, __) => const SizedBox(height: 2),
                itemBuilder: (_, i) => _convTile(_visible[i]),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewMenu,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Tin mới'),
      ),
    );
  }

  Widget _filterChips() {
    final unreadCount = _items.where((c) => c.unreadCount > 0).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          _filterChip(
            label: 'Tất cả',
            count: _items.length,
            selected: _filter == _ConvFilter.all,
            onTap: () => setState(() => _filter = _ConvFilter.all),
          ),
          const SizedBox(width: 8),
          _filterChip(
            label: 'Chưa đọc',
            count: unreadCount,
            selected: _filter == _ConvFilter.unread,
            onTap: () => setState(() => _filter = _ConvFilter.unread),
          ),
          const Spacer(),
          if (_pinned.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppPalette.coral.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.push_pin,
                      size: 12, color: AppPalette.coral),
                  const SizedBox(width: 4),
                  Text(
                    '${_pinned.length} đã ghim',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppPalette.coral,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            gradient: selected ? AppPalette.primaryGradient : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: selected ? Colors.white : AppPalette.textPrimary,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.25)
                        : AppPalette.indigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: selected ? Colors.white : AppPalette.indigo,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Horizontal scrollable strip of friends, online ones first.
  /// Tap a friend -> open direct chat. Skips own user.
  Widget _friendsStrip() {
    if (_loading || _friends.isEmpty) return const SizedBox.shrink();
    // Sort: online first, then by name.
    final sorted = List<Map<String, dynamic>>.from(_friends)
      ..sort((a, b) {
        final aOn = _onlineUsers.contains(a['user_id'] as String) ? 0 : 1;
        final bOn = _onlineUsers.contains(b['user_id'] as String) ? 0 : 1;
        if (aOn != bOn) return aOn - bOn;
        return ((a['display_name'] ?? '') as String)
            .compareTo((b['display_name'] ?? '') as String);
      });

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Text('Bạn bè',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary)),
                const SizedBox(width: 8),
                if (_onlineUsers.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppPalette.mint.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${sorted.where((f) => _onlineUsers.contains(f['user_id'])).length} online',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.mint,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final f = sorted[i];
                final name = (f['display_name'] ?? '') as String;
                final avatar = (f['avatar_url'] ?? '') as String;
                final userId = f['user_id'] as String;
                final online = _onlineUsers.contains(userId);
                return GestureDetector(
                  onTap: () => _openDirectByUser(userId, name, avatar),
                  child: SizedBox(
                    width: 64,
                    child: Column(
                      children: [
                        UserAvatar(
                          name: name,
                          url: avatar,
                          size: 54,
                          online: online,
                          showRing: online,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _firstName(name),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _firstName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.last;
  }

  Future<void> _openDirectByUser(
      String peerId, String name, String avatar) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final conv = await api.post('/conversations/direct',
          body: {'peer_id': peerId}) as Map<String, dynamic>;
      final isHidden = (conv['is_hidden'] ?? false) as bool;
      if (!mounted) return;
      if (!blockIfHidden(context, isHidden: isHidden)) return;
      nav
          .push(MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: conv['id'] as String,
              title: name,
              peerAvatar: avatar,
              peerId: peerId,
            ),
          ))
          .then((_) => _load());
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _searchBar() {
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Tìm tin nhắn, bạn bè...',
        prefixIcon: const Icon(Icons.search, color: AppPalette.textSecondary),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _convTile(Conversation c) {
    final peerId = _peerIdOf(c);
    final online = peerId != null && _onlineUsers.contains(peerId);
    final pinned = _pinned.contains(c.id);
    return Material(
      color: pinned ? AppPalette.coral.withValues(alpha: 0.04) : Colors.white,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: c.id,
              title: c.title,
              peerAvatar: c.avatarUrl,
              peerId: peerId,
              isGroup: c.type == 'group',
            ),
          ),
        ).then((_) => _load()),
        onLongPress: () => _showConvActions(c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              UserAvatar(
                name: c.title,
                url: c.avatarUrl,
                size: 50,
                online: online,
                showRing: online,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (pinned) ...[
                          const Icon(Icons.push_pin,
                              size: 13, color: AppPalette.coral),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (c.lastMessageAt != null)
                          Text(
                            _formatTime(c.lastMessageAt!),
                            style: TextStyle(
                              fontSize: 11,
                              color: c.unreadCount > 0
                                  ? AppPalette.indigo
                                  : AppPalette.textSecondary,
                              fontWeight: c.unreadCount > 0
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.lastMessagePreview.isEmpty
                                ? 'Bắt đầu trò chuyện'
                                : c.lastMessagePreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: c.unreadCount > 0
                                  ? AppPalette.textPrimary
                                  : AppPalette.textSecondary,
                              fontWeight: c.unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (c.unreadCount > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: const BoxDecoration(
                              gradient: AppPalette.primaryGradient,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(20)),
                            ),
                            child: Text(
                              c.unreadCount > 99 ? '99+' : '${c.unreadCount}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showConvActions(Conversation c) async {
    final pinned = _pinned.contains(c.id);
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppPalette.divider,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: Icon(
                pinned ? Icons.push_pin_outlined : Icons.push_pin,
                color: AppPalette.coral,
              ),
              title: Text(pinned ? 'Bỏ ghim' : 'Ghim lên đầu'),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.lock_outline, color: AppPalette.violet),
              title: const Text('Ẩn cuộc trò chuyện'),
              subtitle: const Text(
                  'Chỉ xem được khi nhập mã PIN'),
              onTap: () => Navigator.pop(context, 'hide'),
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: AppPalette.indigo),
              title: const Text('Sao chép ID cuộc trò chuyện'),
              onTap: () => Navigator.pop(context, 'copy_id'),
            ),
            ListTile(
              leading: const Icon(Icons.close, color: AppPalette.textSecondary),
              title: const Text('Huỷ'),
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == 'pin') {
      await _togglePin(c.id);
    } else if (action == 'hide') {
      await _hideConversation(c);
    } else if (action == 'copy_id') {
      await Clipboard.setData(ClipboardData(text: c.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã sao chép ID')),
      );
    }
  }

  Future<void> _hideConversation(Conversation c) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    // First check if PIN is set; if not, prompt setup.
    try {
      final st = await api.get('/me/hide-pin') as Map<String, dynamic>;
      final hasPin = (st['has_pin'] ?? false) as bool;
      if (!hasPin) {
        if (!mounted) return;
        final created = await PinDialog.show(
          context,
          mode: PinDialogMode.setup,
          title: 'Thiết lập mã PIN',
          subtitle:
              'Cần PIN để ẩn cuộc trò chuyện và xem lại sau này.',
        );
        if (created == null || !mounted) return;
        await api.post('/me/hide-pin', body: {'new_pin': created['pin']});
        // Now hide directly with the new pin
        await api.post('/conversations/${c.id}/hide',
            body: {'pin': created['pin']});
        messenger.showSnackBar(
          const SnackBar(content: Text('Đã thiết lập PIN và ẩn cuộc trò chuyện')),
        );
        _load();
        return;
      }
      if (!mounted) return;
      final res = await PinDialog.show(
        context,
        mode: PinDialogMode.verify,
        title: 'Nhập mã PIN để ẩn',
      );
      if (res == null || !mounted) return;
      await api
          .post('/conversations/${c.id}/hide', body: {'pin': res['pin']});
      messenger.showSnackBar(
        SnackBar(content: Text('Đã ẩn ${c.title}')),
      );
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_friendlyPinError(e))));
    }
  }

  String _friendlyPinError(Object e) {
    final s = e.toString();
    if (s.contains('wrong pin')) return 'Mã PIN không đúng';
    if (s.contains('pin not set')) return 'Bạn chưa đặt PIN';
    return s;
  }

  String? _peerIdOf(Conversation c) {
    if (c.type != 'direct') return null;
    final me = context.read<AuthProvider>().user?.id;
    final ids = c.memberIds;
    if (ids == null || me == null) return null;
    return ids.firstWhere((id) => id != me, orElse: () => '');
  }

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final l = t.toLocal();
    if (l.year == now.year && l.month == now.month && l.day == now.day) {
      return DateFormat('HH:mm').format(l);
    }
    final diff = now.difference(l).inDays;
    if (diff < 7) return DateFormat('EEE').format(l);
    return DateFormat('dd/MM').format(l);
  }
}

class _Header extends StatelessWidget {
  final String name;
  const _Header({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: const TextStyle(
                      fontSize: 13, color: AppPalette.textSecondary),
                ),
                const SizedBox(height: 2),
                ShaderMask(
                  shaderCallback: (b) =>
                      AppPalette.primaryGradient.createShader(b),
                  child: Text(
                    name.isNotEmpty ? name : 'Bạn',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: const Icon(Icons.notifications_none_rounded,
                color: AppPalette.indigo),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Chào buổi sáng,';
    if (h < 14) return 'Chào buổi trưa,';
    if (h < 18) return 'Chào buổi chiều,';
    return 'Chào buổi tối,';
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                gradient: AppPalette.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.forum_outlined,
                  color: Colors.white, size: 40),
            ),
            const SizedBox(height: 18),
            const Text(
              'Chưa có cuộc trò chuyện',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Nhấn “Tin mới” để bắt đầu cuộc trò chuyện đầu tiên của bạn.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppPalette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
