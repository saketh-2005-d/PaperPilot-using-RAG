import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => 'ApiException($status): $message';
}

class Api {
  static String baseUrl = 'https://pdf-api.niheshr.com';
  static String? _token;

  static void setToken(String? t) => _token = t;
  static String? get token => _token;

  static Map<String, String> _headers({bool json = true}) {
    final h = <String, String>{};
    if (json) h['Content-Type'] = 'application/json';
    if (_token != null) h['Authorization'] = 'Bearer $_token';
    return h;
  }

  static Future<dynamic> _decode(http.Response r) async {
    final body = r.body.isEmpty ? null : jsonDecode(r.body);
    if (r.statusCode >= 200 && r.statusCode < 300) return body;
    final msg = body is Map && body['detail'] != null ? body['detail'].toString() : r.body;
    throw ApiException(r.statusCode, msg);
  }

  static Future<Map<String, dynamic>> signup(String email, String password) async {
    final r = await http.post(
      Uri.parse('$baseUrl/auth/signup'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return await _decode(r) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final r = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: _headers(),
      body: jsonEncode({'email': email, 'password': password}),
    );
    return await _decode(r) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> google(String idToken) async {
    final r = await http.post(
      Uri.parse('$baseUrl/auth/google'),
      headers: _headers(),
      body: jsonEncode({'id_token': idToken}),
    );
    return await _decode(r) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> getMe() async {
    final r = await http.get(Uri.parse('$baseUrl/auth/me'), headers: _headers());
    return await _decode(r) as Map<String, dynamic>;
  }

  static Future<void> deleteMe() async {
    final r = await http.delete(Uri.parse('$baseUrl/auth/me'), headers: _headers());
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    await _decode(r);
  }

  static Future<List<dynamic>> listDocuments() async {
    final r = await http.get(Uri.parse('$baseUrl/documents'), headers: _headers());
    return await _decode(r) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> getDocument(int id) async {
    final r = await http.get(Uri.parse('$baseUrl/documents/$id'), headers: _headers());
    return await _decode(r) as Map<String, dynamic>;
  }

  static Future<String> getPdfUrl(int id) async {
    final r = await http.get(Uri.parse('$baseUrl/documents/$id/pdf-url'), headers: _headers());
    final body = await _decode(r) as Map<String, dynamic>;
    return body['url'] as String;
  }

  static Future<Map<String, dynamic>> uploadPdf(String filename, List<int> bytes) async {
    final req = http.MultipartRequest('POST', Uri.parse('$baseUrl/documents'))
      ..headers.addAll(_headers(json: false))
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    final streamed = await req.send();
    final r = await http.Response.fromStream(streamed);
    return await _decode(r) as Map<String, dynamic>;
  }

  static Future<void> deleteDocument(int id) async {
    final r = await http.delete(Uri.parse('$baseUrl/documents/$id'), headers: _headers());
    await _decode(r);
  }

  static Future<List<dynamic>> listMessages(int docId) async {
    final r = await http.get(Uri.parse('$baseUrl/chat/$docId/messages'), headers: _headers());
    return await _decode(r) as List<dynamic>;
  }

  static Future<Map<String, dynamic>> chat(int docId, String message) async {
    final r = await http.post(
      Uri.parse('$baseUrl/chat/$docId'),
      headers: _headers(),
      body: jsonEncode({'message': message}),
    );
    return await _decode(r) as Map<String, dynamic>;
  }
}
