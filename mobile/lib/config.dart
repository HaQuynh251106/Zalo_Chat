class AppConfig {
  // Override with --dart-define=API_BASE=http://10.0.2.2:8080 for Android emulator,
  // or http://localhost:8080 for iOS sim / desktop / web.
  static const String apiBase = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://localhost:8080',
  );

  static String get wsBase {
    final uri = Uri.parse(apiBase);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${uri.authority}';
  }
}
