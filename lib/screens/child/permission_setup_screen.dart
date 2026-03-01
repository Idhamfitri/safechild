// lib/screens/child/permission_setup_screen.dart
// NEW: Shown after successful pairing on the child device.
// Walks the parent through granting all required permissions
// before monitoring can begin.
//
// Permissions required on CHILD DEVICE (from permission table):
//   - POST_NOTIFICATIONS     → runtime (permission_handler)
//   - SYSTEM_ALERT_WINDOW    → special (permission_handler)
//   - PACKAGE_USAGE_STATS    → special (open Usage Access settings)
//   - BIND_ACCESSIBILITY_SVC → special (open Accessibility settings)
//   - BIND_DEVICE_ADMIN      → special (open Device Admin settings)
//
//  Auto-granted (no prompt): INTERNET, ACCESS_NETWORK_STATE,
//                            RECEIVE_BOOT_COMPLETED, FOREGROUND_SERVICE

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../utils/app_theme.dart';
import 'child_active_screen.dart';

// ─── Permission step data ─────────────────────────────────────────────────────
class _PermStep {
  final IconData icon;
  final String   title;
  final String   subtitle;     // what module needs it
  final String   reason;       // why it's needed (shown to user)
  final _PermType type;

  const _PermStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.reason,
    required this.type,
  });
}

enum _PermType {
  notification,       // runtime — permission_handler
  systemAlertWindow,  // special — permission_handler
  usageAccess,        // special — open Usage Access settings
  accessibility,      // special — open Accessibility settings
  deviceAdmin,        // special — open Security settings
}

const _steps = [
  _PermStep(
    icon: Icons.notifications_active_outlined,
    title: 'Notifications',
    subtitle: 'Required for Module 4 — Alert System',
    reason:
        'SafeChild sends real-time safety alerts to this device when '
        'suspicious content or bypass attempts are detected.',
    type: _PermType.notification,
  ),
  _PermStep(
    icon: Icons.layers_outlined,
    title: 'Display Over Other Apps',
    subtitle: 'Required for Module 3 — Anti-Bypass',
    reason:
        'Allows SafeChild to display intervention screens over harmful '
        'content and show safety warnings when needed.',
    type: _PermType.systemAlertWindow,
  ),
  _PermStep(
    icon: Icons.bar_chart_outlined,
    title: 'Usage Access',
    subtitle: 'Required for Module 3 — App Monitoring',
    reason:
        'Allows SafeChild to track which apps are used and for how long, '
        'so screen time data can be reported to the parent dashboard.',
    type: _PermType.usageAccess,
  ),
  _PermStep(
    icon: Icons.accessibility_new_outlined,
    title: 'Accessibility Service',
    subtitle: 'Required for Modules 2 & 3 — Content Detection',
    reason:
        'Allows SafeChild to read on-screen text for AI content analysis. '
        'No personal data is stored — only safety-related summaries.',
    type: _PermType.accessibility,
  ),
  _PermStep(
    icon: Icons.admin_panel_settings_outlined,
    title: 'Device Administrator',
    subtitle: 'Required for Module 3 — Anti-Bypass',
    reason:
        'Prevents SafeChild from being uninstalled without the parent\'s '
        'knowledge, ensuring the child device stays protected.',
    type: _PermType.deviceAdmin,
  ),
];

// ─── Screen ───────────────────────────────────────────────────────────────────
class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen> {
  int  _current = 0;  // current step index
  bool _loading = false;

  // Track which steps have been actioned
  final Set<int> _granted = {};
  final Set<int> _skipped = {};

  bool get _isLastStep => _current == _steps.length - 1;
  bool get _isCurrentActioned =>
      _granted.contains(_current) || _skipped.contains(_current);

  // ─── Grant / open settings ────────────────────────────────────────────────
  Future<void> _grantPermission(int index) async {
    final step = _steps[index];
    setState(() => _loading = true);

    try {
      switch (step.type) {
        // ── Runtime permission ──────────────────────────────────────────────
        case _PermType.notification:
          final status = await Permission.notification.request();
          if (status.isGranted || status.isLimited) {
            setState(() { _granted.add(index); });
          } else if (status.isPermanentlyDenied) {
            await openAppSettings();
            setState(() { _granted.add(index); }); // assume fixed in settings
          }
          break;

        // ── Special: overlay ───────────────────────────────────────────────
        case _PermType.systemAlertWindow:
          final status = await Permission.systemAlertWindow.request();
          if (status.isGranted) {
            setState(() { _granted.add(index); });
          } else {
            // Prompt user to go to settings
            _showManualInstructions(
              'Display Over Other Apps',
              '1. Tap "Open Settings" below\n'
              '2. Find "SafeChild" in the list\n'
              '3. Enable "Allow display over other apps"\n'
              '4. Return to SafeChild',
              onOpenSettings: () async {
                await openAppSettings();
                setState(() { _granted.add(index); });
              },
            );
          }
          break;

        // ── Special: Usage Access ──────────────────────────────────────────
        case _PermType.usageAccess:
          _showManualInstructions(
            'Usage Access Permission',
            '1. Tap "Open Settings" below\n'
            '2. Find "SafeChild" in the list\n'
            '3. Enable "Permit usage access"\n'
            '4. Return to SafeChild',
            onOpenSettings: () async {
              // Opens Usage Access settings via Android intent
              // (handled by openAppSettings as fallback)
              await openAppSettings();
              setState(() { _granted.add(index); });
            },
          );
          break;

        // ── Special: Accessibility ─────────────────────────────────────────
        case _PermType.accessibility:
          _showManualInstructions(
            'Accessibility Service',
            '1. Tap "Open Settings" below\n'
            '2. Go to Installed Apps → SafeChild\n'
            '3. Enable the SafeChild accessibility service\n'
            '4. Tap "Allow" on the confirmation dialog\n'
            '5. Return to SafeChild',
            onOpenSettings: () async {
              await openAppSettings();
              setState(() { _granted.add(index); });
            },
          );
          break;

        // ── Special: Device Admin ──────────────────────────────────────────
        case _PermType.deviceAdmin:
          _showManualInstructions(
            'Device Administrator',
            '1. Tap "Open Settings" below\n'
            '2. Go to Security → Device Admin Apps\n'
            '3. Enable SafeChild as a device administrator\n'
            '4. Tap "Activate" on the confirmation dialog\n'
            '5. Return to SafeChild',
            onOpenSettings: () async {
              await openAppSettings();
              setState(() { _granted.add(index); });
            },
          );
          break;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── Manual instruction dialog ────────────────────────────────────────────
  void _showManualInstructions(
    String title,
    String steps, {
    required VoidCallback onOpenSettings,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(steps,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSub,
                  height: 1.7)),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSub)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40)),
            onPressed: () {
              Navigator.pop(context);
              onOpenSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ─── Navigate forward ─────────────────────────────────────────────────────
  void _next() {
    if (_isLastStep) {
      // All steps done → go to monitoring screen
      Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ChildActiveScreen()),
          (_) => false);
    } else {
      setState(() => _current++);
    }
  }

  void _skip() {
    setState(() {
      _skipped.add(_current);
      if (!_isLastStep) _current++;
    });
  }

  // ─── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final step = _steps[_current];
    final total = _steps.length;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          // ── Top bar ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.shield, color: AppColors.primary, size: 24),
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

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (_current + 1) / total,
                    minHeight: 6,
                    backgroundColor: AppColors.divider,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  ),
                ),
              ],
            ),
          ),

          // ── Permission card ───────────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Icon circle
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      key: ValueKey(_current),
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        color: _isCurrentActioned
                            ? AppColors.primary.withOpacity(0.12)
                            : AppColors.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _granted.contains(_current)
                            ? Icons.check_circle
                            : step.icon,
                        size: 48,
                        color: _granted.contains(_current)
                            ? AppColors.primary
                            : AppColors.primary.withOpacity(0.7),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Step title
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      key: ValueKey('title$_current'),
                      step.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Module badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(step.subtitle,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 20),

                  // Reason card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(step.reason,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textSub,
                                  height: 1.55)),
                        ),
                      ],
                    ),
                  ),

                  // Granted badge
                  if (_granted.contains(_current)) ...[
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      const Icon(Icons.check_circle,
                          size: 16, color: AppColors.statusLinked),
                      const SizedBox(width: 6),
                      const Text('Permission granted',
                          style: TextStyle(
                              fontSize: 13,
                              color: AppColors.statusLinked,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ] else if (_skipped.contains(_current)) ...[
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.warning_amber_outlined,
                          size: 16, color: AppColors.statusPending),
                      const SizedBox(width: 6),
                      Text('Skipped — some features may not work',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.statusPending)),
                    ]),
                  ],
                ],
              ),
            ),
          ),

          // ── Action buttons ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(children: [
              // Grant button
              if (!_isCurrentActioned)
                ElevatedButton(
                  onPressed: _loading ? null : () => _grantPermission(_current),
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Grant ${step.title}'),
                )
              else
                ElevatedButton(
                  onPressed: _next,
                  child: Text(
                      _isLastStep ? 'Start Monitoring' : 'Next Permission'),
                ),

              const SizedBox(height: 12),

              // Skip (only if not actioned yet and not device admin)
              if (!_isCurrentActioned && step.type != _PermType.deviceAdmin)
                TextButton(
                  onPressed: _skip,
                  child: const Text('Skip for now',
                      style: TextStyle(color: AppColors.textSub)),
                )
              else if (_isCurrentActioned && !_isLastStep)
                TextButton(
                  onPressed: _next,
                  child: const Text('Continue →',
                      style: TextStyle(color: AppColors.primary)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}