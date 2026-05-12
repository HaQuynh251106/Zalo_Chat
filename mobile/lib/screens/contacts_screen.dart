import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';
import '../theme.dart';
import '../widgets/hide_pin_gate.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<Map<String, dynamic>> _contacts = [];
  bool _loading = true;
  String _query = '';
  final Set<String> _online = {};
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _load();
    final ws = context.read<WsClient>();
    _wsSub = ws.events.listen((ev) {
      final t = ev['type'];
      if (t == 'presence.update') {
        final p = ev['payload'] as Map<String, dynamic>;
        final id = p['user_id'] as String?;
        final on = (p['online'] ?? false) as bool;
        if (id == null) return;
        setState(() => on ? _online.add(id) : _online.remove(id));
      } else if (t == 'contact.changed') {
        // request / accept / removed — reload list.
        _load();
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
      final data = await api.get('/contacts') as List<dynamic>;
      setState(() {
        _contacts = data.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendRequest() async {
    final phone = await _askPhone();
    if (phone == null || phone.isEmpty) return;
    if (!mounted) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final user = await api.get('/users/search', query: {'phone': phone})
          as Map<String, dynamic>;
      await api.post('/contacts/request', body: {'user_id': user['id']});
      messenger.showSnackBar(
          const SnackBar(content: Text('Đã gửi lời mời kết bạn')));
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<String?> _askPhone() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Thêm bạn bằng SĐT'),
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
            child: const Text('Gửi lời mời'),
          ),
        ],
      ),
    );
  }

  Future<void> _accept(String userId) async {
    try {
      final api = context.read<ApiClient>();
      await api.post('/contacts/accept', body: {'user_id': userId});
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final incoming = _contacts
        .where((c) =>
            c['status'] == 'pending' && c['direction'] == 'incoming')
        .toList();
    final outgoing = _contacts
        .where((c) =>
            c['status'] == 'pending' && c['direction'] == 'outgoing')
        .toList();
    final friends = _contacts.where((c) => c['status'] == 'accepted').toList();
    final visibleFriends = _query.isEmpty
        ? friends
        : friends
            .where((c) =>
                ((c['display_name'] ?? '') as String)
                    .toLowerCase()
                    .contains(_query.toLowerCase()))
            .toList();

    final onlineFriends =
        friends.where((c) => _online.contains(c['user_id'] as String)).toList();

    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppPalette.indigo,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 120),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: ShaderMask(
                  shaderCallback: (b) =>
                      AppPalette.primaryGradient.createShader(b),
                  child: const Text('Danh bạ',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Text(
                  'Người bạn đã kết nối, đang online và lời mời mới.',
                  style: TextStyle(color: AppPalette.textSecondary),
                ),
              ),

              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: _searchBar(),
              ),

              // 3 quick actions
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                        child: _quickAction(Icons.person_add_alt_1,
                            'Thêm bạn', _sendRequest, AppPalette.indigo)),
                    Expanded(
                        child: _quickAction(Icons.qr_code_scanner,
                            'Quét QR', () {}, AppPalette.violet)),
                    Expanded(
                        child: _quickAction(Icons.share_outlined,
                            'Mời bạn bè', () {}, AppPalette.coral)),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Online friends horizontal row
              if (onlineFriends.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _sectionLabel('Đang hoạt động (${onlineFriends.length})'),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: onlineFriends.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final f = onlineFriends[i];
                      final name = (f['display_name'] ?? '') as String;
                      return GestureDetector(
                        onTap: () => _openChat(
                          f['user_id'] as String,
                          name,
                          (f['avatar_url'] ?? '') as String,
                        ),
                        child: SizedBox(
                          width: 64,
                          child: Column(
                            children: [
                              UserAvatar(
                                name: name,
                                url: (f['avatar_url'] ?? '') as String,
                                size: 54,
                                online: true,
                                showRing: true,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _firstName(name),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
              ],

              // Pending requests
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppPalette.indigo)),
                )
              else ...[
                if (incoming.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _sectionLabel('Lời mời đến (${incoming.length})'),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                        children: incoming.map(_incomingTile).toList()),
                  ),
                  const SizedBox(height: 18),
                ],
                if (outgoing.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: _sectionLabel('Đã gửi (${outgoing.length})'),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                        children: outgoing.map(_outgoingTile).toList()),
                  ),
                  const SizedBox(height: 18),
                ],

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                          child:
                              _sectionLabel('Bạn bè (${friends.length})')),
                      Text(
                        '${onlineFriends.length} đang online',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppPalette.mint,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (friends.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                    child: _emptyHint(
                      'Chưa có bạn bè',
                      'Bấm "Thêm bạn" ở trên để mời người đầu tiên.',
                      Icons.group_add_outlined,
                    ),
                  )
                else if (visibleFriends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Text(
                        'Không tìm thấy bạn nào khớp với tìm kiếm.',
                        style: TextStyle(color: AppPalette.textSecondary)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Column(
                        children: visibleFriends.map(_friendTile).toList()),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _firstName(String full) {
    final parts = full.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? '' : parts.last;
  }

  Widget _searchBar() {
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Tìm bạn bè...',
        prefixIcon:
            const Icon(Icons.search, color: AppPalette.textSecondary),
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

  Widget _quickAction(
      IconData icon, String label, VoidCallback onTap, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(height: 6),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyHint(String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppPalette.indigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppPalette.indigo, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: const TextStyle(
                        color: AppPalette.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontWeight: FontWeight.w700, color: AppPalette.textPrimary),
      );

  Widget _incomingTile(Map<String, dynamic> c) {
    final name = (c['display_name'] ?? '') as String;
    final avatar = (c['avatar_url'] ?? '') as String;
    final id = c['user_id'] as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          UserAvatar(name: name, url: avatar, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Text('Muốn kết bạn với bạn',
                    style: TextStyle(
                        color: AppPalette.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _cancel(id),
            style: TextButton.styleFrom(foregroundColor: AppPalette.textSecondary),
            child: const Text('Từ chối'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppPalette.indigo),
            onPressed: () => _accept(id),
            child: const Text('Đồng ý'),
          ),
        ],
      ),
    );
  }

  Widget _outgoingTile(Map<String, dynamic> c) {
    final name = (c['display_name'] ?? '') as String;
    final avatar = (c['avatar_url'] ?? '') as String;
    final id = c['user_id'] as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.bgLight,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppPalette.divider),
      ),
      child: Row(
        children: [
          UserAvatar(name: name, url: avatar, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const Row(
                  children: [
                    Icon(Icons.schedule,
                        size: 12, color: AppPalette.textSecondary),
                    SizedBox(width: 4),
                    Text('Đang chờ phản hồi',
                        style: TextStyle(
                            color: AppPalette.textSecondary, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
            ),
            onPressed: () => _cancel(id),
            child: const Text('Huỷ'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel(String peerId) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post('/contacts/cancel', body: {'user_id': peerId});
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _friendTile(Map<String, dynamic> c) {
    final name = (c['display_name'] ?? '') as String;
    final avatar = (c['avatar_url'] ?? '') as String;
    final userId = c['user_id'] as String;
    final online = _online.contains(userId);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openChat(userId, name, avatar),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                UserAvatar(
                  name: name,
                  url: avatar,
                  size: 44,
                  online: online,
                  showRing: online,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      Text(
                        online ? 'Đang hoạt động' : 'Ngoại tuyến',
                        style: TextStyle(
                          fontSize: 11,
                          color: online
                              ? AppPalette.mint
                              : AppPalette.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: AppPalette.indigo.withValues(alpha: 0.1),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _openChat(userId, name, avatar),
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.chat_bubble_outline,
                          color: AppPalette.indigo, size: 18),
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

  Future<void> _openChat(String peerId, String name, String avatar) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final conv = await api.post('/conversations/direct',
          body: {'peer_id': peerId}) as Map<String, dynamic>;
      final isHidden = (conv['is_hidden'] ?? false) as bool;
      if (!mounted) return;
      if (!blockIfHidden(context, isHidden: isHidden)) return;
      nav.push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conv['id'] as String,
          title: name,
          peerAvatar: avatar,
          peerId: peerId,
        ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
