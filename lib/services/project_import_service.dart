import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/validators.dart';
import '../models/project_model.dart';

ProjectType detectProjectType(Iterable<String> paths) {
  final p = paths.map((e) => e.replaceAll('\\', '/')).toList();
  bool has(bool Function(String) f) => p.any(f);
  bool isRoot(String f, String name) {
    final parts = f.split('/');
    return parts.last == name && parts.length <= 2;
  }

  if (has((f) => isRoot(f, 'pubspec.yaml')) && has((f) => f.endsWith('.dart'))) {
    return ProjectType.flutter;
  }
  final gradle = has((f) => f.endsWith('build.gradle') || f.endsWith('build.gradle.kts'));
  if (gradle && has((f) => f.endsWith('AndroidManifest.xml'))) return ProjectType.nativeAndroid;
  if (has((f) => f.endsWith('index.html'))) return ProjectType.web;
  return ProjectType.unknown;
}

class ProjectImportService {
  static const maxEntries = 20000;
  static const maxTotalBytes = 1024 * 1024 * 1024;
  static const maxSingleFile = 500 * 1024 * 1024;
  static const maxRatio = 200;

  /// Inspects the archive in memory only. Nothing is ever extracted to disk.
  ImportReport analyze(String fileName, Uint8List bytes, {int maxZipMb = 100}) {
    final issues = <String>[];
    if (!fileName.toLowerCase().endsWith('.zip')) issues.add('امتداد الملف يجب أن يكون .zip');
    if (bytes.isEmpty) issues.add('الملف فارغ');
    if (bytes.length > maxZipMb * 1024 * 1024) issues.add('حجم الملف يتجاوز الحد المسموح ($maxZipMb MB)');
    if (issues.isNotEmpty) {
      return ImportReport(fileName: fileName, sizeBytes: bytes.length, type: ProjectType.unknown, issues: issues);
    }

    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return ImportReport(
        fileName: fileName,
        sizeBytes: bytes.length,
        type: ProjectType.unknown,
        issues: ['تعذر قراءة الأرشيف (ZIP غير صالح)'],
      );
    }

    if (archive.length > maxEntries) issues.add('عدد الملفات داخل الأرشيف كبير بصورة غير طبيعية');
    var total = 0;
    final names = <String>[];
    for (final f in archive) {
      if (!isSafeZipPath(f.name)) {
        issues.add('مسار خطير داخل الأرشيف: ${f.name}');
        break;
      }
      if (f.isSymbolicLink) {
        issues.add('الأرشيف يحتوي رابطًا رمزيًا: ${f.name}');
        break;
      }
      total += f.size;
      if (f.size > maxSingleFile) {
        issues.add('ملف ضخم جدًا داخل الأرشيف: ${f.name}');
        break;
      }
      names.add(f.name);
    }
    if (total > maxTotalBytes) issues.add('الحجم بعد الفك يتجاوز الحد المسموح');
    if (bytes.isNotEmpty && total / bytes.length > maxRatio) {
      issues.add('نسبة الضغط غير طبيعية (احتمال قنبلة ضغط)');
    }

    final type = detectProjectType(names);
    if (issues.isEmpty && type == ProjectType.unknown) {
      issues.add('نوع المشروع غير مدعوم أو الملفات ناقصة');
    }
    if (issues.isEmpty && type == ProjectType.web) {
      issues.add('مشاريع HTML/CSS/JS غير مدعومة في مسار البناء الحالي (لم يُنفذ مسار Capacitor بعد)');
    }
    return ImportReport(fileName: fileName, sizeBytes: bytes.length, type: type, issues: issues);
  }
}
