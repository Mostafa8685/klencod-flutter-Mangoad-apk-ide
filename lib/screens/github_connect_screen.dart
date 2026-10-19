import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/localization.dart';
import '../app/services_scope.dart';
import '../app/theme.dart';
import '../models/github_auth_model.dart';
import '../services/api_client.dart';
import '../widgets/mango_button.dart';

const String kVerificationUrl = 'https://github.com/login/device';

class GithubConnectScreen extends StatefulWidget {
  const GithubConnectScreen({super.key, required this.services});
  final AppServices services;

  @override
  State<GithubConnectScreen> createState() => _GithubConnectScreenState();
}

class _GithubConnectScreenState extends State<GithubConnectScreen> {
  GithubAuthStatus _status = GithubAuthStatus.disconnected;
  DeviceCode? _code;
  String? _error;
  Timer? _timer;
  int _interval = 5;

  @override
  void initState() {
    super.initState();
    if (widget.services.settings.githubConnected) _status = GithubAuthStatus.connected;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _status = GithubAuthStatus.starting;
      _error = null;
    });
    try {
      final c = await widget.services.github.start();
      setState(() {
        _code = c;
        _interval = c.interval;
        _status = GithubAuthStatus.pending;
      });
      _schedule();
    } on ApiException catch (e) {
      setState(() {
        _status = GithubAuthStatus.error;
        _error = e.message;
      });
    }
  }

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(Duration(seconds: _interval), _poll);
  }

  Future<void> _poll() async {
    try {
      final r = await widget.services.github.status();
      if (!mounted) return;
      if (r.retryAfter != null) _interval = r.retryAfter!;
      setState(() => _status = r.status);
      if (r.status == GithubAuthStatus.pending) _schedule();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'authorization_pending') {
        _schedule();
      } else {
        setState(() {
          _status = GithubAuthStatus.error;
          _error = e.message;
        });
      }
    }
  }

  String get _statusText => switch (_status) {
        GithubAuthStatus.disconnected => L.t('conn_idle'),
        GithubAuthStatus.starting => L.t('conn_starting'),
        GithubAuthStatus.pending => L.t('conn_pending'),
        GithubAuthStatus.connected => L.t('conn_connected'),
        GithubAuthStatus.expired => L.t('conn_expired'),
        GithubAuthStatus.denied => L.t('conn_denied'),
        GithubAuthStatus.error => _error ?? L.t('conn_error'),
      };

  @override
  Widget build(BuildContext context) {
    final connected = _status == GithubAuthStatus.connected;
    final busy = _status == GithubAuthStatus.starting || _status == GithubAuthStatus.pending;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('MANGO / CONNECT',
              style: TextStyle(color: MangoColors.orange, letterSpacing: 2, fontWeight: FontWeight.w700, fontSize: 12)),
          const SizedBox(height: 8),
          Text(L.t('connect_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(L.t('connect_desc'), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(L.t('how_title'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 8),
                Text(L.t('how_body'), style: const TextStyle(height: 1.7)),
              ]),
            ),
          ),
          const SizedBox(height: 18),
          Row(children: [
            if (busy)
              const Padding(padding: EdgeInsets.only(left: 10, right: 10), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
            Expanded(child: Text(_statusText, style: TextStyle(color: connected ? const Color(0xFF3FB950) : null))),
          ]),
          const SizedBox(height: 12),
          if (_code != null && !connected) ...[
            Text(L.t('verify_code'), style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: MangoColors.border),
                color: Theme.of(context).cardTheme.color,
              ),
              alignment: Alignment.center,
              child: SelectableText(_code!.userCode,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 4)),
            ),
            const SizedBox(height: 10),
            MangoButton(
              label: L.t('copy_code'),
              icon: Icons.copy,
              outlined: true,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _code!.userCode));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L.t('copied'))));
                }
              },
            ),
            const SizedBox(height: 10),
            MangoButton(
              label: L.t('open_verify'),
              icon: Icons.open_in_new,
              color: MangoColors.githubBlue,
              onPressed: () => launchUrl(Uri.parse(_code!.verificationUri.isNotEmpty ? _code!.verificationUri : kVerificationUrl),
                  mode: LaunchMode.externalApplication),
            ),
            const SizedBox(height: 10),
          ],
          if (!connected)
            MangoButton(label: L.t('start_login'), icon: Icons.login, loading: busy && _code == null, onPressed: busy ? null : _start),
          if (connected)
            MangoButton(
              label: L.t('disconnect'),
              icon: Icons.link_off,
              outlined: true,
              color: const Color(0xFFF85149),
              onPressed: () async {
                try {
                  await widget.services.github.disconnect();
                  if (mounted) setState(() => _status = GithubAuthStatus.disconnected);
                } on ApiException catch (e) {
                  if (mounted) setState(() => _error = e.message);
                }
              },
            ),
          const SizedBox(height: 10),
          MangoButton(label: L.t('close'), outlined: true, color: Colors.grey, onPressed: () => Navigator.pop(context)),
        ],
      ),
    );
  }
}
