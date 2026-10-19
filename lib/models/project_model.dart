enum ProjectType {
  flutter,
  nativeAndroid,
  web,
  unknown;

  String get apiName => switch (this) {
        ProjectType.flutter => 'flutter',
        ProjectType.nativeAndroid => 'native',
        ProjectType.web => 'web',
        ProjectType.unknown => 'unknown',
      };

  String get l10nKey => switch (this) {
        ProjectType.flutter => 'type_flutter',
        ProjectType.nativeAndroid => 'type_native',
        ProjectType.web => 'type_web',
        ProjectType.unknown => 'type_unknown',
      };
}

class ImportReport {
  final String fileName;
  final int sizeBytes;
  final ProjectType type;
  final List<String> issues;

  const ImportReport({
    required this.fileName,
    required this.sizeBytes,
    required this.type,
    required this.issues,
  });

  bool get ok => issues.isEmpty;
}

class RecentProject {
  final String name;
  final String type;
  final DateTime at;
  const RecentProject(this.name, this.type, this.at);

  Map<String, dynamic> toJson() => {'name': name, 'type': type, 'at': at.toIso8601String()};
  factory RecentProject.fromJson(Map<String, dynamic> j) => RecentProject(
        j['name'] as String,
        j['type'] as String,
        DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      );
}
