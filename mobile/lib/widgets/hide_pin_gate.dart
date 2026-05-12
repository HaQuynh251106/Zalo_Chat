import 'package:flutter/material.dart';
import '../services/api_client.dart';
import 'pin_dialog.dart';

/// Stealth gate for "completely hidden" conversations.
///
/// When [isHidden] is true: shows a *neutral* snackbar (no mention of "ẩn"
/// to avoid leaking the existence to anyone shoulder-surfing) and returns
/// false — the caller should NOT navigate.
///
/// When [isHidden] is false: returns true immediately.
///
/// To actually access a hidden conversation, the user must go through
/// Profile -> Trò chuyện ẩn (PIN-gated) or the conversation search bar
/// (which calls [unlockHiddenViaPin] before opening).
bool blockIfHidden(
  BuildContext context, {
  required bool isHidden,
}) {
  if (!isHidden) return true;
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(
      duration: Duration(seconds: 2),
      content: Text('Không có cuộc trò chuyện nào'),
    ),
  );
  return false;
}

/// Verifies the user's hide-PIN and returns true on success.
/// Used by entry points that DO want to allow access to a hidden conv
/// (e.g. exact-name search results).
Future<bool> unlockHiddenViaPin(
  BuildContext context, {
  required ApiClient api,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final res = await PinDialog.show(
    context,
    mode: PinDialogMode.verify,
    title: 'Nhập mã PIN',
    subtitle: 'Cuộc trò chuyện này yêu cầu xác minh.',
  );
  if (res == null) return false;
  try {
    await api.post('/me/hide-pin/verify', body: {'pin': res['pin']});
    return true;
  } catch (e) {
    final msg = e.toString();
    messenger.showSnackBar(SnackBar(
      content: Text(msg.contains('wrong pin') ? 'Mã PIN không đúng' : '$e'),
    ));
    return false;
  }
}
