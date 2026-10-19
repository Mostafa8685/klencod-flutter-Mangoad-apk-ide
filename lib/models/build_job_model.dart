enum BuildStage {
  waiting,
  preparing,
  validating,
  installing,
  building,
  uploading,
  completed,
  failed;

  /// Unknown server values fall back to [waiting], never to success.
  static BuildStage parse(String? v) {
    for (final s in BuildStage.values) {
      if (s.name == v) return s;
    }
    return BuildStage.waiting;
  }

  bool get isFinal => this == completed || this == failed;
}

class BuildJob {
  final String id;
  final String projectName;
  final String projectType;
  final String packageName;
  final String versionName;
  final String buildType;
  final BuildStage stage;
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final String? apkName;
  final int? apkSize;
  final String? error;

  const BuildJob({
    required this.id,
    required this.projectName,
    required this.projectType,
    required this.packageName,
    required this.versionName,
    required this.buildType,
    required this.stage,
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.apkName,
    this.apkSize,
    this.error,
  });

  /// Downloadable only when the server reports a real, non-empty APK.
  bool get hasApk => stage == BuildStage.completed && apkName != null && (apkSize ?? 0) > 0;

  factory BuildJob.fromJson(Map<String, dynamic> j) {
    DateTime? d(dynamic v) => v == null ? null : DateTime.tryParse(v as String);
    return BuildJob(
      id: j['id'] as String,
      projectName: (j['projectName'] ?? '') as String,
      projectType: (j['projectType'] ?? 'unknown') as String,
      packageName: (j['packageName'] ?? '') as String,
      versionName: (j['versionName'] ?? '') as String,
      buildType: (j['buildType'] ?? 'debug') as String,
      stage: BuildStage.parse(j['stage'] as String?),
      createdAt: d(j['createdAt']) ?? DateTime.now(),
      startedAt: d(j['startedAt']),
      finishedAt: d(j['finishedAt']),
      apkName: j['apkName'] as String?,
      apkSize: (j['apkSize'] as num?)?.toInt(),
      error: j['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'projectName': projectName,
        'projectType': projectType,
        'packageName': packageName,
        'versionName': versionName,
        'buildType': buildType,
        'stage': stage.name,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'apkName': apkName,
        'apkSize': apkSize,
        'error': error,
      };
}
