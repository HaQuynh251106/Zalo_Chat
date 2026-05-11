import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});
  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final _title = TextEditingController();
  final Set<String> _selected = {};
  List<Map<String, dynamic>> _friends = [];
  bool _loading = true;
  bool _creating = false;

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
        _friends = data
            .cast<Map<String, dynamic>>()
            .where((c) => c['status'] == 'accepted')
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    if (_title.text.trim().isEmpty || _selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Nhập tên nhóm và chọn ít nhất 1 thành viên')),
      );
      return;
    }
    setState(() => _creating = true);
    final api = context.read<ApiClient>();
    final nav = Navigator.of(context);
    try {
      final conv = await api.post('/conversations/group', body: {
        'title': _title.text.trim(),
        'member_ids': _selected.toList(),
      }) as Map<String, dynamic>;
      nav.pop(conv);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Nhóm mới'),
        actions: [
          TextButton(
            onPressed: _creating ? null : _create,
            child: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Tạo'),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _title,
              decoration: const InputDecoration(
                labelText: 'Tên nhóm',
                prefixIcon: Icon(Icons.group),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Text('Chọn thành viên',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary)),
                const Spacer(),
                Text('Đã chọn: ${_selected.length}',
                    style: const TextStyle(
                        color: AppPalette.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppPalette.indigo))
                : _friends.isEmpty
                    ? const Center(
                        child: Text('Chưa có bạn nào để thêm vào nhóm',
                            style: TextStyle(color: AppPalette.textSecondary)),
                      )
                    : ListView.builder(
                        itemCount: _friends.length,
                        itemBuilder: (_, i) {
                          final f = _friends[i];
                          final id = f['user_id'] as String;
                          final name = (f['display_name'] ?? '') as String;
                          final picked = _selected.contains(id);
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: CheckboxListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                              value: picked,
                              onChanged: (v) => setState(() {
                                if (v == true) {
                                  _selected.add(id);
                                } else {
                                  _selected.remove(id);
                                }
                              }),
                              title: Text(name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              secondary: UserAvatar(
                                  name: name,
                                  url: (f['avatar_url'] ?? '') as String,
                                  size: 40),
                              activeColor: AppPalette.indigo,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
