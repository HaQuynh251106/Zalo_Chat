import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/gradient_button.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_phone.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Vui lòng nhập số điện thoại và mật khẩu');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = context.read<AuthProvider>();
      if (_isRegister) {
        await auth.register(
            _phone.text.trim(), _password.text, _displayName.text.trim());
      } else {
        await auth.login(_phone.text.trim(), _password.text);
      }
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('401')) return 'Sai số điện thoại hoặc mật khẩu';
    if (s.contains('409')) return 'Số điện thoại đã đăng ký';
    return s.replaceFirst('ApiException', 'Lỗi');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppPalette.backdropGradient),
        child: SafeArea(
          child: Stack(
            children: [
              const _DecorBlobs(),
              Center(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 24),
                        _Brand(),
                        const SizedBox(height: 28),
                        _glassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                _isRegister
                                    ? 'Tạo tài khoản mới'
                                    : 'Chào mừng trở lại',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _isRegister
                                    ? 'Vài thông tin nhỏ là bắt đầu trò chuyện được rồi.'
                                    : 'Đăng nhập để tiếp tục cuộc trò chuyện của bạn.',
                                style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.78),
                                    fontSize: 13),
                              ),
                              const SizedBox(height: 20),
                              _glassField(
                                controller: _phone,
                                label: 'Số điện thoại',
                                icon: Icons.phone_iphone,
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 12),
                              _glassField(
                                controller: _password,
                                label: 'Mật khẩu',
                                icon: Icons.lock_outline,
                                obscure: _obscure,
                                trailing: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: Colors.white70,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              if (_isRegister) ...[
                                const SizedBox(height: 12),
                                _glassField(
                                  controller: _displayName,
                                  label: 'Tên hiển thị',
                                  icon: Icons.person_outline,
                                ),
                              ],
                              if (_error != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color:
                                            Colors.red.withValues(alpha: 0.4)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.error_outline,
                                          color: Colors.white, size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 20),
                              GradientButton(
                                label: _isRegister ? 'Đăng ký' : 'Đăng nhập',
                                icon: _isRegister
                                    ? Icons.person_add_alt_1
                                    : Icons.login,
                                loading: _loading,
                                onPressed: _loading ? null : _submit,
                              ),
                              const SizedBox(height: 14),
                              TextButton(
                                onPressed: () => setState(() {
                                  _isRegister = !_isRegister;
                                  _error = null;
                                }),
                                style: TextButton.styleFrom(
                                    foregroundColor: Colors.white),
                                child: Text(
                                  _isRegister
                                      ? 'Đã có tài khoản? Đăng nhập'
                                      : 'Chưa có tài khoản? Đăng ký miễn phí',
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          'Cộng đồng • Kết nối • Bảo mật',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _glassCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _glassField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? trailing,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        cursorColor: Colors.white,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
          prefixIcon: Icon(icon, color: Colors.white70, size: 20),
          suffixIcon: trailing,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.3), width: 1.2),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.bubble_chart, color: Colors.white, size: 38),
        ),
        const SizedBox(height: 14),
        const Text(
          'Lumo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        Text(
          'nhắn tin sáng & gọn',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 13,
              letterSpacing: 0.4),
        ),
      ],
    );
  }
}

class _DecorBlobs extends StatelessWidget {
  const _DecorBlobs();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -80,
            right: -60,
            child: _blob(220, Colors.white.withValues(alpha: 0.18)),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: _blob(260, AppPalette.coral.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}
