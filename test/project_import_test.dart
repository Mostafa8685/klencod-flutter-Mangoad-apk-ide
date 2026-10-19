import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mango_apk_studio/models/project_model.dart';
import 'package:mango_apk_studio/services/project_import_service.dart';

Uint8List zipOf(Map<String, String> files) {
  final a = Archive();
  files.forEach((n, c) => a.addFile(ArchiveFile(n, utf8.encode(c).length, utf8.encode(c))));
  return Uint8List.fromList(ZipEncoder().encode(a)!);
}

void main() {
  final svc = ProjectImportService();

  test('detects project types', () {
    expect(detectProjectType(['pubspec.yaml', 'lib/main.dart']), ProjectType.flutter);
    expect(detectProjectType(['proj/pubspec.yaml', 'proj/lib/main.dart']), ProjectType.flutter);
    expect(detectProjectType(['app/build.gradle', 'app/src/main/AndroidManifest.xml']), ProjectType.nativeAndroid);
    expect(detectProjectType(['index.html']), ProjectType.web);
    expect(detectProjectType(['readme.txt']), ProjectType.unknown);
  });

  test('accepts a valid flutter zip', () {
    final r = svc.analyze('app.zip', zipOf({'pubspec.yaml': 'name: a', 'lib/main.dart': 'void main(){}'}));
    expect(r.ok, isTrue);
    expect(r.type, ProjectType.flutter);
  });

  test('rejects path traversal', () {
    final r = svc.analyze('bad.zip', zipOf({'../evil.sh': 'x', 'pubspec.yaml': 'n', 'lib/a.dart': ''}));
    expect(r.ok, isFalse);
    expect(r.issues.join(), contains('مسار خطير'));
  });

  test('rejects invalid zip, wrong extension and oversize', () {
    expect(svc.analyze('x.zip', Uint8List.fromList([1, 2, 3, 4])).ok, isFalse);
    expect(svc.analyze('x.rar', zipOf({'a': 'b'})).ok, isFalse);
    final big = zipOf({'pubspec.yaml': 'n', 'lib/a.dart': 'x' * 2000000});
    expect(svc.analyze('x.zip', big, maxZipMb: 0).ok, isFalse);
  });

  test('unsupported project explains why', () {
    final r = svc.analyze('x.zip', zipOf({'readme.txt': 'hi'}));
    expect(r.ok, isFalse);
    expect(r.issues, isNotEmpty);
  });
}
