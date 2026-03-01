// lib/screens/auth/splash_screen.dart
// On launch:
//  - Checks SharedPreferences for stored role
//  - If role == 'parent'  and Firebase Auth session exists → ParentDashboard
//  - If role == 'child'   and link_id stored              → ChildActiveScreen
//  - Otherwise                                            → LoginScreen

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/app_theme.dart';
import 'login_screen.dart';
import '../parent/dashboard_screen.dart';
import '../child/child_active_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
    Future.delayed(const Duration(seconds: 2), _route);
  }

  Future<void> _route() async {
    if (!mounted) return;
    final prefs  = await SharedPreferences.getInstance();
    final role   = prefs.getString('role');       // 'parent' | 'child' | null
    final linkId = prefs.getString('link_id');    // set after child pairing

    if (role == 'parent' && FirebaseAuth.instance.currentUser != null) {
      _go(const ParentDashboardScreen());
    } else if (role == 'child' && linkId != null) {
      _go(const ChildActiveScreen());
    } else {
      _go(const LoginScreen());
    }
  }

  void _go(Widget screen) {
    if (!mounted) return;
    Navigator.pushReplacement(
        context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield_outlined,
                  size: 56, color: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text('SafeChild',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2)),
            const SizedBox(height: 6),
            Text('Smart Parental Control System',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.75), fontSize: 13)),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2),
          ]),
        ),
      ),
    );
  }
}