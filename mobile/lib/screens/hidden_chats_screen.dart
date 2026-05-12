import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';

/// Screen showing the user's hidden conversations.
/// Caller must have already verified the user's hide-PIN and pass it in.
class HiddenChatsScreen extends StatefulWidget {
  final String pin;
  const HiddenChatsScreen({super.key, required this.pin});

  @override
  State<HiddenChatsScreen> createState() => _HiddenChatsScreenState();
}

class _HiddenChatsScreenState extends State<HiddenChatsScreen> {
  List<Conversation> _items = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  List<Conversation> get _visible {
    if (_query.trim().isEmpty) return _items;
    final q = _query.toLowerCase();
    return _items
        .where((c) =>
            c.title.toLowerCase().contains(q) ||
            c.lastMessagePreview.toLowerCase().contains(q))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = context.read<ApiClient>();
      final data =
          await api.post('/conversations/hidden', body: {'pin': widget.pin})
              as List<dynamic>;
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

  Future<void> _unhide(Conversation c) async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post('/conversations/${c.id}/unhide');
      messenger.showSnackBar(SnackBar(content: Text('Đã bỏ ẩn ${c.title}')));
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('HH:mm dd/MM');
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.lock, size: 18, color: AppPalette.indigo),
            SizedBox(width: 8),
            Text('Trò chuyện ẩn'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppPalette.indigo))
          : _error != null
              ? Center(child: Text(_error!))
              : Column(
                  children: [
                    if (_items.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          decoration: InputDecoration(
                            hintText: 'Tìm theo tên...',
                            prefixIcon:
                                const Icon(Icons.search, color: AppPalette.indigo),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    Expanded(
                      child: _items.isEmpty
                          ? const _EmptyHidden()
                          : _visible.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Text(
                                      'Không có kết quả khớp "$_query"',
                                      style: const TextStyle(
                                          color: AppPalette.textSecondary),
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  color: AppPalette.indigo,
                                  onRefresh: _load,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.fromLTRB(
                                        12, 4, 12, 60),
                                    itemCount: _visible.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 6),
                                    itemBuilder: (_, i) {
                                      final c = _visible[i];
                          return Material(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ChatScreen(
                                    conversationId: c.id,
                                    title: c.title,
                                    peerAvatar: c.avatarUrl,
                                    isGroup: c.type == 'group',
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(
                                  children: [
                                    UserAvatar(
                                        name: c.title,
                                        url: c.avatarUrl,
                                        size: 46),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(c.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 14)),
                                          const SizedBox(height: 2),
                                          Text(
                                            c.lastMessagePreview.isEmpty
                                                ? '—'
                                                : c.lastMessagePreview,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: AppPalette
                                                    .textSecondary),
                                          ),
                                          if (c.lastMessageAt != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              df.format(
                                                  c.lastMessageAt!.toLocal()),
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: AppPalette
                                                      .textSecondary),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _unhide(c),
                                      child: const Text('Bỏ ẩn'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                                  ),
                                ),
                    ),
                  ],
                ),
    );
  }
}

class _EmptyHidden extends StatelessWidget {
  const _EmptyHidden();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppPalette.indigo.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_outline,
                  color: AppPalette.indigo, size: 36),
            ),
            const SizedBox(height: 14),
            const Text('Chưa có cuộc trò chuyện nào được ẩn',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text(
              'Giữ vào một cuộc trò chuyện ở tab Tin nhắn rồi chọn "Ẩn cuộc trò chuyện".',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppPalette.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
