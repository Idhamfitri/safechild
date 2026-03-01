// lib/main.dart
// SafeChild — Single Flutter Application
// Handles both Parent and Child Device roles.

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/auth/splash_screen.dart';
import 'utils/app_theme.dart';

import 'firebase_options.dart';



void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
     options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const SafeChildApp());
}

class SafeChildApp extends StatelessWidget {
  const SafeChildApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeChild',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}