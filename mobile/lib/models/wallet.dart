import 'package:intl/intl.dart';

class Wallet {
  final String userId;
  final int balanceCents;
  final DateTime updatedAt;

  Wallet({
    required this.userId,
    required this.balanceCents,
    required this.updatedAt,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) => Wallet(
        userId: (json['user_id'] ?? '') as String,
        balanceCents: (json['balance_cents'] as num? ?? 0).toInt(),
        updatedAt: DateTime.parse(
          (json['updated_at'] ?? DateTime.now().toIso8601String()) as String,
        ),
      );
}

class WalletCounterparty {
  final String id;
  final String displayName;
  final String avatarUrl;

  WalletCounterparty({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
  });

  factory WalletCounterparty.fromJson(Map<String, dynamic> json) =>
      WalletCounterparty(
        id: (json['id'] ?? '') as String,
        displayName: (json['display_name'] ?? json['name'] ?? '') as String,
        avatarUrl: (json['avatar_url'] ?? json['avatar'] ?? '') as String,
      );
}

class WalletTx {
  final String id;
  final String type;
  final int amountCents;
  final int balanceAfter;
  final String memo;
  final WalletCounterparty? counterparty;
  final String? relatedMessageId;
  final DateTime createdAt;

  WalletTx({
    required this.id,
    required this.type,
    required this.amountCents,
    required this.balanceAfter,
    required this.memo,
    this.counterparty,
    this.relatedMessageId,
    required this.createdAt,
  });

  bool get isIncoming => type == 'transfer_in' || type == 'topup';

  factory WalletTx.fromJson(Map<String, dynamic> json) => WalletTx(
        id: json['id'] as String,
        type: json['type'] as String,
        amountCents: (json['amount_cents'] as num).toInt(),
        balanceAfter: (json['balance_after'] as num? ?? 0).toInt(),
        memo: (json['memo'] ?? '') as String,
        counterparty: json['counterparty'] is Map<String, dynamic>
            ? WalletCounterparty.fromJson(
                json['counterparty'] as Map<String, dynamic>,
              )
            : null,
        relatedMessageId: json['related_message_id'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}

String formatVndCents(int cents) {
  final vnd = cents ~/ 100;
  return '${NumberFormat('#,###', 'vi_VN').format(vnd)} ₫';
}

String digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');
