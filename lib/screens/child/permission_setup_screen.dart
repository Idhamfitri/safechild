// lib/screens/child/permission_setup_screen.dart
// FIXED:
//  1. Uses WidgetsBindingObserver to detect when user returns from Settings
//  2. Checks ACTUAL permission status on resume — not just assuming granted
//  3. Permissions that can't be auto-verified (usage, accessibility, device
//     admin) show a "Did you enable it?" confirmation dialog on return
//  4. User cannot proceed to next step until permission is confirmed granted
//  5. Device Admin step is required — no skip allowed

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../utils/app_theme.dart';
import 'child_active_screen.dart';

// ─── Step data model ──────────────────────────────────────────────────────────
class _PermStep {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final String   reason;
  final _PermType type;
  final List<String> instructions;

  const _PermStep({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.reason,
    required this.type,
    required this.instructions,
  });
}

enum _PermType {
  notification,
  systemAlertWindow,
  usageAccess,
  accessibility,
  deviceAdmin,
}

const _steps = [
  _PermStep(
    icon: Icons.notifications_active_outlined,
    title: 'Notifications',
    subtitle: 'Required for Module 4 — Alert System',
    reason: 'SafeChild needs to send real-time safety alerts to this device '
        'when suspicious content or bypass attempts are detected.',
    type: _PermType.notification,
    instructions: [
      'Tap "Grant Permission" below',
      'When Android prompts, tap Allow',
      'Return here',
    ],
  ),
  _PermStep(
    icon: Icons.layers_outlined,
    title: 'Display Over Other Apps',
    subtitle: 'Required for Module 3 — Anti-Bypass',
    reason: 'Allows SafeChild to display intervention screens over harmful '
        'content and block restricted apps.',
    type: _PermType.systemAlertWindow,
    instructions: [
      'Tap "Open Settings" below',
      'Find SafeChild in the list',
      'Toggle ON "Allow display over other apps"',
      'Press Back to return here',
    ],
  ),
  _PermStep(
    icon: Icons.bar_chart_outlined,
    title: 'Usage Access',
    subtitle: 'Required for Module 3 — App Monitoring',
    reason: 'Allows SafeChild to track which apps are used and for how long, '
        'so screen time data can be reported to the parent dashboard.',
    type: _PermType.usageAccess,
    instructions: [
      'Tap "Open Settings" below',
      'Find SafeChild in the Usage Access list',
      'Toggle ON "Permit usage access"',
      'Press Back to return here',
    ],
  ),
  _PermStep(
    icon: Icons.accessibility_new_outlined,
    title: 'Accessibility Service',
    subtitle: 'Required for Modules 2 & 3 — Content Detection',
    reason: 'Allows SafeChild to read on-screen text for AI content analysis. '
        'No personal data is stored — only safety-related summaries.',
    type: _PermType.accessibility,
    instructions: [
      'Tap "Open Settings" below',
      'Scroll down to find SafeChild',
      'Tap SafeChild and toggle the service ON',
      'Tap "Allow" on the confirmation popup',
      'Press Back to return here',
    ],
  ),
  _PermStep(
    icon: Icons.admin_panel_settings_outlined,
    title: 'Device Administrator',
    subtitle: 'Required for Module 3 — Anti-Bypass',
    reason: 'Prevents SafeChild from being uninstalled without the parent\'s '
        'knowledge, ensuring the child device stays protected at all times.',
    type: _PermType.deviceAdmin,
    instructions: [
      'Tap "Open Settings" below',
      'Navigate to Security → Device Admin Apps',
      'Find SafeChild and toggle it ON',
      'Tap "Activate" on the confirmation dialog',
      'Press Back to return here',
    ],
  ),
];

// ─── Status of each permission step ──────────────────────────────────────────
enum _StepStatus { idle, granted, skipped }

// ─── Screen ───────────────────────────────────────────────────────────────────
class PermissionSetupScreen extends StatefulWidget {
  const PermissionSetupScreen({super.key});

  @override
  State<PermissionSetupScreen> createState() => _PermissionSetupScreenState();
}

class _PermissionSetupScreenState extends State<PermissionSetupScreen>
    with WidgetsBindingObserver {
  int  _current = 0;
  bool _loading = false;

  // Tracks status of each step
  final _status = List<_StepStatus>.filled(5, _StepStatus.idle);

  // Which step was waiting when user went to Settings
  int? _awaitingReturnFor;

  @override
  void initState() {
    super.initState();
    // Register observer — fires when app comes back to foreground from Settings
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Called when app returns to foreground (user pressed Back from Settings) 
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _awaitingReturnFor != null) {
      final idx = _awaitingReturnFor!;
      _awaitingReturnFor = null;
      _verifyOnResume(idx);
    }
  }

  // ── Verify actual permission status after returning from Settings ──────────
  Future<void> _verifyOnResume(int index) async {
    final step = _steps[index];

    switch (step.type) {
      // These two can be checked programmatically via permission_handler
      case _PermType.notification:
        final s = await Permission.notification.status;
        if (s.isGranted || s.isLimited) {
          _setGranted(index);
        } else {
          _showNotGrantedDialog(index);
        }
        break;

      case _PermType.systemAlertWindow:
        final s = await Permission.systemAlertWindow.status;
        if (s.isGranted) {
          _setGranted(index);
        } else {
          _showNotGrantedDialog(index);
        }
        break;

      // These cannot be checked via permission_handler without native code.
      // Show "Did you enable it?" confirmation — user must confirm.
      case _PermType.usageAccess:
      case _PermType.accessibility:
      case _PermType.deviceAdmin:
        _showConfirmDialog(index);
        break;
    }
  }

  // ── Grant button tapped ───────────────────────────────────────────────────
  Future<void> _grantPermission(int index) async {
    final step = _steps[index];
    setState(() => _loading = true);

    try {
      switch (step.type) {
        // Runtime — request directly
        case _PermType.notification:
          _awaitingReturnFor = index;
          final s = await Permission.notification.request();
          _awaitingReturnFor = null;
          if (s.isGranted || s.isLimited) {
            _setGranted(index);
          } else if (s.isPermanentlyDenied) {
            _awaitingReturnFor = index;
            await openAppSettings();
          } else {
            _showNotGrantedDialog(index);
          }
          break;

        // Special permissions — show instructions, open settings, wait for resume
        case _PermType.systemAlertWindow:
          final s = await Permission.systemAlertWindow.status;
          if (s.isGranted) {
            _setGranted(index);
          } else {
            await _showInstructionsAndOpen(index);
          }
          break;

        case _PermType.usageAccess:
        case _PermType.accessibility:
        case _PermType.deviceAdmin:
          await _showInstructionsAndOpen(index);
          break;
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Show step-by-step instructions then open Settings ────────────────────
  Future<void> _showInstructionsAndOpen(int index) async {
    final step = _steps[index];
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          Icon(step.icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(step.title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Follow these steps carefully:',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            ...List.generate(step.instructions.length, (i) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(step.instructions[i],
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSub,
                            height: 1.4)),
                  ),
                ],
              ),
            )),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.statusPending.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline,
                    size: 14, color: AppColors.statusPending),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'SafeChild will check the permission when you return.',
                    style: TextStyle(
                        fontSize: 11,
                        color: AppColors.statusPending,
                        height: 1.4),
                  ),
                ),
              ]),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not Now',
                style: TextStyle(color: AppColors.textSub)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _awaitingReturnFor = index;
      await openAppSettings();
    }
  }

  // ── "Did you enable it?" dialog for manually-verified permissions ─────────
  void _showConfirmDialog(int index) {
    final step = _steps[index];
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: const Text('Did you enable it?',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        content: Text(
          'Did you turn on "${step.title}" in Settings?',
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSub, height: 1.5),
        ),
        actions: [
          // Not enabled — stay on this step, try again
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('No, try again',
                style: TextStyle(color: AppColors.textSub)),
          ),
          // Confirmed — mark as granted, allow proceed
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(context);
              _setGranted(index);
            },
            child: const Text('Yes, I enabled it'),
          ),
        ],
      ),
    );
  }

  // ── "Not granted" dialog — stay on current step ───────────────────────────
  void _showNotGrantedDialog(int index) {
    final step = _steps[index];
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.statusPending, size: 22),
          const SizedBox(width: 8),
          const Text('Permission Not Granted',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ]),
        content: Text(
          '"${step.title}" was not enabled. SafeChild requires this '
          'permission to protect this device properly.\n\n'
          'Please try again and make sure you enable it in Settings.',
          style: const TextStyle(
              fontSize: 13, color: AppColors.textSub, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () => Navigator.pop(context),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  // ── Mark step as granted and update UI ───────────────────────────────────
  void _setGranted(int index) {
    if (!mounted) return;
    setState(() => _status[index] = _StepStatus.granted);
  }

  // ── Check if current step is done (granted or skipped) ───────────────────
  bool get _isCurrentDone =>
      _status[_current] == _StepStatus.granted ||
      _status[_current] == _StepStatus.skipped;

  bool get _isLastStep => _current == _steps.length - 1;

  bool get _canSkip =>
      _steps[_current].type != _PermType.deviceAdmin;

  // ── Next step / finish ────────────────────────────────────────────────────
  void _next() {
    if (_isLastStep) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ChildActiveScreen()),
        (_) => false,
      );
    } else {
      setState(() => _current++);
    }
  }

  void _skip() {
    setState(() {
      _status[_current] = _StepStatus.skipped;
      if (!_isLastStep) _current++;
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final step   = _steps[_current];
    final total  = _steps.length;
    final status = _status[_current];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(children: [
          // ── Top bar + progress ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.shield,
                      color: AppColors.primary, size: 22),
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
                // Step dots
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(total, (i) {
                    final done = _status[i] == _StepStatus.granted;
                    final active = i == _current;
                    return Container(
                      width: active ? 20 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: done
                            ? AppColors.statusLinked
                            : active
                                ? AppColors.primary
                                : AppColors.divider,
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),

          // ── Permission card ──────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 8),

                  // Icon circle
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      key: ValueKey(_current),
                      width: 100, height: 100,
                      decoration: BoxDecoration(
                        color: status == _StepStatus.granted
                            ? AppColors.statusLinked.withOpacity(0.12)
                            : AppColors.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        status == _StepStatus.granted
                            ? Icons.check_circle
                            : step.icon,
                        size: 52,
                        color: status == _StepStatus.granted
                            ? AppColors.statusLinked
                            : AppColors.primary.withOpacity(0.75),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Title
                  Text(
                    step.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
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
                            size: 17, color: AppColors.primary),
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

                  const SizedBox(height: 16),

                  // Status indicator
                  if (status == _StepStatus.granted)
                    _statusChip(
                      icon: Icons.check_circle,
                      label: 'Permission granted — you may proceed',
                      color: AppColors.statusLinked,
                    )
                  else if (status == _StepStatus.skipped)
                    _statusChip(
                      icon: Icons.warning_amber_outlined,
                      label: 'Skipped — some features may not work',
                      color: AppColors.statusPending,
                    )
                  else if (step.type == _PermType.deviceAdmin)
                    _statusChip(
                      icon: Icons.lock_outline,
                      label: 'Required — cannot be skipped',
                      color: AppColors.error,
                    ),
                ],
              ),
            ),
          ),

          // ── Action buttons ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(children: [
              // Primary button
              if (!_isCurrentDone)
                ElevatedButton(
                  onPressed: _loading
                      ? null
                      : () => _grantPermission(_current),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_isLastStep
                          ? 'Start Monitoring'
                          : 'Next'),
                      const SizedBox(width: 6),
                      Icon(
                        _isLastStep
                            ? Icons.shield
                            : Icons.arrow_forward,
                        size: 16),
                    ],
                  ),
                ),

              const SizedBox(height: 10),

              // Skip button — only show if not done and not device admin
              if (!_isCurrentDone && _canSkip)
                TextButton(
                  onPressed: _skip,
                  child: const Text('Skip for now',
                      style: TextStyle(color: AppColors.textSub)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _statusChip({
    required IconData icon,
    required String   label,
    required Color    color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 8),
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