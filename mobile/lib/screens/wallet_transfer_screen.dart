import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/wallet.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';

class WalletTransferScreen extends StatefulWidget {
  final String? initialUserId;
  final String? initialName;
  final String initialAvatar;

  const WalletTransferScreen({
    super.key,
    this.initialUserId,
    this.initialName,
    this.initialAvatar = '',
  });

  @override
  State<WalletTransferScreen> createState() => _WalletTransferScreenState();
}

class _WalletTransferScreenState extends State<WalletTransferScreen> {
  final _amount = TextEditingController();
  final _memo = TextEditingController();
  List<Map<String, dynamic>> _friends = [];
  Wallet? _wallet;
  Map<String, dynamic>? _selected;
  bool _loading = true;
  bool _submitting = false;

  int get _amountCents {
    final raw = digitsOnly(_amount.text);
    if (raw.isEmpty) return 0;
    return int.parse(raw) * 100;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final api = context.read<ApiClient>();
      final results = await Future.wait([
        api.get('/wallet/me'),
        api.get('/contacts'),
      ]);
      final wallet = Wallet.fromJson(results[0] as Map<String, dynamic>);
      final contacts = (results[1] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((c) => c['status'] == 'accepted')
          .toList();
      Map<String, dynamic>? selected;
      if (widget.initialUserId != null) {
        selected = contacts.cast<Map<String, dynamic>?>().firstWhere(
              (c) => c?['user_id'] == widget.initialUserId,
              orElse: () => {
                'user_id': widget.initialUserId,
                'display_name': widget.initialName ?? 'Người nhận',
                'avatar_url': widget.initialAvatar,
                'status': 'accepted',
              },
            );
      }
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _friends = contacts;
        _selected = selected;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _submit() async {
    final peer = _selected;
    if (peer == null) return;
    final api = context.read<ApiClient>();
    final cents = _amountCents;
    final balance = _wallet?.balanceCents ?? 0;
    if (cents < 1000 * 100 || cents > 20000000 * 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Số tiền chuyển từ 1.000 ₫ đến 20.000.000 ₫'),
        ),
      );
      return;
    }
    if (cents > balance) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Số dư không đủ')),
      );
      return;
    }
    final name = (peer['display_name'] ?? '') as String;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xác nhận chuyển tiền'),
        content: Text('Chuyển ${formatVndCents(cents)} tới $name?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Chuyển'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _submitting = true);
    try {
      await api.post('/wallet/transfer', body: {
        'to_user_id': peer['user_id'],
        'amount_cents': cents,
        'memo': _memo.text.trim(),
      });
      if (!mounted) return;
      setState(() => _submitting = false);
      await _showSuccess(name);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_friendlyError(e))),
      );
    }
  }

  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('insufficient_funds')) return 'Số dư không đủ';
    if (s.contains('not_friends')) return 'Chỉ có thể chuyển tiền cho bạn bè';
    if (s.contains('blocked')) return 'Không thể chuyển tiền do chặn liên hệ';
    return s;
  }

  Future<void> _showSuccess(String name) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        Timer(const Duration(milliseconds: 1200), () {
          final nav = Navigator.of(context, rootNavigator: true);
          if (nav.canPop()) nav.pop();
        });
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: const BoxDecoration(
                  color: AppPalette.mint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 14),
              const Text(
                'Chuyển tiền thành công',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 6),
              Text(
                '${formatVndCents(_amountCents)} tới $name',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppPalette.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final balance = _wallet?.balanceCents ?? 0;
    final overBalance = _amountCents > balance;
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      appBar: AppBar(
        title: const Text('Chuyển tiền'),
        backgroundColor: Colors.white,
        foregroundColor: AppPalette.textPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppPalette.indigo))
          : selected == null
              ? _friendPicker()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                  children: [
                    _balanceCard(balance),
                    const SizedBox(height: 14),
                    _recipientCard(selected),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: 'Số tiền',
                        suffixText: '₫',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        errorText: overBalance ? 'Số dư không đủ' : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _memo,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Lời nhắn',
                        prefixIcon: Icon(Icons.notes_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppPalette.indigo,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _submitting || overBalance ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _amountCents > 0
                                    ? 'Chuyển ${formatVndCents(_amountCents)}'
                                    : 'Chuyển tiền',
                              ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _friendPicker() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
      children: [
        const Text(
          'Chọn bạn bè',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        if (_friends.isEmpty)
          const Text(
            'Bạn chưa có bạn bè phù hợp để chuyển tiền.',
            style: TextStyle(color: AppPalette.textSecondary),
          )
        else
          for (final f in _friends)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _friendTile(f),
            ),
      ],
    );
  }

  Widget _friendTile(Map<String, dynamic> f) {
    final name = (f['display_name'] ?? '') as String;
    final avatar = (f['avatar_url'] ?? '') as String;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => setState(() => _selected = f),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              UserAvatar(name: name, url: avatar, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.chevron_right, color: AppPalette.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _balanceCard(int balance) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              color: AppPalette.indigo),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Số dư: ${formatVndCents(balance)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recipientCard(Map<String, dynamic> selected) {
    final name = (selected['display_name'] ?? '') as String;
    final avatar = (selected['avatar_url'] ?? '') as String;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          UserAvatar(name: name, url: avatar, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Người nhận',
                  style:
                      TextStyle(color: AppPalette.textSecondary, fontSize: 12),
                ),
                Text(
                  name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ],
            ),
          ),
          if (widget.initialUserId == null)
            TextButton(
              onPressed: () => setState(() => _selected = null),
              child: const Text('Đổi'),
            ),
        ],
      ),
    );
  }
}
