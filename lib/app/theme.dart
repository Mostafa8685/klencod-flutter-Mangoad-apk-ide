import 'package:flutter/material.dart';

class MangoColors {
  static const orange = Color(0xFFFF9800);
  static const darkBg = Color(0xFF090D13);
  static const card = Color(0xFF151C26);
  static const border = Color(0xFF303B49);
  static const githubBlue = Color(0xFF388BFD);
}

class MangoTheme {
  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: MangoColors.orange,
      brightness: Brightness.dark,
    ).copyWith(primary: MangoColors.orange, onPrimary: Colors.black, surface: MangoColors.card);
    return _base(scheme, MangoColors.darkBg, MangoColors.card, MangoColors.border);
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: MangoColors.orange,
      brightness: Brightness.light,
    ).copyWith(primary: const Color(0xFFE68900));
    return _base(scheme, const Color(0xFFF7F8FA), Colors.white, const Color(0xFFDDE2E8));
  }

  static ThemeData _base(ColorScheme s, Color bg, Color card, Color border) {
    OutlineInputBorder ob() => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: s,
      scaffoldBackgroundColor: bg,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: s.onSurface,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: ob(),
        enabledBorder: ob(),
      ),
    );
  }
}
