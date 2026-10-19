import 'package:flutter/material.dart';

import '../app/localization.dart';
import '../app/services_scope.dart';
import '../models/build_job_model.dart';
import '../services/settings_service.dart';
import '../widgets/mango_button.dart';
import '../widgets/mango_logo.dart';
import '../widgets/project_card.dart';
import '../app/theme.dart';
import 'build_history_screen.dart';
import 'build_status_screen.dart';
import 'github_connect_screen.dart';
import 'customization_screen.dart';
import 'ide_workspace_screen.dart';
import 'new_build_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    final s = services.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final history = s.history;
        final ok = history.where((j) => j.stage == BuildStage.completed).length;
        final failed = history.where((j) => j.stage == BuildStage.failed).length;
        final last = history.isEmpty ? null : history.first.projectName;
        return Scaffold(
          appBar: AppBar(
            title: const Text('MANGO APK STUDIO', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
            actions: [
              IconButton(
                icon: Icon(s.darkMode ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
                onPressed: () => s.setDark(!s.darkMode),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(services: services))),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(children: [
                const MangoLogo(size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Mango APK Studio', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text(L.t('dev'), style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              Card(
                child: ListTile(
                  leading: Icon(Icons.hub_outlined, color: s.githubConnected ? const Color(0xFF3FB950) : MangoColors.githubBlue),
                  title: Text(L.t('github_status')),
                  subtitle: Text(s.githubConnected
                      ? '${L.t('connected')}${s.githubLogin != null ? ' • ${s.githubLogin}' : ''}'
                      : L.t('disconnected')),
                  trailing: TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GithubConnectScreen(services: services))),
                    child: Text(L.t('connect_github')),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                _stat(context, L.t('builds_total'), '${history.length}'),
                const SizedBox(width: 8),
                _stat(context, L.t('builds_ok'), '$ok'),
                const SizedBox(width: 8),
                _stat(context, L.t('builds_failed'), '$failed'),
              ]),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: Text(L.t('last_project')),
                  trailing: Text(last == null || last.isEmpty ? L.t('none') : last),
                ),
              ),
              const SizedBox(height: 16),
              MangoButton(
                label: L.t('open_ide'),
                icon: Icons.code_rounded,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => IdeWorkspaceScreen(
                      onBuildWithMangoBackend: (projectName, zipBytes) async {
                        final fileName = '$projectName.zip';
                        final report = services.importer.analyze(
                          fileName,
                          zipBytes,
                          maxZipMb: services.settings.maxZipMb,
                        );
                        if (!report.ok) {
                          throw Exception(report.issues.join('\n'));
                        }
                        if (!context.mounted) return;
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CustomizationScreen(
                              services: services,
                              report: report,
                              zipBytes: zipBytes,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              MangoButton(
                label: L.t('new_build'),
                icon: Icons.add_circle_outline,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewBuildScreen(services: services))),
              ),
              const SizedBox(height: 10),
              MangoButton(
                label: L.t('pick_zip'),
                icon: Icons.folder_zip_outlined,
                outlined: true,
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewBuildScreen(services: services, autoPick: true))),
              ),
              const SizedBox(height: 22),
              Text(L.t('recent_projects'), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (s.recentProjects.isEmpty)
                Text(L.t('none'), style: Theme.of(context).textTheme.bodySmall)
              else
                ...s.recentProjects.take(5).map((p) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Card(child: ListTile(dense: true, title: Text(p.name), subtitle: Text(p.type))),
                    )),
              const SizedBox(height: 18),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(L.t('recent_builds'), style: const TextStyle(fontWeight: FontWeight.w700)),
                TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BuildHistoryScreen(services: services))),
                  child: Text(L.t('history')),
                ),
              ]),
              if (history.isEmpty)
                Text(L.t('none'), style: Theme.of(context).textTheme.bodySmall)
              else
                ...history.take(3).map((j) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ProjectCard(
                        job: j,
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BuildStatusScreen(services: services, jobId: j.id))),
                      ),
                    )),
              const SizedBox(height: 18),
              Center(child: Text('${L.t('version')} $kAppVersion', style: Theme.of(context).textTheme.bodySmall)),
            ],
          ),
        );
      },
    );
  }

  Widget _stat(BuildContext c, String label, String v) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: MangoColors.orange)),
              const SizedBox(height: 2),
              Text(label, style: Theme.of(c).textTheme.bodySmall),
            ]),
          ),
        ),
      );
}
