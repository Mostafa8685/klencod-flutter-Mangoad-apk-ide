import '../models/github_auth_model.dart';
import 'api_client.dart';
import 'settings_service.dart';

class GithubStatusResult {
  final GithubAuthStatus status;
  final String? login;
  final int? retryAfter;
  const GithubStatusResult(this.status, {this.login, this.retryAfter});
}

class GithubService {
  GithubService(this.api, this.settings);
  final ApiClient api;
  final SettingsService settings;

  Future<DeviceCode> start() async {
    final r = await api.post('/api/auth/github/device/start');
    return DeviceCode.fromJson(r);
  }

  /// Asks the backend to check authorization. Only a `connected` reply from the
  /// server flips the app into the connected state.
  Future<GithubStatusResult> status() async {
    final r = await api.get('/api/auth/github/device/status');
    final s = r['status'] as String? ?? 'error';
    final next = nextGithubStatus(GithubAuthStatus.pending, s);
    if (next == GithubAuthStatus.connected) {
      await settings.setGithub(true, login: r['login'] as String?);
    } else if (next == GithubAuthStatus.disconnected) {
      await settings.setGithub(false);
    }
    return GithubStatusResult(next, login: r['login'] as String?, retryAfter: (r['interval'] as num?)?.toInt());
  }

  Future<void> disconnect() async {
    await api.post('/api/auth/github/disconnect');
    await settings.setGithub(false);
  }
}
