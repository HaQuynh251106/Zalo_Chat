class AppUser {
  final String id;
  final String phone;
  final String displayName;
  final String avatarUrl;
  final String bio;

  AppUser({
    required this.id,
    required this.phone,
    required this.displayName,
    this.avatarUrl = '',
    this.bio = '',
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        phone: j['phone'] as String,
        displayName: (j['display_name'] ?? '') as String,
        avatarUrl: (j['avatar_url'] ?? '') as String,
        bio: (j['bio'] ?? '') as String,
      );
}
