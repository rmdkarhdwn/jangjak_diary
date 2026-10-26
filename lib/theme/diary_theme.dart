import 'package:flutter/material.dart';

abstract final class DiaryTheme {
  static const cream = Color(0xFFF4EDE1);
  static const ink = Color(0xFF514C5D);
  static const background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF5C5C70), Color(0xFF79788A)],
  );

  static const title = TextStyle(
    fontFamily: 'NotoSerifKR',
    fontSize: 32,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: -1,
    color: cream,
  );

  static ThemeData get data => ThemeData(
    useMaterial3: true,
    fontFamily: 'NotoSansKR',
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF706C83),
      surface: cream,
      onSurface: ink,
    ),
    scaffoldBackgroundColor: const Color(0xFF5C5C70),
    textTheme: ThemeData.light().textTheme.apply(
      fontFamily: 'NotoSansKR',
      bodyColor: ink,
      displayColor: ink,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: .42),
      contentPadding: const EdgeInsets.all(18),
      hintStyle: TextStyle(color: ink.withValues(alpha: .45), fontSize: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: ink.withValues(alpha: .16)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: ink.withValues(alpha: .16)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        backgroundColor: ink,
        foregroundColor: cream,
        textStyle: const TextStyle(
          fontFamily: 'NotoSansKR',
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
  );
}
