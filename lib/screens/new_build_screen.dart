import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/localization.dart';
import '../app/services_scope.dart';
import '../models/project_model.dart';
import '../widgets/mango_button.dart';
import 'customization_screen.dart';

class NewBuildScreen extends StatefulWidget {
  const NewBuildScreen({super.key, required this.services, this.autoPick = false});
  final AppServices services;
  final bool autoPick;

  @override
  State<NewBuildScreen> createState() => _NewBuildScreenState();
}

class _NewBuildScreenState extends State<NewBuildScreen> {
  ImportReport? _report;
  Uint8List? _bytes;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPick) WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
    final path = res?.files.single.path;
    if (path == null) return;
    setState(() => _busy = true);
    try {
      final file = File(path);
      if (!await file.exists()) throw const FileSystemException('missing');
      final len = await file.length();
      final limit = widget.services.settings.maxZipMb * 1024 * 1024;
      final name = res!.files.single.name;
      if (len > limit) {
        setState(() {
          _bytes = null;
          _report = ImportReport(fileName: name, sizeBytes: len, type: ProjectType.unknown, issues: ['حجم الملف يتجاوز الحد المسموح (${widget.services.settings.maxZipMb} MB)']);
        });
        return;
      }
      final bytes = await file.readAsBytes();
      final report = widget.services.importer.analyze(name, bytes, maxZipMb: widget.services.settings.maxZipMb);
      setState(() {
        _bytes = report.ok ? bytes : null;
        _report = report;
      });
    } catch (_) {
      setState(() {
        _bytes = null;
        _report = ImportReport(fileName: path.split('/').last, sizeBytes: 0, type: ProjectType.unknown, issues: ['تعذر قراءة الملف']);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _size(int b) => b > 1048576 ? '${(b / 1048576).toStringAsFixed(1)} MB' : '${(b / 1024).toStringAsFixed(0)} KB';

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      appBar: AppBar(title: Text(L.t('new_build'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        MangoButton(label: L.t('pick_zip'), icon: Icons.folder_zip_outlined, loading: _busy, onPressed: _pick),
        const SizedBox(height: 16),
        if (r != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _row(L.t('file_name'), r.fileName),
                _row(L.t('file_size'), _size(r.sizeBytes)),
                _row(L.t('project_type'), L.t(r.type.l10nKey)),
                const Divider(height: 24),
                Text(L.t('scan_result'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (r.ok)
                  Text(L.t('scan_ok'), style: const TextStyle(color: Color(0xFF3FB950)))
                else
                  ...r.issues.map((i) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $i', style: const TextStyle(color: Color(0xFFF85149))),
                      )),
              ]),
            ),
          ),
        const SizedBox(height: 16),
        if (r != null && r.ok && _bytes != null)
          MangoButton(
            label: L.t('next'),
            icon: Icons.arrow_forward,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CustomizationScreen(services: widget.services, report: r, zipBytes: _bytes!)),
            ),
          ),
      ]),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: Theme.of(context).textTheme.bodySmall),
          Flexible(child: Text(v, overflow: TextOverflow.ellipsis)),
        ]),
      );
}
