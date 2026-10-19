import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mango_apk_studio/models/build_job_model.dart';
import 'package:mango_apk_studio/models/github_auth_model.dart';
import 'package:mango_apk_studio/services/api_client.dart';
import 'package:mango_apk_studio/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('build job parsing', () {
    final j = BuildJob.fromJson({
      'id': 'abc', 'projectName': 'Lens', 'stage': 'building',
      'createdAt': '2026-10-17T10:00:00.000Z',
    });
    expect(j.stage, BuildStage.building);
    expect(j.hasApk, isFalse);
    expect(BuildStage.parse('nonsense'), BuildStage.waiting);
    final done = BuildJob.fromJson({
      'id': 'abc', 'stage': 'completed', 'apkName': 'a.apk', 'apkSize': 1000,
      'createdAt': '2026-10-17T10:00:00.000Z',
    });
    expect(done.hasApk, isTrue);
    final noApk = BuildJob.fromJson({'id': 'x', 'stage': 'completed', 'createdAt': '2026-10-17T10:00:00.000Z'});
    expect(noApk.hasApk, isFalse, reason: 'completed without an APK must not be downloadable');
    expect(BuildJob.fromJson(done.toJson()).apkName, 'a.apk');
  });

  test('github oauth state transitions', () {
    expect(nextGithubStatus(GithubAuthStatus.pending, 'pending'), GithubAuthStatus.pending);
    expect(nextGithubStatus(GithubAuthStatus.pending, 'slow_down'), GithubAuthStatus.pending);
    expect(nextGithubStatus(GithubAuthStatus.pending, 'connected'), GithubAuthStatus.connected);
    expect(nextGithubStatus(GithubAuthStatus.pending, 'expired'), GithubAuthStatus.expired);
    expect(nextGithubStatus(GithubAuthStatus.pending, 'denied'), GithubAuthStatus.denied);
    expect(nextGithubStatus(GithubAuthStatus.pending, 'whatever'), GithubAuthStatus.error);
  });

  test('backend url acceptance', () {
    expect(isAcceptableBackendUrl('https://api.example.com'), isTrue);
    expect(isAcceptableBackendUrl('http://evil.com'), isFalse);
    expect(isAcceptableBackendUrl('http://10.0.2.2:8080'), isTrue);
    expect(isAcceptableBackendUrl('ftp://x'), isFalse);
  });

  test('api error handling', () async {
    SharedPreferences.setMockInitialValues({'backend': 'https://api.test', 'session': 't'});
    final settings = await SettingsService.load();
    final client = MockClient((req) async {
      if (req.url.path == '/api/builds/rl') return http.Response('{}', 429);
      if (req.url.path == '/api/builds/gone') {
        return http.Response(jsonEncode({'error': {'code': 'github_not_connected', 'message': 'x'}}), 403);
      }
      return http.Response('boom', 502);
    });
    final api = ApiClient(settings, client: client);
    expect(() => api.get('/api/builds/rl'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'rate_limited')));
    expect(() => api.get('/api/builds/gone'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'github_not_connected')));
    expect(() => api.get('/api/builds/other'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'backend_unavailable')));
  });

  test('missing backend url is reported', () async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(await SettingsService.load());
    expect(() => api.uri('/x'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 'no_backend')));
  });
}
