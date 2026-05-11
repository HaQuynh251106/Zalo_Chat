class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String type;
  final String body;
  final String mediaUrl;
  final bool recalled;
  final DateTime createdAt;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.body,
    this.mediaUrl = '',
    this.recalled = false,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> j) => Message(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        senderId: j['sender_id'] as String,
        type: (j['type'] ?? 'text') as String,
        body: (j['body'] ?? '') as String,
        mediaUrl: (j['media_url'] ?? '') as String,
        recalled: (j['recalled'] ?? false) as bool,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
