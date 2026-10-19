import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/localization.dart';
import '../app/services_scope.dart';
import '../core/validators.dart';
import '../models/build_job_model.dart';
import '../models/project_model.dart';
import '../services/api_client.dart';
import '../services/build_service.dart';
import '../widgets/mango_button.dart';
import 'build_status_screen.dart';

class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key, required this.services, required this.report, required this.zipBytes});
  final AppServices services;
  final ImportReport report;
  final Uint8List zipBytes;

  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.report.fileName.replaceAll(RegExp(r'\.zip$', caseSensitive: false), ''));
  final _pkg = TextEditingController(text: 'com.mango.app');
  final _vn = TextEditingController(text: '1.0.0');
  final _vc = TextEditingController(text: '1');
  late final _out = TextEditingController(text: 'app.apk');
  String _type = 'debug';
  Uint8List? _icon;
  String? _iconError;
  bool _busy = false;
  String? _error;

  Future<void> _pickIcon() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg']);
    final path = res?.files.single.path;
    if (path == null) return;
    final bytes = await File(path).readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      setState(() => _iconError = 'حجم الصورة يتجاوز 5MB');
      return;
    }
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final img = (await codec.getNextFrame()).image;
      final ok = img.width >= 512 && img.height >= 512 && (img.width / img.height - 1).abs() < 0.02;
      setState(() {
        _iconError = ok ? null : 'يجب أن تكون الصورة مربعة وبأبعاد 512x512 على الأقل';
        _icon = ok ? bytes : null;
      });
    } catch (_) {
      setState(() => _iconError = 'صيغة الصورة غير مدعومة');
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final req = BuildRequest(
        projectName: _name.text.trim(),
        projectType: widget.report.type.apiName,
        appName: _name.text.trim(),
        packageName: _pkg.text.trim(),
        versionName: _vn.text.trim(),
        versionCode: int.parse(_vc.text.trim()),
        buildType: _type,
        outputName: _out.text.trim(),
      );
      final BuildJob job = await widget.services.builds.create(req, widget.zipBytes, icon: _icon);
      await widget.services.settings.upsertJob(job);
      await widget.services.settings.addRecent(RecentProject(req.projectName, widget.report.type.apiName, DateTime.now()));
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => BuildStatusScreen(services: widget.services, jobId: job.id)));
    } on ApiException catch (e) {
      setState(() => _error = e.detail != null && e.status != null && e.status! < 500 ? '${e.message}\n${e.detail}' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(TextEditingController c, String label, bool Function(String) ok, {TextInputType? kb, bool ltr = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          keyboardType: kb,
          textDirection: ltr ? TextDirection.ltr : null,
          decoration: InputDecoration(labelText: label),
          validator: (v) => ok((v ?? '').trim()) ? null : L.t('invalid'),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L.t('customize'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          _field(_name, L.t('app_name'), isValidAppName),
          _field(_pkg, L.t('package_name'), isValidPackageName, ltr: true),
          _field(_vn, L.t('version_name'), isValidVersionName, ltr: true),
          _field(_vc, L.t('version_code'), isValidVersionCode, kb: TextInputType.number, ltr: true),
          _field(_out, L.t('output_name'), isValidOutputName, ltr: true),
          Text(L.t('build_type')),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'debug', label: Text('Debug')), ButtonSegment(value: 'release', label: Text('Release'))],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),
          Text(L.t('app_icon')),
          const SizedBox(height: 6),
          Row(children: [
            if (_icon != null)
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_icon!, width: 56, height: 56, fit: BoxFit.cover)),
            if (_icon != null) const SizedBox(width: 12),
            Expanded(child: MangoButton(label: L.t('pick_icon'), icon: Icons.image_outlined, outlined: true, onPressed: _pickIcon)),
          ]),
          if (_iconError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_iconError!, style: const TextStyle(color: Color(0xFFF85149)))),
          const SizedBox(height: 20),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: Color(0xFFF85149)))),
          MangoButton(label: L.t('start_build'), icon: Icons.rocket_launch_outlined, loading: _busy, onPressed: _submit),
        ]),
      ),
    );
  }
}
