import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';

class AuthProvider extends ChangeNotifier {
  static const _kToken = 'access_token';
  static const _kRefreshToken = 'refresh_token';
  static const _kDeviceId = 'device_id';
  static const _kUser = 'user_json';

  final ApiClient api;
  final WsClient ws;

  AppUser? _user;
  String? _token;
  String? _refreshToken;
  String? _deviceId;

  AuthProvider({required this.api, required this.ws});

  AppUser? get user => _user;
  String? get token => _token;
  String? get deviceId => _deviceId;
  bool get isAuthenticated => _token != null && _user != null;

  Future<void> bootstrap() async {
    final sp = await SharedPreferences.getInstance();
    _token = sp.getString(_kToken);
    _refreshToken = sp.getString(_kRefreshToken);
    _deviceId = sp.getString(_kDeviceId) ?? const Uuid().v4();
    await sp.setString(_kDeviceId, _deviceId!);
    final userStr = sp.getString(_kUser);
    if (_token != null && userStr != null) {
      api.setToken(_token);
      try {
        final data = await api.get('/me');
        _user = AppUser.fromJson(data as Map<String, dynamic>);
        ws.connect(_token!);
      } catch (_) {
        if (_refreshToken != null) {
          try {
            await _refresh(sp);
          } catch (_) {
            await logout();
          }
        } else {
          await logout();
        }
      }
    } else if (_refreshToken != null) {
      try {
        await _refresh(sp);
      } catch (_) {
        await logout();
      }
    }
    notifyListeners();
  }

  Future<void> register(
    String phone,
    String password,
    String displayName,
  ) async {
    await api.post(
      '/auth/register',
      body: {'phone': phone, 'password': password, 'display_name': displayName},
    );
    await login(phone, password);
  }

  Future<void> login(String phone, String password) async {
    final sp = await SharedPreferences.getInstance();
    _deviceId ??= sp.getString(_kDeviceId) ?? const Uuid().v4();
    await sp.setString(_kDeviceId, _deviceId!);

    final data = await api.post(
      '/auth/login',
      body: {
        'phone': phone,
        'password': password,
        'device_id': _deviceId,
        'device_name': 'Flutter Client',
        'platform': defaultTargetPlatform.name,
      },
    ) as Map<String, dynamic>;

    await _applySession(sp, data);
    notifyListeners();
  }

  Future<void> _refresh(SharedPreferences sp) async {
    final refresh = _refreshToken;
    if (refresh == null) return;
    api.setToken(null);
    final data =
        await api.post('/auth/refresh', body: {'refresh_token': refresh})
            as Map<String, dynamic>;
    await _applySession(sp, data);
  }

  Future<void> _applySession(
    SharedPreferences sp,
    Map<String, dynamic> data,
  ) async {
    _token = data['access_token'] as String;
    _refreshToken = data['refresh_token'] as String?;
    _deviceId = (data['device_id'] as String?) ?? _deviceId;
    _user = AppUser.fromJson(data['user'] as Map<String, dynamic>);

    api.setToken(_token);
    ws.connect(_token!);

    await sp.setString(_kToken, _token!);
    if (_refreshToken != null) {
      await sp.setString(_kRefreshToken, _refreshToken!);
    }
    if (_deviceId != null) {
      await sp.setString(_kDeviceId, _deviceId!);
    }
    await sp.setString(_kUser, _user!.id);
  }

  Future<void> refreshMe() async {
    if (_token == null) return;
    try {
      final data = await api.get('/me');
      _user = AppUser.fromJson(data as Map<String, dynamic>);
      notifyListeners();
    } catch (_) {
      // silent: caller will surface errors when calling underlying mutation
    }
  }

  Future<void> logout({bool remote = true}) async {
    if (remote && _token != null) {
      try {
        await api.post('/auth/logout');
      } catch (_) {
        // Local logout must still proceed if server/session is already gone.
      }
    }
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kToken);
    await sp.remove(_kRefreshToken);
    await sp.remove(_kUser);
    ws.close();
    api.setToken(null);
    _token = null;
    _refreshToken = null;
    _user = null;
    notifyListeners();
  }
}
