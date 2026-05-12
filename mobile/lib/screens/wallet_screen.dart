import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/wallet.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';
import '../theme.dart';
import '../widgets/user_avatar.dart';
import 'wallet_topup_sheet.dart';
import 'wallet_transfer_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  Wallet? _wallet;
  List<WalletTx> _txs = [];
  bool _loading = true;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _load();
    _wsSub = context.read<WsClient>().events.listen((ev) {
      final type = ev['type'];
      if (type == 'wallet.updated' || type == 'money.received') {
        _load(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final api = context.read<ApiClient>();
      final results = await Future.wait([
        api.get('/wallet/me'),
        api.get('/wallet/transactions'),
      ]);
      if (!mounted) return;
      setState(() {
        _wallet = Wallet.fromJson(results[0] as Map<String, dynamic>);
        _txs = (results[1] as List<dynamic>)
            .map((e) => WalletTx.fromJson(e as Map<String, dynamic>))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _topup() async {
    final changed = await WalletTopupSheet.show(context);
    if (changed == true) _load();
  }

  Future<void> _transfer() async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const WalletTransferScreen()),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    return Scaffold(
      backgroundColor: AppPalette.bgLight,
      appBar: AppBar(
        title: const Text('Ví Lumo'),
        backgroundColor: Colors.white,
        foregroundColor: AppPalette.textPrimary,
        elevation: 0,
      ),
      body: RefreshIndicator(
        color: AppPalette.indigo,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
          children: [
            _balanceCard(wallet?.balanceCents ?? 0),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    Icons.add_card_outlined,
                    'Nạp tiền',
                    _topup,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionButton(
                    Icons.payments_outlined,
                    'Chuyển tiền',
                    _transfer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Lịch sử giao dịch',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: CircularProgressIndicator(color: AppPalette.indigo),
                ),
              )
            else if (_txs.isEmpty)
              _empty()
            else
              ..._historyItems(_txs),
          ],
        ),
      ),
    );
  }

  Widget _balanceCard(int cents) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB347), Color(0xFFFFCC33), Color(0xFFFF8C42)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF8C42).withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_wallet_outlined,
                    color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text(
                'Số dư khả dụng',
                style:
                    TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            formatVndCents(cents),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Cập nhật ${DateFormat('HH:mm dd/MM').format(DateTime.now())}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.82)),
          ),
        ],
      ),
    );
  }

  Widget _actionButton(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppPalette.indigo),
              const SizedBox(width: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _historyItems(List<WalletTx> txs) {
    final out = <Widget>[];
    String? lastDate;
    final dayFmt = DateFormat('dd/MM/yyyy');
    for (final tx in txs) {
      final day = dayFmt.format(tx.createdAt.toLocal());
      if (day != lastDate) {
        out.add(Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
          child: Text(
            day,
            style: const TextStyle(
              color: AppPalette.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ));
        lastDate = day;
      }
      out.add(_txTile(tx));
    }
    return out;
  }

  Widget _txTile(WalletTx tx) {
    final cp = tx.counterparty;
    final incoming = tx.isIncoming;
    final title = tx.type == 'topup'
        ? 'Nạp tiền'
        : incoming
            ? 'Nhận từ ${cp?.displayName ?? 'Bạn bè'}'
            : 'Chuyển tới ${cp?.displayName ?? 'Bạn bè'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          if (cp == null)
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppPalette.indigo.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.add_card_outlined, color: AppPalette.indigo),
            )
          else
            UserAvatar(
              name: cp.displayName,
              url: cp.avatarUrl,
              size: 42,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                if (tx.memo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    tx.memo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppPalette.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${incoming ? '+' : '-'}${formatVndCents(tx.amountCents)}',
            style: TextStyle(
              color: incoming ? AppPalette.mint : Colors.red,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 38, color: AppPalette.textSecondary),
          SizedBox(height: 10),
          Text(
            'Chưa có giao dịch',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          SizedBox(height: 4),
          Text(
            'Nạp tiền thử nghiệm hoặc chuyển tiền cho bạn bè để bắt đầu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppPalette.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
