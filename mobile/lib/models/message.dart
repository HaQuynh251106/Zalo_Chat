class MessageReaction {
  final String userId;
  final String emoji;
  MessageReaction({required this.userId, required this.emoji});
  factory MessageReaction.fromJson(Map<String, dynamic> j) => MessageReaction(
        userId: j['user_id'] as String,
        emoji: (j['emoji'] ?? '') as String,
      );
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String type;
  final String body;
  final String mediaUrl;
  final bool recalled;
  final DateTime? pinnedAt;
  final DateTime createdAt;
  final String? replyToId;
  final String replyToSnippet;
  final String? replyToSender;
  final List<MessageReaction> reactions;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.body,
    this.mediaUrl = '',
    this.recalled = false,
    this.pinnedAt,
    required this.createdAt,
    this.replyToId,
    this.replyToSnippet = '',
    this.replyToSender,
    this.reactions = const [],
  });

  bool get isPinned => pinnedAt != null;

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        senderId: j['sender_id'] as String,
        type: (j['type'] ?? 'text') as String,
        body: (j['body'] ?? '') as String,
        mediaUrl: (j['media_url'] ?? '') as String,
        recalled: (j['recalled'] ?? false) as bool,
        pinnedAt: j['pinned_at'] != null
            ? DateTime.parse(j['pinned_at'] as String)
            : null,
        createdAt: DateTime.parse(j['created_at'] as String),
        replyToId: j['reply_to_id'] as String?,
        replyToSnippet: (j['reply_to_snippet'] ?? '') as String,
        replyToSender: j['reply_to_sender'] as String?,
        reactions: (j['reactions'] as List<dynamic>? ?? const [])
            .map((e) => MessageReaction.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Message copyWith({
    bool? recalled,
    String? body,
    Object? pinnedAt = _sentinel,
    List<MessageReaction>? reactions,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        body: body ?? this.body,
        mediaUrl: mediaUrl,
        recalled: recalled ?? this.recalled,
        pinnedAt: identical(pinnedAt, _sentinel)
            ? this.pinnedAt
            : pinnedAt as DateTime?,
        createdAt: createdAt,
        replyToId: replyToId,
        replyToSnippet: replyToSnippet,
        replyToSender: replyToSender,
        reactions: reactions ?? this.reactions,
      );
}

const Object _sentinel = Object();
