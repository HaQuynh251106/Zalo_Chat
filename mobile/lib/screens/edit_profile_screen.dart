import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _name;
  late final TextEditingController _bio;
  String _avatarUrl = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthProvider>().user;
    _name = TextEditingController(text: u?.displayName ?? '');
    _bio = TextEditingController(text: u?.bio ?? '');
    _avatarUrl = u?.avatarUrl ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final messenger = ScaffoldMessenger.of(context);
    final api = context.read<ApiClient>();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 80, maxWidth: 1024);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final res = await api.upload(bytes: bytes, filename: picked.name);
      setState(() => _avatarUrl =
          _absUrl(res['url'] as String? ?? (res['path'] as String? ?? '')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final api = context.read<ApiClient>();
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      await api.put('/me', body: {
        'display_name': _name.text.trim(),
        'avatar_url': _avatarUrl,
        'bio': _bio.text.trim(),
      });
      await auth.refreshMe();
      nav.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _absUrl(String pathOrUrl) {
    if (pathOrUrl.startsWith('http')) return pathOrUrl;
    return _apiBase() + pathOrUrl;
  }

  String _apiBase() {
    // We rely on AppConfig at runtime via ApiClient but to display image directly
    // we resolve relative paths to the same host. Import lazily to avoid circular.
    // Simpler: rely on the same hostname embedded in the upload `url` field —
    // backend returns absolute if PUBLIC_BASE_URL set; otherwise we leave as path.
    return const String.fromEnvironment('API_BASE',
        defaultValue: 'http://localhost:8080');
  }

  @override
  Widget build(BuildContext context) {
    final me = context.watch<AuthProvider>().user;
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Chỉnh sửa hồ sơ'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      UserAvatar(
                        name: me?.displayName ?? '?',
                        url: _avatarUrl,
                        size: 110,
                        showRing: true,
                      ),
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: const BoxDecoration(
                          gradient: AppPalette.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.camera_alt,
                            color: Colors.white, size: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(me?.phone ?? '',
                    style: const TextStyle(
                        color: AppPalette.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: 'Tên hiển thị',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bio,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Giới thiệu',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppPalette.indigo,
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Lưu thay đổi'),
          ),
        ],
      ),
    );
  }
}
