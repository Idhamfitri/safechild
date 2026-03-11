// lib/utils/app_theme.dart

import 'package:flutter/material.dart';

class AppColors {
  static const Color primary       = Color(0xFF1A7F64);
  static const Color primaryDark   = Color(0xFF12614C);
  static const Color accent        = Color(0xFF3ECFA0);
  static const Color background    = Color(0xFFF5F9F7);
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color error         = Color(0xFFD32F2F);
  static const Color textPrimary   = Color(0xFF1C2B25);
  static const Color textSub       = Color(0xFF6B7C74);
  static const Color divider       = Color(0xFFDDE6E2);
  static const Color statusPending = Color(0xFFF9A825);
  static const Color statusLinked  = Color(0xFF1A7F64);
  static const Color statusExpired = Color(0xFFD32F2F);
}

class AppTheme {
  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary:   AppColors.primary,
          secondary: AppColors.accent,
          error:     AppColors.error,
          surface:   AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            textStyle: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.error),
          ),
          labelStyle: const TextStyle(color: AppColors.textSub),
        ),
       
        cardTheme: CardThemeData(
          color: AppColors.surface,
          elevation: 2,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
        ),
        useMaterial3: true,
      );
}