import 'dart:async';

import 'package:flutter/material.dart';

import '../app/localization.dart';
import '../app/services_scope.dart';
import '../app/theme.dart';
import '../models/build_job_model.dart';
import '../services/api_client.dart';
import '../widgets/mango_button.dart';
import '../widgets/status_badge.dart';

class BuildStatusScreen extends StatefulWidget {
  const BuildStatusScreen({super.key, required this.services, required this.jobId});
  final AppServices services;
  final String jobId;

  @override
  State<BuildStatusScreen> createState() => _BuildStatusScreenState();
}

class _BuildStatusScreenState extends State<BuildStatusScreen> {
  BuildJob? _job;
  List<String> _logs = [];
  String? _error;
  Timer? _timer;

  static const _stages = [
    BuildStage.waiting,
    BuildStage.preparing,
    BuildStage.validating,
    BuildStage.installing,
    BuildStage.building,
    BuildStage.uploading,
    BuildStage.completed,
  ];

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final j = await widget.services.builds.get(widget.jobId);
      await widget.services.settings.upsertJob(j);
      final logs = j.stage.isFinal ? await widget.services.builds.logs(j.id) : _logs;
      if (!mounted) return;
      setState(() {
        _job = j;
        _logs = logs;
        _error = null;
      });
      if (!j.stage.isFinal) _timer = Timer(const Duration(seconds: 6), _refresh);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      _timer = Timer(const Duration(seconds: 15), _refresh);
    }
  }

  Future<void> _retry() async {
    try {
      final j = await widget.services.builds.retry(widget.jobId);
      await widget.services.settings.upsertJob(j);
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BuildStatusScreen(services: widget.services, jobId: j.id)));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _download() async {
    try {
      await widget.services.builds.download(_job!);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  String _t(DateTime? d) => d == null ? '-' : d.toLocal().toString().substring(0, 19);

  @override
  Widget build(BuildContext context) {
    final j = _job;
    return Scaffold(
      appBar: AppBar(title: Text(L.t('build_status'))),
      body: j == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(j.projectName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                      StatusBadge(j.stage),
                    ]),
                    const SizedBox(height: 10),
                    _kv(L.t('job_id'), j.id),
                    _kv(L.t('started'), _t(j.startedAt)),
                    _kv(L.t('finished'), _t(j.finishedAt)),
                  ]),
                ),
              ),
              const SizedBox(height: 14),
              // Only the stage name is shown. GitHub Actions gives no real percentage, so none is invented.
              ..._stages.map((s) {
                final cur = j.stage == BuildStage.failed ? -1 : _stages.indexOf(j.stage);
                final idx = _stages.indexOf(s);
                final done = cur > idx || j.stage == BuildStage.completed;
                final active = cur == idx && !j.stage.isFinal;
                return ListTile(
                  dense: true,
                  leading: done
                      ? const Icon(Icons.check_circle, color: Color(0xFF3FB950))
                      : active
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.radio_button_unchecked, color: MangoColors.border),
                  title: Text(L.t('stage_${s.name}')),
                );
              }),
              if (j.stage == BuildStage.failed)
                ListTile(dense: true, leading: const Icon(Icons.cancel, color: Color(0xFFF85149)), title: Text(L.t('stage_failed')), subtitle: j.error == null ? null : Text(j.error!)),
              if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFF85149)))),
              if (j.hasApk) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    title: Text(j.apkName!, textDirection: TextDirection.ltr),
                    subtitle: Text('${((j.apkSize ?? 0) / 1048576).toStringAsFixed(1)} MB  •  ${_t(j.finishedAt)}'),
                  ),
                ),
                const SizedBox(height: 10),
                MangoButton(label: L.t('download'), icon: Icons.download, onPressed: _download),
              ],
              if (j.stage == BuildStage.failed) ...[
                const SizedBox(height: 10),
                MangoButton(label: L.t('retry'), icon: Icons.refresh, outlined: true, onPressed: _retry),
              ],
              const SizedBox(height: 14),
              ExpansionTile(
                title: Text(L.t('logs')),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(_logs.isEmpty ? '-' : _logs.join('\n'),
                        textDirection: TextDirection.ltr, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ),
                ],
              ),
            ]),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: Theme.of(context).textTheme.bodySmall),
          Flexible(child: Text(v, overflow: TextOverflow.ellipsis, textDirection: TextDirection.ltr)),
        ]),
      );
}
