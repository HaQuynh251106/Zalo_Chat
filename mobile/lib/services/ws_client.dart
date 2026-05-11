import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

typedef WsHandler = void Function(String type, Map<String, dynamic> payload);

class WsClient {
  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _sub;
  String? _token;
  Timer? _reconnectTimer;
  bool _closedByUser = false;

  Stream<Map<String, dynamic>> get events => _controller.stream;

  void connect(String token) {
    _closedByUser = true;
    _disconnect(clearToken: false);
    _token = token;
    _closedByUser = false;
    _open();
  }

  void _open() {
    if (_token == null) return;
    final uri = Uri.parse(
      '${AppConfig.wsBase}/api/v1/ws',
    ).replace(queryParameters: {'token': _token});
    _channel = WebSocketChannel.connect(uri);
    _sub = _channel!.stream.listen(
      (raw) {
        try {
          final j = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(j);
        } catch (_) {}
      },
      onDone: _scheduleReconnect,
      onError: (_) => _scheduleReconnect(),
      cancelOnError: true,
    );
  }

  void _scheduleReconnect() {
    if (_closedByUser || _token == null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _open);
  }

  void send(String type, [Map<String, dynamic>? payload]) {
    final ch = _channel;
    if (ch == null) return;
    ch.sink.add(
      jsonEncode({'type': type, if (payload != null) 'payload': payload}),
    );
  }

  void close() {
    _closedByUser = true;
    _disconnect(clearToken: true);
  }

  void _disconnect({required bool clearToken}) {
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _sub = null;
    _channel = null;
    if (clearToken) _token = null;
  }
}
