import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/build_job_model.dart';
import '../models/project_model.dart';

const String kDefaultBackendUrl = String.fromEnvironment('BACKEND_URL', defaultValue: '');
const String kAppVersion = '1.0.0';

class SettingsService extends ChangeNotifier {
  SettingsService._(this._p);
  final SharedPreferences _p;

  static Future<SettingsService> load() async =>
      SettingsService._(await SharedPreferences.getInstance());

  bool get darkMode => _p.getBool('dark') ?? true;
  String get language => _p.getString('lang') ?? 'ar';
  int get maxZipMb => _p.getInt('maxZipMb') ?? 100;
  String get backendUrl => _p.getString('backend') ?? kDefaultBackendUrl;
  String? get sessionToken => _p.getString('session');
  bool get githubConnected => _p.getBool('ghConnected') ?? false;
  String? get githubLogin => _p.getString('ghLogin');

  String get deviceId {
    var id = _p.getString('deviceId');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
      _p.setString('deviceId', id);
    }
    return id;
  }

  Future<void> setDark(bool v) async {
    await _p.setBool('dark', v);
    notifyListeners();
  }

  Future<void> setLanguage(String v) async {
    await _p.setString('lang', v);
    notifyListeners();
  }

  Future<void> setMaxZipMb(int v) async {
    await _p.setInt('maxZipMb', v.clamp(1, 500));
    notifyListeners();
  }

  Future<void> setBackendUrl(String v) async {
    await _p.setString('backend', v.trim());
    await _p.remove('session');
    await _p.setBool('ghConnected', false);
    notifyListeners();
  }

  Future<void> setSession(String? t) async {
    t == null ? await _p.remove('session') : await _p.setString('session', t);
  }

  Future<void> setGithub(bool connected, {String? login}) async {
    await _p.setBool('ghConnected', connected);
    login == null || !connected ? await _p.remove('ghLogin') : await _p.setString('ghLogin', login);
    notifyListeners();
  }

  List<BuildJob> get history {
    final raw = _p.getString('history');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => BuildJob.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> upsertJob(BuildJob job) async {
    final list = history.where((j) => j.id != job.id).toList()..insert(0, job);
    await _p.setString('history', jsonEncode(list.take(50).map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  List<RecentProject> get recentProjects {
    final raw = _p.getString('recent');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => RecentProject.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> addRecent(RecentProject r) async {
    final list = recentProjects.where((e) => e.name != r.name).toList()..insert(0, r);
    await _p.setString('recent', jsonEncode(list.take(10).map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  ThemeMode get themeMode => darkMode ? ThemeMode.dark : ThemeMode.light;
}
