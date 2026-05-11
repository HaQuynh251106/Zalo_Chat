import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';
import 'new_group_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});
  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  List<Conversation> _items = [];
  bool _loading = true;
  String? _error;
  String _query = '';
  final Set<String> _onlineUsers = {};
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
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

  Future<void> _load() async {
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/conversations') as List<dynamic>;
      setState(() {
        _items = data
            .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
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
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (choice == 'direct') _startNewDirect();
    if (choice == 'group') _createGroup();
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
    if (_query.isEmpty) return _items;
    final q = _query.toLowerCase();
    return _items
        .where((c) =>
            c.title.toLowerCase().contains(q) ||
            c.lastMessagePreview.toLowerCase().contains(q))
        .toList();
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
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              conversationId: c.id,
              title: c.title,
              peerAvatar: c.avatarUrl,
              peerId: peerId,
            ),
          ),
        ).then((_) => _load()),
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
