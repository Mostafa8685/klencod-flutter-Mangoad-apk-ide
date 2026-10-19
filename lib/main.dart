import 'package:flutter/material.dart';
import 'app/app.dart';
import 'app/services_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create();
  runApp(MangoApp(services: services));
}