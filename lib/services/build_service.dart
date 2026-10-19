import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../models/build_job_model.dart';
import 'api_client.dart';

class BuildRequest {
  final String projectName;
  final String projectType;
  final String appName;
  final String packageName;
  final String versionName;
  final int versionCode;
  final String buildType;
  final String outputName;
  const BuildRequest({
    required this.projectName,
    required this.projectType,
    required this.appName,
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.buildType,
    required this.outputName,
  });

  Map<String, dynamic> toJson() => {
        'projectName': projectName,
        'projectType': projectType,
        'appName': appName,
        'packageName': packageName,
        'versionName': versionName,
        'versionCode': versionCode,
        'buildType': buildType,
        'outputName': outputName,
      };
}

class BuildService {
  BuildService(this.api);
  final ApiClient api;

  Future<BuildJob> create(BuildRequest req, Uint8List zip, {Uint8List? icon}) async {
    final m = http.MultipartRequest('POST', api.uri('/api/builds'))
      ..fields['meta'] = jsonEncode(req.toJson())
      ..files.add(http.MultipartFile.fromBytes('source', zip, filename: 'source.zip'));
    if (icon != null) {
      m.files.add(http.MultipartFile.fromBytes('icon', icon, filename: 'icon.png'));
    }
    final r = await api.sendMultipart(m);
    return BuildJob.fromJson(r['job'] as Map<String, dynamic>);
  }

  Future<BuildJob> get(String id) async {
    final r = await api.get('/api/builds/$id');
    return BuildJob.fromJson(r['job'] as Map<String, dynamic>);
  }

  Future<List<String>> logs(String id) async {
    final r = await api.get('/api/builds/$id/logs');
    return (r['logs'] as List).map((e) => e.toString()).toList();
  }

  Future<BuildJob> retry(String id) async {
    final r = await api.post('/api/builds/$id/retry');
    return BuildJob.fromJson(r['job'] as Map<String, dynamic>);
  }

  /// Requests a short-lived signed link for THIS job and opens it.
  Future<void> download(BuildJob job) async {
    if (!job.hasApk) throw const ApiException('artifact_missing');
    final r = await api.post('/api/builds/${job.id}/download-link');
    final url = Uri.parse(r['url'] as String);
    final expected = Uri.parse(api.settings.backendUrl);
    if (url.host != expected.host) throw const ApiException('download_failed');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok) throw const ApiException('download_failed');
  }
}
