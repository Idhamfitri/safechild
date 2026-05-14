import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/auth/splash_screen.dart';
import 'utils/app_theme.dart';
import 'firebase_options.dart';

// Top-level FCM handler — runs in a separate isolate when the app is
// backgrounded or killed. Android delivers high-priority FCM data messages
// even in Doze mode, so this is the fastest path when Firestore is throttled.
@pragma('vm:entry-point')
Future<void> _onFcmBackground(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final prefs = await SharedPreferences.getInstance();
  final type  = message.data['type'];

  if (type == 'lock_change') {
    final isLocked = message.data['is_locked'] == 'true';
    final lockedBy = message.data['locked_by'] ?? 'parent';
    await prefs.setBool('fcm_lock_pending', isLocked);
    // isManualLock = true for parent locks, false for schedule locks
    await prefs.setBool('fcm_lock_is_manual', lockedBy != 'schedule');
  } else if (type == 'device_unlinked') {
    // Clear credentials immediately so the app lands on RegisterScreen on next open
    await prefs.setBool('fcm_unlink_pending', true);
    await prefs.remove('role');
    await prefs.remove('link_id');
    await prefs.remove('device_id');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Must be registered before runApp so it is available when the system
  // delivers a background FCM message to a fresh isolate.
  FirebaseMessaging.onBackgroundMessage(_onFcmBackground);
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