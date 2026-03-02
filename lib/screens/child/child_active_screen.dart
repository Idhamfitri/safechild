// lib/screens/child/child_active_screen.dart
// UPDATED — Module 2:
//   1. Writes setup_phase = 'active' on init
//   2. Starts ContentDetectionService (Gemini text capture)
//   3. Writes heartbeat to Firestore every 10 minutes  ← THE FIX
//   4. Tracks accessibility + battery in each heartbeat
//   5. Listens for parent unlink

import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/content_detection_service.dart';
import '../../utils/app_theme.dart';
import '../auth/register_screen.dart';

class ChildActiveScreen extends StatefulWidget {
  const ChildActiveScreen({super.key});

  @override
  State<ChildActiveScreen> createState() => _ChildActiveScreenState();
}

class _ChildActiveScreenState extends State<ChildActiveScreen> {
  StreamSubscription<DocumentSnapshot>? _linkSub;
  Timer?  _heartbeatTimer;
  bool    _unlinking = false;
  String? _deviceId;
  String? _linkId;

  final _detectionService = ContentDetectionService();
  final _battery          = Battery();

  // How often to write a heartbeat — 10 minutes
  static const _heartbeatInterval = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _linkId    = prefs.getString('link_id');
    _deviceId  = prefs.getString('device_id');

    if (_linkId == null || _deviceId == null) {
      _forceLogout();
      return;
    }

    // ── Step 1: Mark setup_phase = active ──────────────────────────────────
    try {
      await FirebaseFirestore.instance
          .collection('parent_child_links')
          .doc(_linkId)
          .update({'setup_phase': 'active'});
    } catch (_) {
      await Future.delayed(const Duration(seconds: 2));
      try {
        await FirebaseFirestore.instance
            .collection('parent_child_links')
            .doc(_linkId)
            .update({'setup_phase': 'active'});
      } catch (_) {}
    }

    // ── Step 2: Start content detection (Module 2) ─────────────────────────
    await _detectionService.start();

    // ── Step 3: Write first heartbeat immediately, then every 10 minutes ───
    await _writeHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _writeHeartbeat());

    // ── Step 4: Listen for parent unlink ────────────────────────────────────
    _linkSub = FirebaseFirestore.instance
        .collection('parent_child_links')
        .doc(_linkId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      if (!doc.exists) { _forceLogout(); return; }
      final ls = doc.data()?['link_status']    as String?;
      final ps = doc.data()?['pairing_status'] as String?;
      if (ls == 'removed' || ps == 'expired') _forceLogout();
    }, onError: (_) {});
  }

  // ── Write one heartbeat document to Firestore ────────────────────────────
  Future<void> _writeHeartbeat() async {
    if (_deviceId == null) return;

    // Check accessibility permission status
    bool accessibilityOn = false;
    try {
      accessibilityOn =
          await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    } catch (_) {}

    // Get battery level
    int? batteryLevel;
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {}

    try {
      await FirebaseFirestore.instance.collection('heartbeat').add({
        'device_id':           _deviceId,
        'timestamp':           FieldValue.serverTimestamp(),
        'signal_status':       'active',
        'safechild_running':   true,
        'device_admin_active': false,     // Module 4 will update this
        'accessibility_active': accessibilityOn,
        if (batteryLevel != null) 'battery_level': batteryLevel,
      });
    } catch (_) {
      // Heartbeat write failed — not fatal, will retry next cycle
    }
  }

  Future<void> _forceLogout() async {
    if (_unlinking || !mounted) return;
    setState(() => _unlinking = true);

    _heartbeatTimer?.cancel();
    await _detectionService.stop();
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
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle),
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
    _heartbeatTimer?.cancel();
    _detectionService.stop();
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
                  child: const Icon(Icons.shield,
                      size: 62, color: AppColors.primary),
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
                  style: TextStyle(
                      fontSize: 14, color: AppColors.textSub, height: 1.6),
                ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(30),
                    border:
                        Border.all(color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.circle,
                        size: 10, color: AppColors.statusLinked),
                    SizedBox(width: 8),
                    Text('Monitoring Active',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ]),
                ),
                const SizedBox(height: 16),
                const Text(
                  'AI content detection is running.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSub),
                ),
              ]),
            ),
          ),
        ),
        if (_unlinking)
          Container(
            color: Colors.black38,
            child: const Center(
                child: CircularProgressIndicator(color: Colors.white)),
          ),
      ]),
    );
  }
}