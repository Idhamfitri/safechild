// lib/screens/child/child_active_screen.dart
// On init: directly writes setup_phase = 'active' to Firestore using linkId.
// This is the ONLY thing the parent is waiting for.
// Also listens for parent unlink → clears session → RegisterScreen.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/app_theme.dart';
import '../auth/register_screen.dart';

class ChildActiveScreen extends StatefulWidget {
  const ChildActiveScreen({super.key});

  @override
  State<ChildActiveScreen> createState() => _ChildActiveScreenState();
}

class _ChildActiveScreenState extends State<ChildActiveScreen> {
  StreamSubscription<DocumentSnapshot>? _linkSub;
  bool _unlinking = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs  = await SharedPreferences.getInstance();
    final linkId = prefs.getString('link_id');

    if (linkId == null) {
      _forceLogout();
      return;
    }

    // ── Step 1: Mark setup_phase = active so parent navigates ──────────────
    // This is all the parent is waiting for. Simple direct write.
    try {
      await FirebaseFirestore.instance
          .collection('parent_child_links')
          .doc(linkId)
          .update({'setup_phase': 'active'});
    } catch (e) {
      // If write fails, retry once after 2 seconds
      await Future.delayed(const Duration(seconds: 2));
      try {
        await FirebaseFirestore.instance
            .collection('parent_child_links')
            .doc(linkId)
            .update({'setup_phase': 'active'});
      } catch (_) {}
    }

    // ── Step 2: Listen for parent unlinking ────────────────────────────────
    _linkSub = FirebaseFirestore.instance
        .collection('parent_child_links')
        .doc(linkId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (!doc.exists) { _forceLogout(); return; }
      final linkStatus    = doc.data()?['link_status']    as String?;
      final pairingStatus = doc.data()?['pairing_status'] as String?;
      if (linkStatus == 'removed' || pairingStatus == 'expired') {
        _forceLogout();
      }
    }, onError: (_) {});
  }

  Future<void> _forceLogout() async {
    if (_unlinking || !mounted) return;
    setState(() => _unlinking = true);

    await _linkSub?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('role');
    await prefs.remove('link_id');
    await prefs.remove('device_id');

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1), shape: BoxShape.circle),
            child: const Icon(Icons.link_off, size: 34, color: AppColors.error),
          ),
          const SizedBox(height: 16),
          const Text('Device Unlinked',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text(
            'The parent has removed this device from SafeChild. '
            'Monitoring has stopped.',
            style: TextStyle(fontSize: 13, color: AppColors.textSub, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
      (_) => false,
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(children: [
        SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 110, height: 110,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.shield, size: 62, color: AppColors.primary),
                ),
                const SizedBox(height: 28),
                const Text('SafeChild is Active',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
                const SizedBox(height: 12),
                const Text(
                  'This device is being monitored.\n'
                  'SafeChild runs silently in the background to keep you safe.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.textSub, height: 1.6),
                ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.circle, size: 10, color: AppColors.statusLinked),
                    SizedBox(width: 8),
                    Text('Monitoring Active',
                        style: TextStyle(color: AppColors.primary,
                            fontWeight: FontWeight.w600, fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 16),
                const Text('Background services will be enabled in Module 4.',
                    style: TextStyle(fontSize: 11, color: AppColors.textSub)),
              ]),
            ),
          ),
        ),
        if (_unlinking)
          Container(
            color: Colors.black38,
            child: const Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
      ]),
    );
  }
}