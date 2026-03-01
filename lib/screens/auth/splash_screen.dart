// lib/screens/auth/splash_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// FIXED: For child role, verifies Firestore link_status BEFORE routing.
// If link_status is 'removed' or 'expired' — clears local storage and
// routes to RegisterScreen instead of ChildActiveScreen.
//
// This handles the case where the child app was closed when unlinked —
// on next launch it won't get stuck on the active screen.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/app_theme.dart';
import 'login_screen.dart';
import 'register_screen.dart';
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
  late Animation<double>   _fade;

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
    final role   = prefs.getString('role');
    final linkId = prefs.getString('link_id');

    // ── Parent role ────────────────────────────────────────────────────────
    if (role == 'parent' && FirebaseAuth.instance.currentUser != null) {
      _go(const ParentDashboardScreen());
      return;
    }

    // ── Child role ─────────────────────────────────────────────────────────
    if (role == 'child' && linkId != null && linkId.isNotEmpty) {
      // ✅ FIXED: Verify the link is still active in Firestore before routing.
      // This catches the case where the child app was closed during unlinking.
      final isStillLinked = await _verifyChildLink(linkId);

      if (isStillLinked) {
        _go(const ChildActiveScreen());
      } else {
        // Link was removed while app was closed — clear local data and
        // send to RegisterScreen so child can pair again if needed.
        await prefs.remove('role');
        await prefs.remove('link_id');
        _go(const RegisterScreen());
      }
      return;
    }

    // ── No valid session ───────────────────────────────────────────────────
    _go(const LoginScreen());
  }

  // ── Check Firestore link_status ───────────────────────────────────────────
  // Returns true only if document exists AND link_status == 'active'.
  Future<bool> _verifyChildLink(String linkId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('parent_child_links')
          .doc(linkId)
          .get();

      if (!doc.exists || doc.data() == null) return false;

      final linkStatus = doc.data()!['link_status'] as String?;
      return linkStatus == 'active';
    } catch (_) {
      // Network error — assume link is still valid to avoid logging
      // the child out due to a temporary connectivity issue.
      return true;
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
              width: 96, height: 96,
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
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 13)),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
                color: Colors.white, strokeWidth: 2),
          ]),
        ),
      ),
    );
  }
}