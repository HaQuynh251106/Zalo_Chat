class CallSession {
  final String id;
  final String conversationId;
  final String initiatorId;
  final String initiatorName;
  final String initiatorAvatar;
  final String kind; // voice | video
  final String status; // ringing | accepted | rejected | missed | ended
  final DateTime startedAt;
  final DateTime? endedAt;

  CallSession({
    required this.id,
    required this.conversationId,
    required this.initiatorId,
    required this.initiatorName,
    required this.initiatorAvatar,
    required this.kind,
    required this.status,
    required this.startedAt,
    this.endedAt,
  });

  factory CallSession.fromJson(Map<String, dynamic> j) => CallSession(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        initiatorId: j['initiator_id'] as String,
        initiatorName: (j['initiator_name'] ?? '') as String,
        initiatorAvatar: (j['initiator_avatar'] ?? '') as String,
        kind: (j['kind'] ?? 'voice') as String,
        status: (j['status'] ?? 'ringing') as String,
        startedAt: DateTime.parse(j['started_at'] as String),
        endedAt: j['ended_at'] != null
            ? DateTime.parse(j['ended_at'] as String)
            : null,
      );
}
