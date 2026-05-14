// lib/screens/child/child_active_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/background_service.dart';
import '../../services/content_detection_service_v2.dart'; // V2: local FastText
import '../../services/bypass_detection_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_utils.dart';
import '../auth/register_screen.dart';
import 'package:pinput/pinput.dart';
import '../../services/pairing_service.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:device_policy_manager/device_policy_manager.dart';
import 'permission_setup_screen.dart';
import '../../models/screen_time_models.dart';
import 'device_lock_screen.dart';

class ChildActiveScreen extends StatefulWidget {
  const ChildActiveScreen({super.key});

  @override
  State<ChildActiveScreen> createState() => _ChildActiveScreenState();
}

class _ChildActiveScreenState extends State<ChildActiveScreen> {
  StreamSubscription<QuerySnapshot>? _linkSub;
  StreamSubscription<DocumentSnapshot>? _deviceSub;
  StreamSubscription<DocumentSnapshot>? _monitoringSub;
  StreamSubscription<DocumentSnapshot>? _screenTimeSub;
  bool    _unlinking = false;
  String? _deviceId;
  String? _linkId;
  
  bool _isLocked = false;
  String _lockReason = 'Device Locked';
  bool _isManualLock = false;

  final _detectionService = ContentDetectionServiceV2();
  final _bypassService    = BypassDetectionService();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _linkId   = prefs.getString('link_id');
    _deviceId = prefs.getString('device_id');

    if (mounted) setState(() {});

    if (_linkId == null || _deviceId == null) {
      _forceLogout();
      return;
    }

    // Mark setup phase active
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

    // Start content detection
    await _detectionService.start();
    
    // Start bypass detection
    await _bypassService.start();

    // Write real permission status from main isolate
    // Must be done here — MethodChannel only works on main isolate
    await _updatePermissions();

    // Start background service — owns heartbeat, survives app kill
    await BackgroundServiceManager.initialize();

    // Listen for ALL parent links (Many-to-Many architecture)
    _linkSub = FirebaseFirestore.instance
        .collection('parent_child_links')
        .where('device_id', isEqualTo: _deviceId)
        .snapshots()
        .listen((snap) async {
      if (!mounted) return;

      // In-memory filter to avoid composite index requirements
      final activeLinks = snap.docs.where((doc) {
        final data = doc.data();
        return data['link_status'] == 'active' && data['pairing_status'] != 'expired';
      }).toList();

      // If active parents drop to 0, unlock the device admin and sign out
      if (activeLinks.isEmpty) {
        _forceLogout();
      }
    }, onError: (_) {});

    // Listen for Remote Settings
    _deviceSub = FirebaseFirestore.instance
        .collection('child_devices')
        .doc(_deviceId)
        .snapshots()
        .listen((snap) async {
      if (!mounted || !snap.exists) return;
      final data = snap.data() ?? {};
      final settings = data['settings'] as Map<String, dynamic>? ?? {};

      // Trigger Permission Setup
      final triggerSetup = settings['trigger_setup'] ?? false;
      if (triggerSetup) {
        // Clear flag immediately so it doesn't loop
        try {
          await FirebaseFirestore.instance
              .collection('child_devices')
              .doc(_deviceId)
              .update({'settings.trigger_setup': false});
        } catch (_) {}

        if (mounted) {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => PermissionSetupScreen()),
              (_) => false);
        }
      }
    }, onError: (_) {});

    // Listen for Monitoring Settings (from Parent)
    _monitoringSub = FirebaseFirestore.instance
        .collection('monitoring_settings')
        .doc(_linkId)
        .snapshots()
        .listen((snap) async {
      if (!mounted || !snap.exists) return;
      final data = snap.data() ?? {};

      final offlineMode = data['offline_mode'] ?? false;
      
      // Bypass
      final bypassEnabled = !offlineMode && (data['bypass_detection_enabled'] ?? true);
      if (bypassEnabled) {
        await _bypassService.start();
      } else {
        await _bypassService.stop();
      }

      // Content Detection
      final contentEnabled = !offlineMode && (data['content_monitoring_enabled'] ?? true);
      if (contentEnabled) {
        await _detectionService.start();
      } else {
        await _detectionService.stop();
      }
    }, onError: (_) {});
    
    // Listen for Screen Time Configuration Lock State
    _screenTimeSub = FirebaseFirestore.instance
        .collection('screen_time_locks')
        .doc(_deviceId)
        .snapshots()
        .listen((snap) {
      if (!mounted || !snap.exists) return;
      final lock = ScreenTimeLock.fromFirestore(snap);
      
      bool isLocked = lock.isLocked;
      
      setState(() {
        _isLocked = isLocked;
        _isManualLock = lock.unlockedAt == null;
        _lockReason = _isManualLock ? 'Device is manually locked by parent' : 'Device is being locked';
      });
      
      // Update bypass service state for active enforcement
      _bypassService.setLocked(isLocked);
    }, onError: (_) {});
  }

  // ── Write real permissions from main isolate to child_devices ─────────────
  Future<void> _updatePermissions() async {
  if (_deviceId == null) return;
  try {
    final accessibility = await FlutterAccessibilityService
            .isAccessibilityPermissionEnabled() ?? false;
    final notification  = await Permission.notification.isGranted;
    final overlay       = await Permission.systemAlertWindow.isGranted;
    // Use packages directly — no native channel needed
    final usageAccess   = await UsageStats.checkUsagePermission() ?? false  ;
    final deviceAdmin   = await DevicePolicyManager.isPermissionGranted();

    await FirebaseFirestore.instance
        .collection('child_devices')
        .doc(_deviceId)
        .update({
      'permission_status.accessibility': accessibility,
      'permission_status.usage_access':  usageAccess,
      'permission_status.device_admin':  deviceAdmin,
      'permission_status.notifications': notification,
      'permission_status.overlay':       overlay,
      'permission_status.last_updated':  FieldValue.serverTimestamp(),
    });
  } catch (_) {}
}

  Future<void> _forceLogout() async {
    if (_unlinking || !mounted) return;
    setState(() => _unlinking = true);

    // Fire-and-forget stop calls so we never hang if a background plugin misbehaves
    _detectionService.stop();
    _bypassService.stop();
    BackgroundServiceManager.stop();
    _linkSub?.cancel();
    _deviceSub?.cancel();
    _monitoringSub?.cancel();
    _screenTimeSub?.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('role');
    await prefs.remove('link_id');
    await prefs.remove('device_id');

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Device Unlinked: SafeChild deactivated.'),
        backgroundColor: AppColors.error,
        duration: Duration(seconds: 4),
      ),
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const RegisterScreen()),
      (_) => false,
    );
  }


  final _pairingService = PairingService();
  void _showAddParentDialog() {
  final codeCtrl  = TextEditingController();
  final codeFocus = FocusNode();
  bool    loading = false;
  String? errorMsg;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Add New Parent',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ask the parent to open SafeChild and share their pairing code.',
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSub,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Pinput(
              controller:   codeCtrl,
              focusNode:    codeFocus,
              length:       6,
              autofocus:    true,
              keyboardType: TextInputType.number,
              defaultPinTheme: PinTheme(
                width: 44, height: 48,
                textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.divider),
                ),
              ),
              focusedPinTheme: PinTheme(
                width: 44, height: 48,
                textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: AppColors.primary, width: 2),
                ),
              ),
              errorPinTheme: PinTheme(
                width: 44, height: 48,
                textStyle: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.error),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.error),
                ),
              ),
            ),
            if (errorMsg != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.error.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline,
                      size: 14, color: AppColors.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(errorMsg!,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.error)),
                  ),
                ]),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: loading ? null : () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: loading
                ? null
                : () async {
                    final code = codeCtrl.text.trim();
                    if (code.length != 6) {
                      setDialogState(() =>
                          errorMsg = 'Enter the full 6-digit code.');
                      return;
                    }
                    setDialogState(() {
                      loading  = true;
                      errorMsg = null;
                    });

                    final error =
                        await _pairingService.submitPairingCode(code);

                    if (error != null) {
                      setDialogState(() {
                        loading  = false;
                        errorMsg = error;
                      });
                      codeCtrl.clear();
                      codeFocus.requestFocus();
                      return;
                    }

                    if (!mounted) return;
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Parent linked successfully!'),
                        backgroundColor: Color(0xFF2E7D32),
                      ),
                    );
                  },
            child: loading
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white))
                : const Text('Link Parent'),
          ),
        ],
      ),
    ),
  );
}

  @override
  void dispose() {
    _detectionService.stop();
    _bypassService.stop();
    _linkSub?.cancel();
    _deviceSub?.cancel();
    _monitoringSub?.cancel();
    _screenTimeSub?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
       return DeviceLockScreen(lockReason: _lockReason, isManualLock: _isManualLock);
    }
  
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // Shield icon
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
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),

                const SizedBox(height: 12),

                const Text(
                  'You are being protected.\n'
                  'SafeChild runs silently in the background.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSub,
                      height: 1.6),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}