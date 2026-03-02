// lib/screens/child/permission_setup_screen.dart
// Simple permission setup wizard.
// Each step: Allow button (opens settings) + Skip for now button — always visible.
// No forced verification checks. Parent/child decides.
// After all 5 steps actioned (granted or skipped) → ChildActiveScreen.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/pairing_service.dart';
import '../../utils/app_theme.dart';
import '../auth/register_screen.dart';
import 'child_active_screen.dart';

class _PermStep {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final String   reason;
  final _PermType type;
  final String   firestoreKey;
  const _PermStep({
    required this.icon, required this.title, required this.subtitle,
    required this.reason, required this.type, required this.firestoreKey,
  });
}

enum _PermType { notification, systemAlertWindow, usageAccess, accessibility, deviceAdmin }
enum _StepStatus { idle, granted, skipped }

const _steps = [
  _PermStep(
    icon: Icons.notifications_active_outlined, title: 'Notifications',
    subtitle: 'Module 4 — Alert System',
    reason: 'Allows SafeChild to send real-time safety alerts to this device.',
    type: _PermType.notification, firestoreKey: 'notifications',
  ),
  _PermStep(
    icon: Icons.layers_outlined, title: 'Display Over Other Apps',
    subtitle: 'Module 3 — Anti-Bypass',
    reason: 'Allows SafeChild to show intervention screens over other apps.',
    type: _PermType.systemAlertWindow, firestoreKey: 'overlay',
  ),
  _PermStep(
    icon: Icons.bar_chart_outlined, title: 'Usage Access',
    subtitle: 'Module 3 — App Monitoring',
    reason: 'Allows SafeChild to track app usage and screen time.',
    type: _PermType.usageAccess, firestoreKey: 'usage_access',
  ),
  _PermStep(
    icon: Icons.accessibility_new_outlined, title: 'Accessibility Service',
    subtitle: 'Modules 2 & 3 — Content Detection',
    reason: 'Allows SafeChild to read on-screen text for AI content analysis.',
    type: _PermType.accessibility, firestoreKey: 'accessibility',
  ),
  _PermStep(
    icon: Icons.admin_panel_settings_outlined, title: 'Device Administrator',
    subtitle: 'Module 3 — Anti-Bypass',
    reason: 'Prevents SafeChild from being uninstalled without parent approval.',
    type: _PermType.deviceAdmin, firestoreKey: 'device_admin',
  ),
];

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});
  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen> {
  final _pairingService = PairingService();
  StreamSubscription<DocumentSnapshot>? _linkSub;

  String? _linkId;
  String? _deviceId;
  int  _current = 0;
  bool _loading = false;
  final _status = List<_StepStatus>.filled(5, _StepStatus.idle);

  @override
  void initState() {
    super.initState();
    _loadIds();
  }

  Future<void> _loadIds() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _linkId   = prefs.getString('link_id');
      _deviceId = prefs.getString('device_id');
    });
    _startLinkWatcher();
  }

  void _startLinkWatcher() {
    if (_linkId == null) return;
    _linkSub = FirebaseFirestore.instance
        .collection('parent_child_links')
        .doc(_linkId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final linkStatus    = doc.data()?['link_status']    as String?;
      final pairingStatus = doc.data()?['pairing_status'] as String?;
      if (linkStatus == 'removed' || pairingStatus == 'expired') _kickOut();
    });
  }

  Future<void> _kickOut() async {
    await _linkSub?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('role');
    await prefs.remove('link_id');
    await prefs.remove('device_id');
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

  Future<void> _grant() async {
    setState(() => _loading = true);
    try {
      switch (_steps[_current].type) {
        case _PermType.notification:
          await Permission.notification.request();
          break;
        default:
          await openAppSettings();
          break;
      }
      _apply(_StepStatus.granted);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _skip() => _apply(_StepStatus.skipped);

  void _apply(_StepStatus s) {
    setState(() => _status[_current] = s);
    if (s == _StepStatus.granted && _linkId != null && _deviceId != null) {
      _pairingService.updatePermissionGranted(
        linkId:        _linkId!,
        deviceId:      _deviceId!,
        stepIndex:     _current,
        permissionKey: _steps[_current].firestoreKey,
      ).catchError((_) {});
    }
  }

  void _next() {
    if (_current < _steps.length - 1) {
      setState(() => _current++);
    } else {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ChildActiveScreen()),
        (_) => false,
      );
    }
  }

  bool get _isDone => _status[_current] != _StepStatus.idle;

  @override
  Widget build(BuildContext context) {
    final step   = _steps[_current];
    final total  = _steps.length;
    final status = _status[_current];
    final isLast = _current == total - 1;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [

          // Progress header
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.shield, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Text('SafeChild Setup',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const Spacer(),
                Text('${_current + 1} of $total',
                    style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (_current + 1) / total,
                  minHeight: 6,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(total, (i) {
                  final done   = _status[i] == _StepStatus.granted;
                  final active = i == _current;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: active ? 20 : 8, height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: done ? AppColors.statusLinked
                          : active ? AppColors.primary : AppColors.divider,
                    ),
                  );
                }),
              ),
            ]),
          ),

          // Step content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(children: [

                // Icon
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    key: ValueKey(_current),
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      color: status == _StepStatus.granted
                          ? AppColors.statusLinked.withOpacity(0.1)
                          : AppColors.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      status == _StepStatus.granted ? Icons.check_circle : step.icon,
                      size: 50,
                      color: status == _StepStatus.granted
                          ? AppColors.statusLinked : AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    key: ValueKey('t$_current'),
                    step.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: 6),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(step.subtitle,
                      style: const TextStyle(fontSize: 11,
                          color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(step.reason,
                          style: const TextStyle(fontSize: 13,
                              color: AppColors.textSub, height: 1.55)),
                    ),
                  ]),
                ),

                const SizedBox(height: 16),

                // Status chip
                if (status == _StepStatus.granted)
                  _chip(Icons.check_circle, 'Granted', AppColors.statusLinked)
                else if (status == _StepStatus.skipped)
                  _chip(Icons.skip_next, 'Skipped', AppColors.statusPending),
              ]),
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(children: [

              if (!_isDone) ...[
                // Allow button
                ElevatedButton(
                  onPressed: _loading ? null : _grant,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Allow ${step.title}'),
                ),
                const SizedBox(height: 10),
                // Skip always visible
                TextButton(
                  onPressed: _skip,
                  child: const Text('Skip for now',
                      style: TextStyle(color: AppColors.textSub)),
                ),
              ] else ...[
                // Next / Finish after actioned
                ElevatedButton(
                  onPressed: _next,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(isLast ? 'Start Monitoring' : 'Next'),
                    const SizedBox(width: 6),
                    Icon(isLast ? Icons.shield : Icons.arrow_forward, size: 16),
                  ]),
                ),
              ],

            ]),
          ),

        ]),
      ),
    );
  }

  Widget _chip(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: color,
              fontWeight: FontWeight.w600)),
        ]),
      );
}