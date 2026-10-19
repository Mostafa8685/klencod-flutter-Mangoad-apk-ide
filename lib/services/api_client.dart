import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/localization.dart';
import 'settings_service.dart';

class ApiException implements Exception {
  final int? status;
  final String code;
  final String? detail;
  const ApiException(this.code, {this.status, this.detail});

  /// Clear, user-facing text. Technical detail is kept separate for logs.
  String get message => friendlyError(code);
  @override
  String toString() => 'ApiException($code, $status, $detail)';
}

String friendlyError(String code) {
  const map = {
    'no_backend': 'err_no_backend',
    'backend_unavailable': 'err_unavailable',
    'timeout': 'err_timeout',
    'github_not_connected': 'err_github_not_connected',
    'authorization_pending': 'err_auth_pending',
    'token_expired': 'err_token_expired',
    'expired_token': 'err_token_expired',
    'rate_limited': 'err_rate_limit',
    'zip_invalid': 'err_zip_invalid',
    'unsupported_project': 'err_unsupported',
    'release_unsupported': 'err_unsupported',
    'artifact_missing': 'err_artifact_missing',
    'download_failed': 'err_download',
  };
  return L.t(map[code] ?? 'err_generic');
}

/// Validates a backend URL: HTTPS only (plain HTTP only for local development).
bool isAcceptableBackendUrl(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return false;
  if (u.scheme == 'https') return true;
  return u.scheme == 'http' && (u.host == 'localhost' || u.host == '10.0.2.2' || u.host == '127.0.0.1');
}

class ApiClient {
  ApiClient(this.settings, {http.Client? client}) : _http = client ?? http.Client();
  final SettingsService settings;
  final http.Client _http;
  static const _timeout = Duration(seconds: 30);

  Uri uri(String path, [Map<String, String>? q]) {
    final base = settings.backendUrl;
    if (base.isEmpty || !isAcceptableBackendUrl(base)) throw const ApiException('no_backend');
    final b = Uri.parse(base);
    return b.replace(path: '${b.path.replaceAll(RegExp(r'/+$'), '')}$path', queryParameters: q);
  }

  Future<void> ensureSession() async {
    if (settings.sessionToken != null) return;
    final r = await _send(() => _http.post(
          uri('/api/session'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'deviceId': settings.deviceId}),
        ));
    await settings.setSession(r['token'] as String);
  }

  Future<Map<String, String>> headers() async {
    await ensureSession();
    return {'authorization': 'Bearer ${settings.sessionToken}', 'content-type': 'application/json'};
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) async {
    final h = await headers();
    return _send(() => _http.get(uri(path, query), headers: h));
  }

  Future<Map<String, dynamic>> post(String path, [Object? body]) async {
    final h = await headers();
    return _send(() => _http.post(uri(path), headers: h, body: jsonEncode(body ?? {})));
  }

  Future<Map<String, dynamic>> sendMultipart(http.MultipartRequest req) async {
    final h = await headers();
    req.headers['authorization'] = h['authorization']!;
    return _send(() async => http.Response.fromStream(await _http.send(req)),
        timeout: const Duration(minutes: 5));
  }

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() fn,
      {Duration timeout = _timeout}) async {
    http.Response res;
    try {
      res = await fn().timeout(timeout);
    } on TimeoutException {
      throw const ApiException('timeout');
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('backend_unavailable', detail: e.toString());
    }
    Map<String, dynamic> body = {};
    try {
      final d = jsonDecode(utf8.decode(res.bodyBytes));
      if (d is Map<String, dynamic>) body = d;
    } catch (_) {}
    if (res.statusCode >= 200 && res.statusCode < 300) return body;
    final err = body['error'];
    final code = err is Map ? (err['code'] as String? ?? 'error') : 'error';
    if (res.statusCode == 401) await settings.setSession(null);
    if (res.statusCode == 429) throw ApiException('rate_limited', status: 429);
    if (res.statusCode >= 500 && code == 'error') {
      throw ApiException('backend_unavailable', status: res.statusCode);
    }
    throw ApiException(code, status: res.statusCode, detail: err is Map ? err['message'] as String? : null);
  }
}
