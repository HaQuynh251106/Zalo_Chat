import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
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
    final pending = _contacts.where((c) => c['status'] == 'pending').toList();
    final friends = _contacts.where((c) => c['status'] == 'accepted').toList();

    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppPalette.indigo,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              const Text('Danh bạ',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Người bạn đã kết nối và lời mời đang chờ.',
                  style: TextStyle(color: AppPalette.textSecondary)),
              const SizedBox(height: 18),
              _actionTile(
                icon: Icons.person_add_alt_1,
                title: 'Thêm bạn mới',
                subtitle: 'Tìm theo số điện thoại',
                onTap: _sendRequest,
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppPalette.indigo)),
                )
              else ...[
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _sectionLabel('Lời mời (${pending.length})'),
                  const SizedBox(height: 8),
                  ...pending.map((c) => _pendingTile(c)),
                ],
                const SizedBox(height: 18),
                _sectionLabel('Bạn bè (${friends.length})'),
                const SizedBox(height: 8),
                if (friends.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text('Chưa có bạn bè. Hãy thêm người đầu tiên!',
                        style: TextStyle(color: AppPalette.textSecondary)),
                  )
                else
                  ...friends.map((c) => _friendTile(c)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontWeight: FontWeight.w700, color: AppPalette.textPrimary),
      );

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  gradient: AppPalette.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle,
                        style: const TextStyle(
                            color: AppPalette.textSecondary, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppPalette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pendingTile(Map<String, dynamic> c) {
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
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppPalette.indigo),
            onPressed: () => _accept(id),
            child: const Text('Đồng ý'),
          ),
        ],
      ),
    );
  }

  Widget _friendTile(Map<String, dynamic> c) {
    final name = (c['display_name'] ?? '') as String;
    final avatar = (c['avatar_url'] ?? '') as String;
    final userId = c['user_id'] as String;
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
              child: Text(name,
                  style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton(
            icon:
                const Icon(Icons.chat_bubble_outline, color: AppPalette.indigo),
            onPressed: () => _openChat(userId, name, avatar),
          ),
        ],
      ),
    );
  }

  Future<void> _openChat(String peerId, String name, String avatar) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final conv =
          await api.post('/conversations/direct', body: {'peer_id': peerId})
              as Map<String, dynamic>;
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
