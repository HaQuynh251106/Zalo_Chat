class Conversation {
  final String id;
  final String type; // direct | group
  final String title;
  final String avatarUrl;
  final DateTime? lastMessageAt;
  final String lastMessagePreview;
  final int unreadCount;
  final List<String>? memberIds;

  Conversation({
    required this.id,
    required this.type,
    required this.title,
    this.avatarUrl = '',
    this.lastMessageAt,
    this.lastMessagePreview = '',
    this.unreadCount = 0,
    this.memberIds,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        type: j['type'] as String,
        title: (j['title'] ?? '') as String,
        avatarUrl: (j['avatar_url'] ?? '') as String,
        lastMessageAt: j['last_message_at'] != null
            ? DateTime.parse(j['last_message_at'] as String)
            : null,
        lastMessagePreview: (j['last_message'] ?? '') as String,
        unreadCount: (j['unread_count'] ?? 0) as int,
        memberIds: (j['member_ids'] as List<dynamic>?)?.cast<String>(),
      );
}
