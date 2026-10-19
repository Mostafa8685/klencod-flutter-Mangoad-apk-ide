import 'package:flutter/material.dart';

import '../app/localization.dart';
import '../app/services_scope.dart';
import '../services/api_client.dart';
import '../widgets/project_card.dart';
import 'build_status_screen.dart';

class BuildHistoryScreen extends StatelessWidget {
  const BuildHistoryScreen({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final jobs = services.settings.history;
        return Scaffold(
          appBar: AppBar(title: Text(L.t('history'))),
          body: jobs.isEmpty
              ? Center(child: Text(L.t('none')))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: jobs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final j = jobs[i];
                    return ProjectCard(
                      job: j,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BuildStatusScreen(services: services, jobId: j.id))),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (j.hasApk)
                          IconButton(
                            icon: const Icon(Icons.download),
                            onPressed: () async {
                              try {
                                await services.builds.download(j);
                              } on ApiException catch (e) {
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                              }
                            },
                          ),
                        if (j.stage.name == 'failed')
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: () async {
                              try {
                                final n = await services.builds.retry(j.id);
                                await services.settings.upsertJob(n);
                              } on ApiException catch (e) {
                                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                              }
                            },
                          ),
                      ]),
                    );
                  },
                ),
        );
      },
    );
  }
}
