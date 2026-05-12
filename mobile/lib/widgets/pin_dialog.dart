import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

enum PinDialogMode { setup, change, verify }

/// Reusable PIN entry dialog used by the "Hide conversation" feature.
/// - setup: enter new PIN + confirm
/// - change: enter old PIN + new PIN + confirm
/// - verify: enter PIN
class PinDialog extends StatefulWidget {
  final PinDialogMode mode;
  final String? title;
  final String? subtitle;

  const PinDialog({
    super.key,
    required this.mode,
    this.title,
    this.subtitle,
  });

  /// Returns a record: ({String? oldPin, String pin}) or null on cancel.
  static Future<Map<String, String>?> show(
    BuildContext context, {
    required PinDialogMode mode,
    String? title,
    String? subtitle,
  }) {
    return showDialog<Map<String, String>>(
      context: context,
      builder: (_) => PinDialog(mode: mode, title: title, subtitle: subtitle),
    );
  }

  @override
  State<PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<PinDialog> {
  final _old = TextEditingController();
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _old.dispose();
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool _validPin(String p) =>
      p.length >= 4 && p.length <= 12 && RegExp(r'^\d+$').hasMatch(p);

  void _submit() {
    final pin = _pin.text;
    if (!_validPin(pin)) {
      setState(() => _error = 'PIN phải 4-12 chữ số');
      return;
    }
    if (widget.mode != PinDialogMode.verify && pin != _confirm.text) {
      setState(() => _error = 'PIN xác nhận không khớp');
      return;
    }
    if (widget.mode == PinDialogMode.change && _old.text.isEmpty) {
      setState(() => _error = 'Nhập PIN hiện tại');
      return;
    }
    Navigator.pop(context, {
      'pin': pin,
      if (widget.mode == PinDialogMode.change) 'old_pin': _old.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    String defaultTitle;
    switch (widget.mode) {
      case PinDialogMode.setup:
        defaultTitle = 'Đặt mã PIN ẩn';
        break;
      case PinDialogMode.change:
        defaultTitle = 'Đổi mã PIN';
        break;
      case PinDialogMode.verify:
        defaultTitle = 'Nhập mã PIN';
        break;
    }
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(widget.title ?? defaultTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.subtitle != null) ...[
            Text(widget.subtitle!,
                style: const TextStyle(
                    color: AppPalette.textSecondary, fontSize: 12)),
            const SizedBox(height: 12),
          ],
          if (widget.mode == PinDialogMode.change) ...[
            TextField(
              controller: _old,
              autofocus: true,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'PIN hiện tại',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 10),
          ],
          TextField(
            controller: _pin,
            autofocus: widget.mode != PinDialogMode.change,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: widget.mode == PinDialogMode.verify
                  ? 'PIN'
                  : 'PIN mới (4-12 chữ số)',
              prefixIcon: const Icon(Icons.password_rounded),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.mode != PinDialogMode.verify) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Xác nhận PIN',
                prefixIcon: Icon(Icons.check),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Huỷ')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppPalette.indigo),
          onPressed: _submit,
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }
}
