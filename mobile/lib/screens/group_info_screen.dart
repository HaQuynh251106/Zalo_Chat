import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';

class GroupInfoScreen extends StatefulWidget {
  final String conversationId;
  final String title;
  final String avatarUrl;
  const GroupInfoScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.avatarUrl = '',
  });

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  List<Map<String, dynamic>> _members = [];
  bool _loading = true;
  bool _leaving = false;
  bool _uploadingAvatar = false;
  String _currentTitle = '';
  String _currentAvatar = '';
  String _myId = '';
  String _myRole = 'member';
  StreamSubscription? _wsSub;

  bool get _canManage => _myRole == 'owner' || _myRole == 'admin';

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title;
    _currentAvatar = widget.avatarUrl;
    _myId = context.read<AuthProvider>().user?.id ?? '';
    _load();
    final ws = context.read<WsClient>();
    _wsSub = ws.events.listen((ev) {
      final t = ev['type'];
      final p = ev['payload'];
      if (p is! Map<String, dynamic>) return;
      if (p['conversation_id'] != widget.conversationId) return;
      if (t == 'conversation.members_added' ||
          t == 'conversation.member_kicked' ||
          t == 'conversation.member_left') {
        _load();
      } else if (t == 'conversation.updated') {
        setState(() {
          _currentTitle = (p['title'] ?? _currentTitle) as String;
          _currentAvatar = (p['avatar_url'] ?? _currentAvatar) as String;
        });
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
      final data =
          await api.get('/conversations/${widget.conversationId}/members')
              as List<dynamic>;
      final list = data.cast<Map<String, dynamic>>();
      String myRole = 'member';
      for (final m in list) {
        if (m['user_id'] == _myId) {
          myRole = (m['role'] ?? 'member') as String;
          break;
        }
      }
      setState(() {
        _members = list;
        _myRole = myRole;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _changeAvatar() async {
    if (!_canManage) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 800);
      if (picked == null) return;
      setState(() => _uploadingAvatar = true);
      final bytes = await picked.readAsBytes();
      final res = await api.upload(bytes: bytes, filename: picked.name);
      final rawUrl = (res['url'] ?? res['path']) as String;
      final fullUrl = rawUrl.startsWith('http')
          ? rawUrl
          : '${AppConfig.apiBase}$rawUrl';
      await api.patch('/conversations/${widget.conversationId}',
          body: {'avatar_url': fullUrl});
      // WS will broadcast and update; also set local immediately.
      setState(() => _currentAvatar = fullUrl);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _showInviteLink() async {
    if (!_canManage) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    String? token;
    try {
      final data = await api
          .post('/conversations/${widget.conversationId}/invite') as Map<String, dynamic>;
      token = data['token'] as String;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppPalette.divider,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Liên kết mời',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text(
                'Chia sẻ mã này; bạn bè dán vào "Tham gia bằng mã" để vào nhóm.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppPalette.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                decoration: BoxDecoration(
                  color: AppPalette.bgLight,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppPalette.indigo.withValues(alpha: 0.4)),
                ),
                child: Text(
                  token!,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4,
                    color: AppPalette.indigo,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.indigo,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  icon: const Icon(Icons.copy),
                  label: const Text('Sao chép mã'),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: token!));
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Đã sao chép mã mời')),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename() async {
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: _currentTitle);
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Đổi tên nhóm'),
          content: TextField(
            controller: c,
            autofocus: true,
            decoration: const InputDecoration(hintText: 'Tên mới'),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Huỷ')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppPalette.indigo),
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );
    if (newTitle == null || newTitle.isEmpty || newTitle == _currentTitle) {
      return;
    }
    if (!mounted) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.patch('/conversations/${widget.conversationId}',
          body: {'title': newTitle});
      // local update; WS broadcast will also confirm
      setState(() => _currentTitle = newTitle);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _addMembers() async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    // Load contacts
    List<Map<String, dynamic>> friends = [];
    try {
      final data = await api.get('/contacts') as List<dynamic>;
      friends = data
          .cast<Map<String, dynamic>>()
          .where((c) => c['status'] == 'accepted')
          .toList();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    final existing = _members.map((m) => m['user_id'] as String).toSet();
    final candidates =
        friends.where((f) => !existing.contains(f['user_id'])).toList();

    if (candidates.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Tất cả bạn bè đã có trong nhóm')));
      return;
    }

    if (!mounted) return;
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMembersSheet(candidates: candidates),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    try {
      await api.post('/conversations/${widget.conversationId}/members',
          body: {'user_ids': selected.toList()});
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _kick(Map<String, dynamic> m) async {
    final name = (m['display_name'] ?? '') as String;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Xoá khỏi nhóm?'),
        content: Text('$name sẽ không nhận tin nhắn mới từ nhóm này.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.delete(
          '/conversations/${widget.conversationId}/members/${m['user_id']}');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Rời nhóm?'),
        content: const Text(
            'Bạn sẽ không nhận tin nhắn mới từ nhóm này nữa. Có thể quay lại bằng lời mời mới.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Huỷ')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rời nhóm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _leaving = true);
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await api.post('/conversations/${widget.conversationId}/leave');
      messenger.showSnackBar(const SnackBar(content: Text('Đã rời nhóm')));
      nav.pop();
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      if (mounted) setState(() => _leaving = false);
    }
  }

  bool _canKick(Map<String, dynamic> m) {
    if (!_canManage) return false;
    if (m['user_id'] == _myId) return false; // use leave
    final role = (m['role'] ?? 'member') as String;
    if (role == 'owner') return false;
    if (_myRole == 'admin' && role == 'admin') return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Thông tin nhóm'),
        actions: [
          if (_canManage)
            IconButton(
              tooltip: 'Đổi tên',
              onPressed: _rename,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppPalette.indigo))
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 16, 0, 80),
              children: [
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _canManage ? _changeAvatar : null,
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: AppPalette.primaryGradient,
                              ),
                              child: UserAvatar(
                                name: _currentTitle,
                                url: _currentAvatar,
                                size: 92,
                              ),
                            ),
                            if (_canManage)
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: const BoxDecoration(
                                    gradient: AppPalette.primaryGradient,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: _uploadingAvatar
                                      ? const SizedBox(
                                          width: 12,
                                          height: 12,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.camera_alt,
                                          color: Colors.white, size: 14),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(_currentTitle,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        '${_members.length} thành viên',
                        style: const TextStyle(
                            color: AppPalette.textSecondary, fontSize: 13),
                      ),
                      if (_canManage) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _showInviteLink,
                          icon: const Icon(Icons.link, color: AppPalette.indigo),
                          label: const Text('Liên kết mời'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppPalette.indigo,
                            side: const BorderSide(color: AppPalette.indigo),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Thành viên (${_members.length})',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppPalette.textPrimary),
                        ),
                      ),
                      if (_canManage)
                        TextButton.icon(
                          onPressed: _addMembers,
                          icon: const Icon(Icons.person_add_alt_1, size: 18),
                          label: const Text('Thêm'),
                          style: TextButton.styleFrom(
                              foregroundColor: AppPalette.indigo),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    children: _members.map((m) {
                      final name = (m['display_name'] ?? '') as String;
                      final role = (m['role'] ?? 'member') as String;
                      final joinedAt =
                          DateTime.parse(m['joined_at'] as String).toLocal();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            UserAvatar(
                              name: name,
                              url: (m['avatar_url'] ?? '') as String,
                              size: 42,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          name +
                                              (m['user_id'] == _myId
                                                  ? ' (bạn)'
                                                  : ''),
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14),
                                        ),
                                      ),
                                      if (role != 'member') ...[
                                        const SizedBox(width: 6),
                                        _roleBadge(role),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    'Tham gia ${df.format(joinedAt)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppPalette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_canKick(m))
                              IconButton(
                                tooltip: 'Xoá khỏi nhóm',
                                icon: const Icon(Icons.person_remove,
                                    color: Colors.red, size: 20),
                                onPressed: () => _kick(m),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: _leaving ? null : _leave,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.exit_to_app,
                                  color: Colors.red, size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text('Rời nhóm',
                                  style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600)),
                            ),
                            if (_leaving)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.red),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _roleBadge(String role) {
    final isOwner = role == 'owner';
    final label = isOwner ? 'Chủ nhóm' : 'Quản trị';
    final color = isOwner ? AppPalette.coral : AppPalette.indigo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _AddMembersSheet extends StatefulWidget {
  final List<Map<String, dynamic>> candidates;
  const _AddMembersSheet({required this.candidates});

  @override
  State<_AddMembersSheet> createState() => _AddMembersSheetState();
}

class _AddMembersSheetState extends State<_AddMembersSheet> {
  final Set<String> _selected = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = _query.isEmpty
        ? widget.candidates
        : widget.candidates
            .where((c) =>
                ((c['display_name'] ?? '') as String)
                    .toLowerCase()
                    .contains(_query.toLowerCase()))
            .toList();
    return Container(
      height: MediaQuery.of(context).size.height * 0.72,
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
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Thêm thành viên',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                Text(
                  'Đã chọn ${_selected.length}',
                  style: const TextStyle(
                      color: AppPalette.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Tìm bạn bè...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppPalette.bgLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text('Không có bạn bè phù hợp',
                        style: TextStyle(color: AppPalette.textSecondary)),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final f = visible[i];
                      final id = f['user_id'] as String;
                      final name = (f['display_name'] ?? '') as String;
                      final picked = _selected.contains(id);
                      return CheckboxListTile(
                        value: picked,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(id);
                          } else {
                            _selected.remove(id);
                          }
                        }),
                        title: Text(name,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                        secondary: UserAvatar(
                          name: name,
                          url: (f['avatar_url'] ?? '') as String,
                          size: 40,
                        ),
                        activeColor: AppPalette.indigo,
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.indigo,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected),
                  child: Text(
                    _selected.isEmpty
                        ? 'Chọn ít nhất 1 người'
                        : 'Thêm ${_selected.length} thành viên',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
