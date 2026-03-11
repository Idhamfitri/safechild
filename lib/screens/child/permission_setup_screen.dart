// lib/screens/child/permission_setup_screen.dart
import 'dart:async';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/native_channel_service.dart';
import '../../services/pairing_service.dart';
import '../../utils/app_theme.dart';
import '../auth/register_screen.dart';
import 'child_active_screen.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';

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

enum _PermType {
  notification,
  systemAlertWindow,
  usageAccess,
  accessibility,
}

enum _StepStatus { idle, granted, denied, skipped }

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
];

class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen>
    with WidgetsBindingObserver {

  final _pairingService = PairingService();
  StreamSubscription<DocumentSnapshot>? _linkSub;

  String? _linkId;
  String? _deviceId;
  int     _current = 0;
  bool    _loading = false;
  bool    _waitingForSettings = false;

  final _status = List<_StepStatus>.filled(4, _StepStatus.idle);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadIds();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSub?.cancel();
    super.dispose();
  }

  // ── Detect return from system settings page ────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _waitingForSettings) {
      _waitingForSettings = false;
      _recheckCurrentPermission();
    }
  }

  Future<void> _loadIds() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _linkId   = prefs.getString('link_id');
      _deviceId = prefs.getString('device_id');
    });
    _startLinkWatcher();
    _recheckAllPermissions();
  }

  void _startLinkWatcher() {
    if (_linkId == null) return;
    _linkSub = FirebaseFirestore.instance
        .collection('parent_child_links')
        .doc(_linkId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final ls = doc.data()?['link_status']    as String?;
      final ps = doc.data()?['pairing_status'] as String?;
      if (ls == 'removed' || ps == 'expired') _kickOut();
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

  // ── Real permission check for a given type ─────────────────────────────
  Future<bool> _checkPermission(_PermType type) async {
    switch (type) {
      case _PermType.notification:
        return await Permission.notification.isGranted;
      case _PermType.systemAlertWindow:
        return await Permission.systemAlertWindow.isGranted;
      case _PermType.usageAccess:
        try {
          return await NativeChannelService.checkUsageAccessGranted();
        } catch (_) {
          return false;
        }
      case _PermType.accessibility:
        return await FlutterAccessibilityService.isAccessibilityPermissionEnabled() ?? false;
    }
  }

  // ── Re-check current step after returning from settings ───────────────
  Future<void> _recheckCurrentPermission() async {
    if (_status[_current] == _StepStatus.skipped) return;
    setState(() => _loading = true);

    final granted = await _checkPermission(_steps[_current].type);

    if (granted) {
      _applyStatus(_current, _StepStatus.granted);
    } else {
      _applyStatus(_current, _StepStatus.denied);
    }

    if (mounted) setState(() => _loading = false);
  }

  // ── Check all permissions on initial load ─────────────────────────────
  Future<void> _recheckAllPermissions() async {
    for (int i = 0; i < _steps.length; i++) {
      final granted = await _checkPermission(_steps[i].type);
      if (granted && _status[i] != _StepStatus.skipped) {
        _applyStatus(i, _StepStatus.granted);
      }
    }
    if (mounted) setState(() {});
  }

  // ── Open settings and wait for return ─────────────────────────────────
  Future<void> _grant() async {
    setState(() => _loading = true);

    try {
      switch (_steps[_current].type) {

        case _PermType.notification:
          final result = await Permission.notification.request();
          if (result.isGranted) {
            _applyStatus(_current, _StepStatus.granted);
          } else {
            _applyStatus(_current, _StepStatus.denied);
          }
          break;

        case _PermType.systemAlertWindow:
          // Must go to system settings — set flag to recheck on return
          _waitingForSettings = true;
          const AndroidIntent(
            action: 'android.settings.action.MANAGE_OVERLAY_PERMISSION',
          ).launch();
          break;

        case _PermType.usageAccess:
          _waitingForSettings = true;
          const AndroidIntent(
            action: 'android.settings.USAGE_ACCESS_SETTINGS',
          ).launch();
          break;

        case _PermType.accessibility:
          _waitingForSettings = true;
          await FlutterAccessibilityService.requestAccessibilityPermission();
          break;
      }
    } catch (_) {
      _waitingForSettings = true;
      await openAppSettings();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _skip() {
    _applyStatus(_current, _StepStatus.skipped);
  }

  // ── Write status to Firestore ──────────────────────────────────────────
  void _applyStatus(int index, _StepStatus s) {
    if (!mounted) return;
    setState(() => _status[index] = s);

    if (_linkId != null && _deviceId != null) {
      final granted = s == _StepStatus.granted;
      _pairingService.updatePermissionGranted(
        linkId:        _linkId!,
        deviceId:      _deviceId!,
        stepIndex:     index,
        permissionKey: _steps[index].firestoreKey,
        granted:       granted,
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

    Color stepColor() {
      if (status == _StepStatus.granted) return AppColors.statusLinked;
      if (status == _StepStatus.denied)  return AppColors.error;
      return AppColors.primary;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [

          // ── Progress header ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(children: [
              Row(children: [
                const Icon(Icons.shield, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Text('SafeChild Setup',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const Spacer(),
                Text('${_current + 1} of $total',
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSub)),
              ]),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: (_current + 1) / total,
                  minHeight: 6,
                  backgroundColor: AppColors.divider,
                  valueColor:
                      const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(total, (i) {
                  final s      = _status[i];
                  final active = i == _current;
                  Color dotColor = AppColors.divider;
                  if (s == _StepStatus.granted) dotColor = AppColors.statusLinked;
                  else if (s == _StepStatus.denied) dotColor = AppColors.error;
                  else if (active) dotColor = AppColors.primary;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: active ? 20 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: dotColor,
                    ),
                  );
                }),
              ),
            ]),
          ),

          // ── Step content ──────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              child: Column(children: [

                // Icon circle
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    key: ValueKey('$_current$status'),
                    width: 100, height: 100,
                    decoration: BoxDecoration(
                      color: stepColor().withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: _loading
                        ? const CircularProgressIndicator()
                        : Icon(
                            status == _StepStatus.granted
                                ? Icons.check_circle
                                : status == _StepStatus.denied
                                    ? Icons.cancel
                                    : step.icon,
                            size: 50,
                            color: stepColor(),
                          ),
                  ),
                ),
                const SizedBox(height: 22),

                // Title
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    key: ValueKey('t$_current'),
                    step.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                ),
                const SizedBox(height: 6),

                // Subtitle badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(step.subtitle,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 20),

                // Reason box
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Icon(Icons.info_outline,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(step.reason,
                          style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSub,
                              height: 1.55)),
                    ),
                  ]),
                ),

                // Accessibility hint
                if (step.type == _PermType.accessibility) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFFCC02)),
                    ),
                    child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Icon(Icons.lightbulb_outline,
                          size: 16, color: Color(0xFFE65100)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'After tapping Allow, find SafeChild in the '
                          'Installed Apps list and toggle it ON.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFFE65100),
                              height: 1.5),
                        ),
                      ),
                    ]),
                  ),
                ],

                const SizedBox(height: 16),

                // Status chip
                if (status == _StepStatus.granted)
                  _chip(Icons.check_circle, 'Granted', AppColors.statusLinked)
                else if (status == _StepStatus.denied)
                  _chip(Icons.cancel, 'Not Granted — tap Allow to retry', AppColors.error)
                else if (status == _StepStatus.skipped)
                  _chip(Icons.skip_next, 'Skipped', AppColors.statusPending),

                // Waiting hint
                if (_waitingForSettings) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Return to SafeChild after granting the permission.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AppColors.textSub),
                  ),
                ],
              ]),
            ),
          ),

          // ── Action buttons ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(children: [

              if (status != _StepStatus.granted) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _grant,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 50)),
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.settings_outlined, size: 16),
                            const SizedBox(width: 8),
                            Text(status == _StepStatus.denied
                                ? 'Retry ${step.title}'
                                : 'Allow ${step.title}'),
                          ]),
                  ),
                ),
                const SizedBox(height: 10),
                if (status != _StepStatus.skipped)
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _skip,
                      child: const Text('Skip for now',
                          style: TextStyle(color: AppColors.textSub)),
                    ),
                  ),
              ],

              if (status == _StepStatus.granted || status == _StepStatus.skipped) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _next,
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 50)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(isLast ? 'Start Monitoring' : 'Next'),
                      const SizedBox(width: 6),
                      Icon(isLast ? Icons.shield : Icons.arrow_forward,
                          size: 16),
                    ]),
                  ),
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
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}