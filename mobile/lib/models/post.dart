class FeedPost {
  final String id;
  final String authorId;
  final String authorName;
  final String authorAvatar;
  final String body;
  final List<String> media;
  final String visibility;
  final DateTime createdAt;
  final int reactionCount;
  final int commentCount;
  final String myReaction;

  FeedPost({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.authorAvatar,
    required this.body,
    required this.media,
    required this.visibility,
    required this.createdAt,
    required this.reactionCount,
    required this.commentCount,
    required this.myReaction,
  });

  factory FeedPost.fromJson(Map<String, dynamic> j) => FeedPost(
        id: j['id'] as String,
        authorId: j['author_id'] as String,
        authorName: (j['author_name'] ?? '') as String,
        authorAvatar: (j['author_avatar'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        media: (j['media'] as List<dynamic>? ?? const []).cast<String>(),
        visibility: (j['visibility'] ?? 'friends') as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        reactionCount: (j['reaction_count'] ?? 0) as int,
        commentCount: (j['comment_count'] ?? 0) as int,
        myReaction: (j['my_reaction'] ?? '') as String,
      );
}
