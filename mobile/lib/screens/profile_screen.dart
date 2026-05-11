import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';
import 'devices_screen.dart';
import 'edit_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: AppPalette.primaryGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppPalette.indigo.withValues(alpha: 0.3),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white24,
                    ),
                    child: UserAvatar(
                      name: user?.displayName ?? '?',
                      url: user?.avatarUrl,
                      size: 64,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? 'Người dùng',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.phone ?? '',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                        if ((user?.bio ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            user!.bio,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.9),
                                fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _section('Tài khoản', [
              _tile(Icons.edit_outlined, 'Chỉnh sửa hồ sơ', onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const EditProfileScreen(),
                ));
              }),
              _tile(Icons.lock_outline, 'Bảo mật & quyền riêng tư'),
              _tile(Icons.devices_other_outlined, 'Thiết bị đang đăng nhập',
                  onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const DevicesScreen(),
                ));
              }),
            ]),
            const SizedBox(height: 16),
            _section('Ứng dụng', [
              _tile(Icons.color_lens_outlined, 'Giao diện',
                  trailing: const Text('Indigo + Coral')),
              _tile(Icons.notifications_none_outlined, 'Thông báo'),
              _tile(Icons.language, 'Ngôn ngữ',
                  trailing: const Text('Tiếng Việt')),
            ]),
            const SizedBox(height: 16),
            _section('Khác', [
              _tile(Icons.help_outline, 'Trợ giúp'),
              _tile(Icons.info_outline, 'Về Lumo',
                  trailing: const Text('v0.2.0')),
            ]),
            const SizedBox(height: 22),
            _logoutButton(() => auth.logout()),
          ],
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title,
              style: const TextStyle(
                fontSize: 13,
                color: AppPalette.textSecondary,
                fontWeight: FontWeight.w600,
              )),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _tile(IconData icon, String label,
      {Widget? trailing, VoidCallback? onTap}) {
    return Builder(
      builder: (context) => InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap ?? () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppPalette.indigo.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppPalette.indigo, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              if (trailing != null)
                DefaultTextStyle(
                  style: const TextStyle(
                      color: AppPalette.textSecondary, fontSize: 12),
                  child: trailing,
                ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  color: AppPalette.textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logoutButton(VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.logout, color: Colors.red, size: 20),
              ),
              const SizedBox(width: 12),
              const Text('Đăng xuất',
                  style: TextStyle(
                      color: Colors.red, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}
