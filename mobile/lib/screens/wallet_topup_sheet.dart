import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/wallet.dart';
import '../services/api_client.dart';
import '../theme.dart';

class WalletTopupSheet extends StatefulWidget {
  const WalletTopupSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const WalletTopupSheet(),
    );
  }

  @override
  State<WalletTopupSheet> createState() => _WalletTopupSheetState();
}

class _WalletTopupSheetState extends State<WalletTopupSheet> {
  final _amount = TextEditingController();
  bool _submitting = false;

  int get _amountCents {
    final raw = digitsOnly(_amount.text);
    if (raw.isEmpty) return 0;
    return int.parse(raw) * 100;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cents = _amountCents;
    if (cents < 10000 * 100 || cents > 50000000 * 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Số tiền nạp từ 10.000 ₫ đến 50.000.000 ₫'),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await context.read<ApiClient>().post('/wallet/topup', body: {
        'amount_cents': cents,
        'source': 'mock',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nạp tiền thành công')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final presets = [50000, 100000, 200000, 500000, 1000000];
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppPalette.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Nạp tiền ví Lumo',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          const Text(
            'Giao dịch thử nghiệm, chưa kết nối cổng thanh toán thật.',
            style: TextStyle(color: AppPalette.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _amount,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Số tiền',
              suffixText: '₫',
              prefixIcon: Icon(Icons.payments_outlined),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final value in presets)
                ChoiceChip(
                  selected: _amount.text == value.toString(),
                  label: Text(formatVndCents(value * 100)),
                  onSelected: (_) {
                    _amount.text = value.toString();
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppPalette.bgLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined,
                    color: AppPalette.indigo),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Nguồn tiền: Mock gateway',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.indigo,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _submitting ? null : _submit,
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
                          ? 'Xác nhận ${formatVndCents(_amountCents)}'
                          : 'Xác nhận',
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
