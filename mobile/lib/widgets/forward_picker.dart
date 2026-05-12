import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../services/api_client.dart';
import '../theme.dart';
import 'user_avatar.dart';

/// Bottom sheet that lists the user's conversations so they can pick
/// a destination to forward a message to.
/// Returns the chosen Conversation, or null if cancelled.
class ForwardPicker extends StatefulWidget {
  final String excludeConversationId;
  const ForwardPicker({super.key, required this.excludeConversationId});

  static Future<Conversation?> show(
      BuildContext context, {
      required String excludeConversationId,
      }) {
    return showModalBottomSheet<Conversation>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ForwardPicker(excludeConversationId: excludeConversationId),
    );
  }

  @override
  State<ForwardPicker> createState() => _ForwardPickerState();
}

class _ForwardPickerState extends State<ForwardPicker> {
  List<Conversation> _items = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/conversations') as List<dynamic>;
      setState(() {
        _items = data
            .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
            .where((c) => c.id != widget.excludeConversationId)
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _query.isEmpty
        ? _items
        : _items
            .where((c) =>
                c.title.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppPalette.divider,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Chuyển tiếp tới',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Tìm cuộc trò chuyện...',
                  prefixIcon:
                      const Icon(Icons.search, color: AppPalette.textSecondary),
                  filled: true,
                  fillColor: AppPalette.bgLight,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
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
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppPalette.indigo))
                  : visible.isEmpty
                      ? const Center(
                          child: Text('Không có cuộc trò chuyện nào',
                              style:
                                  TextStyle(color: AppPalette.textSecondary)))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (_, i) {
                            final c = visible[i];
                            return ListTile(
                              leading: UserAvatar(
                                  name: c.title, url: c.avatarUrl, size: 44),
                              title: Text(c.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                c.type == 'group' ? 'Nhóm' : 'Cá nhân',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppPalette.textSecondary),
                              ),
                              onTap: () => Navigator.pop(context, c),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
