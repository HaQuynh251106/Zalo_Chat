import 'package:flutter_test/flutter_test.dart';
import 'package:lumo/main.dart';
import 'package:lumo/services/api_client.dart';
import 'package:lumo/services/ws_client.dart';

void main() {
  testWidgets('App boots without crashing', (tester) async {
    await tester.pumpWidget(LumoApp(api: ApiClient(), ws: WsClient()));
    await tester.pump();
    expect(find.byType(LumoApp), findsOneWidget);
  });
}
