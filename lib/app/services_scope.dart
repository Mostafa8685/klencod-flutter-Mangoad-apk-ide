import '../services/api_client.dart';
import '../services/build_service.dart';
import '../services/github_service.dart';
import '../services/project_import_service.dart';
import '../services/settings_service.dart';

class AppServices {
  AppServices(this.settings)
      : api = ApiClient(settings),
        importer = ProjectImportService() {
    github = GithubService(api, settings);
    builds = BuildService(api);
  }

  final SettingsService settings;
  final ApiClient api;
  final ProjectImportService importer;
  late final GithubService github;
  late final BuildService builds;

  static Future<AppServices> create() async => AppServices(await SettingsService.load());
}
