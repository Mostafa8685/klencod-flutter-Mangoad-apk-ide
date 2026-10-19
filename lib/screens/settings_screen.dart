import 'package:flutter/material.dart';

import '../app/localization.dart';
import '../app/services_scope.dart';
import '../services/api_client.dart';
import '../services/settings_service.dart';
import 'github_connect_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _url = TextEditingController(text: widget.services.settings.backendUrl);
  String? _urlError;

  Future<void> _saveUrl() async {
    final v = _url.text.trim();
    if (!isAcceptableBackendUrl(v)) {
      setState(() => _urlError = 'يجب أن يبدأ العنوان بـ https://');
      return;
    }
    // Any server other than the built-in default is untrusted until the user confirms.
    if (v != kDefaultBackendUrl) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(L.t('untrusted_backend')),
          content: Text(L.t('untrusted_body')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(L.t('cancel'))),
            TextButton(onPressed: () => Navigator.pop(c, true), child: Text(L.t('continue'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    await widget.services.settings.setBackendUrl(v);
    if (mounted) setState(() => _urlError = null);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.services.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(L.t('settings'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          ListTile(
            title: Text(L.t('language')),
            trailing: DropdownButton<String>(
              value: s.language,
              underline: const SizedBox(),
              items: const [DropdownMenuItem(value: 'ar', child: Text('العربية')), DropdownMenuItem(value: 'en', child: Text('English'))],
              onChanged: (v) => v == null ? null : s.setLanguage(v),
            ),
          ),
          SwitchListTile(title: Text(L.t('theme')), value: s.darkMode, onChanged: s.setDark),
          ListTile(
            title: Text(L.t('zip_limit')),
            subtitle: Slider(value: s.maxZipMb.toDouble(), min: 10, max: 500, divisions: 49, label: '${s.maxZipMb}', onChanged: (v) => s.setMaxZipMb(v.round())),
            trailing: Text('${s.maxZipMb}'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _url,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: L.t('backend_url'),
              errorText: _urlError,
              suffixIcon: IconButton(icon: const Icon(Icons.check), onPressed: _saveUrl, tooltip: L.t('save')),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.hub_outlined),
            title: Text(L.t('github_status')),
            subtitle: Text(s.githubConnected ? '${L.t('connected')}${s.githubLogin != null ? ' • ${s.githubLogin}' : ''}' : L.t('disconnected')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GithubConnectScreen(services: widget.services))),
          ),
          if (s.githubConnected)
            ListTile(
              leading: const Icon(Icons.link_off, color: Color(0xFFF85149)),
              title: Text(L.t('disconnect')),
              onTap: () async {
                try {
                  await widget.services.github.disconnect();
                } on ApiException catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
            ),
          const Divider(),
          ListTile(title: Text(L.t('developer')), trailing: Text(L.t('dev'))),
          ListTile(title: Text(L.t('version')), trailing: const Text(kAppVersion)),
          ListTile(
            title: Text(L.t('privacy')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showDialog(
              context: context,
              builder: (c) => AlertDialog(title: Text(L.t('privacy')), content: Text(L.t('privacy_body')), actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(L.t('close')))]),
            ),
          ),
        ]),
      ),
    );
  }
}
