import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config.dart';
import '../models/post.dart';
import '../providers/auth_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/comments_sheet.dart';
import '../widgets/user_avatar.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});
  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  List<FeedPost> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiClient>();
      final data = await api.get('/feed') as List<dynamic>;
      setState(() {
        _posts = data
            .map((e) => FeedPost.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _compose() async {
    final result = await showModalBottomSheet<_ComposeResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ComposeSheet(),
    );
    if (result == null || (result.body.trim().isEmpty && result.media.isEmpty))
      return;
    if (!mounted) return;
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await api.post('/feed', body: {
        'body': result.body,
        'visibility': result.visibility,
        'media': result.media,
      });
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _openComments(FeedPost p) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentsSheet(postId: p.id),
    );
    _load();
  }

  Future<void> _react(FeedPost p) async {
    final reaction = p.myReaction == 'love' ? '' : 'love';
    try {
      final api = context.read<ApiClient>();
      await api.post('/feed/${p.id}/react', body: {'reaction': reaction});
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppPalette.indigo,
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ShaderMask(
                              shaderCallback: (b) =>
                                  AppPalette.primaryGradient.createShader(b),
                              child: const Text(
                                'Nhật ký',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const Text(
                              'Khoảnh khắc của bạn bè quanh bạn.',
                              style: TextStyle(color: AppPalette.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _composerCard()),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppPalette.indigo)),
                )
              else if (_posts.isEmpty)
                const SliverToBoxAdapter(child: _EmptyFeed())
              else
                SliverList.separated(
                  itemCount: _posts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (_, i) => _postCard(_posts[i]),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composerCard() {
    final me = context.watch<AuthProvider>().user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: _compose,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                UserAvatar(
                    name: me?.displayName ?? '?', url: me?.avatarUrl, size: 40),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Hôm nay bạn nghĩ gì?',
                    style: TextStyle(color: AppPalette.textSecondary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    gradient: AppPalette.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit, color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _postCard(FeedPost p) {
    final df = DateFormat('dd/MM • HH:mm');
    final liked = p.myReaction == 'love';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03), blurRadius: 10)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  UserAvatar(name: p.authorName, url: p.authorAvatar, size: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.authorName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        Row(
                          children: [
                            Text(
                              df.format(p.createdAt.toLocal()),
                              style: const TextStyle(
                                  color: AppPalette.textSecondary,
                                  fontSize: 11),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.circle,
                                size: 3, color: AppPalette.textSecondary),
                            const SizedBox(width: 6),
                            Icon(_visIcon(p.visibility),
                                size: 12, color: AppPalette.textSecondary),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.more_horiz, color: AppPalette.textSecondary),
                ],
              ),
            ),
            if (p.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Text(p.body,
                    style: const TextStyle(fontSize: 14, height: 1.4)),
              ),
            if (p.media.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(0),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.network(
                    p.media.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: AppPalette.divider),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: () => _react(p),
                    icon: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      color:
                          liked ? AppPalette.coral : AppPalette.textSecondary,
                    ),
                    label: Text(
                      '${p.reactionCount}',
                      style: TextStyle(
                          color: liked
                              ? AppPalette.coral
                              : AppPalette.textSecondary),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openComments(p),
                    icon: const Icon(Icons.mode_comment_outlined,
                        color: AppPalette.textSecondary),
                    label: Text('${p.commentCount}',
                        style:
                            const TextStyle(color: AppPalette.textSecondary)),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.ios_share,
                        color: AppPalette.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _visIcon(String v) => switch (v) {
        'public' => Icons.public,
        'private' => Icons.lock_outline,
        _ => Icons.people_outline,
      };
}

class _ComposeResult {
  final String body;
  final String visibility;
  final List<String> media;
  _ComposeResult(
      {required this.body, required this.visibility, required this.media});
}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet();
  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _c = TextEditingController();
  final List<String> _media = [];
  String _visibility = 'friends';
  bool _uploading = false;

  Future<void> _pickImage() async {
    final api = context.read<ApiClient>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _uploading = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final res = await api.upload(bytes: bytes, filename: picked.name);
      final raw = (res['url'] ?? res['path']) as String;
      final url = raw.startsWith('http') ? raw : '${AppConfig.apiBase}$raw';
      setState(() => _media.add(url));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: padding),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppPalette.divider,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const Text('Tạo bài viết',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              autofocus: true,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: 'Hôm nay có điều gì thú vị?',
              ),
            ),
            if (_media.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _media.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(_media[i],
                            width: 80, height: 80, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: GestureDetector(
                          onTap: () => setState(() => _media.removeAt(i)),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _uploading ? null : _pickImage,
                  icon: _uploading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.photo_outlined,
                          color: AppPalette.indigo),
                  label: const Text('Ảnh',
                      style: TextStyle(color: AppPalette.indigo)),
                ),
                const Spacer(),
                DropdownButton<String>(
                  value: _visibility,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'public', child: Text('Công khai')),
                    DropdownMenuItem(value: 'friends', child: Text('Bạn bè')),
                    DropdownMenuItem(
                        value: 'private', child: Text('Chỉ mình tôi')),
                  ],
                  onChanged: (v) =>
                      v == null ? null : setState(() => _visibility = v),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Huỷ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.indigo),
                    onPressed: () => Navigator.pop(
                      context,
                      _ComposeResult(
                          body: _c.text,
                          visibility: _visibility,
                          media: List.of(_media)),
                    ),
                    child: const Text('Đăng'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppPalette.coral.withValues(alpha: 0.7),
                  AppPalette.violet.withValues(alpha: 0.7)
                ],
              ),
              shape: BoxShape.circle,
            ),
            child:
                const Icon(Icons.auto_awesome, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 14),
          const Text('Chưa có khoảnh khắc nào',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Hãy là người đầu tiên chia sẻ điều gì đó với bạn bè.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppPalette.textSecondary),
          ),
        ],
      ),
    );
  }
}
