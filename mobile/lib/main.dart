import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/auth_provider.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/api_client.dart';
import 'services/ws_client.dart';
import 'theme.dart';
import 'widgets/incoming_call_overlay.dart';
import 'widgets/money_toast_overlay.dart';

void main() {
  final api = ApiClient();
  final ws = WsClient();
  runApp(LumoApp(api: api, ws: ws));
}

class LumoApp extends StatelessWidget {
  final ApiClient api;
  final WsClient ws;
  const LumoApp({super.key, required this.api, required this.ws});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        Provider<WsClient>.value(value: ws),
        ChangeNotifierProvider(
          create: (_) => AuthProvider(api: api, ws: ws)..bootstrap(),
        ),
      ],
      child: MaterialApp(
        title: 'Lumo',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isAuthenticated) return const LoginScreen();
    return const IncomingCallOverlay(
      child: MoneyToastOverlay(child: HomeShell()),
    );
  }
}
