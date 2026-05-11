import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../config.dart';

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'ApiException($status): $message';
}

class ApiClient {
  String? _token;

  void setToken(String? token) => _token = token;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(AppConfig.apiBase);
    return base.replace(path: '/api/v1$path', queryParameters: query);
  }

  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final uri = _uri(path, query);
    http.Response res;
    switch (method) {
      case 'GET':
        res = await http.get(uri, headers: _headers());
        break;
      case 'POST':
        res = await http.post(
          uri,
          headers: _headers(),
          body: jsonEncode(body ?? {}),
        );
        break;
      case 'PUT':
        res = await http.put(
          uri,
          headers: _headers(),
          body: jsonEncode(body ?? {}),
        );
        break;
      case 'DELETE':
        res = await http.delete(uri, headers: _headers());
        break;
      default:
        throw ArgumentError('unsupported method $method');
    }
    final decoded =
        res.body.isEmpty ? {} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw ApiException(
        res.statusCode,
        (decoded['error'] ?? 'request failed').toString(),
      );
    }
    return decoded['data'];
  }

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _request('GET', path, query: query);
  Future<dynamic> post(String path, {Object? body}) =>
      _request('POST', path, body: body);
  Future<dynamic> put(String path, {Object? body}) =>
      _request('PUT', path, body: body);
  Future<dynamic> delete(String path) => _request('DELETE', path);

  /// Upload bytes to /upload. Returns the `data` payload of the response.
  Future<Map<String, dynamic>> upload({
    required Uint8List bytes,
    required String filename,
    String? mimeType,
  }) async {
    final uri = _uri('/upload');
    final req = http.MultipartRequest('POST', uri);
    if (_token != null) req.headers['Authorization'] = 'Bearer $_token';
    req.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: filename,
      contentType: mimeType != null ? MediaType.parse(mimeType) : null,
    ));
    final streamed = await req.send();
    final body = await streamed.stream.bytesToString();
    final decoded = body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(body) as Map<String, dynamic>;
    if (streamed.statusCode >= 400) {
      throw ApiException(streamed.statusCode,
          (decoded['error'] ?? 'upload failed').toString());
    }
    return decoded['data'] as Map<String, dynamic>;
  }
}
