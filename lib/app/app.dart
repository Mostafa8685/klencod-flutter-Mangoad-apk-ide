import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../screens/home_screen.dart';
import 'localization.dart';
import 'services_scope.dart';
import 'theme.dart';

class MangoApp extends StatelessWidget {
  const MangoApp({super.key, required this.services});
  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: services.settings,
      builder: (context, _) {
        final s = services.settings;
        L.lang = s.language;
        return MaterialApp(
          key: ValueKey(s.language),
          title: 'Mango APK Studio',
          debugShowCheckedModeBanner: false,
          theme: MangoTheme.light(),
          darkTheme: MangoTheme.dark(),
          themeMode: s.themeMode,
          locale: Locale(s.language),
          supportedLocales: const [Locale('ar'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: HomeScreen(services: services),
        );
      },
    );
  }
}
