// lib/screens/child/child_active_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/background_service.dart';
import '../../services/content_detection_service.dart';
import '../../services/native_channel_service.dart';
import '../../utils/app_theme.dart';
import '../auth/register_screen.dart';
import 'package:pinput/pinput.dart';
import '../../services/pairing_service.dart';

class ChildActiveScreen extends StatefulWidget {
  const ChildActiveScreen({super.key});

  @override
  State<ChildActiveScreen> createState() => _ChildActiveScreenState();
}

class _ChildActiveScreenState extends State<ChildActiveScreen> {
  StreamSubscription<DocumentSnapshot>? _linkSub;
  bool    _unlinking = false;
  String? _deviceId;
  String? _linkId;

  final _detectionService = ContentDetectionService();

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

    // Write real permission status from main isolate
    // Must be done here — MethodChannel only works on main isolate
    await _updatePermissions();

    // Start background service — owns heartbeat, survives app kill
    await BackgroundServiceManager.initialize();

    // Listen for parent unlink
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

  // ── Write real permissions from main isolate to child_devices ─────────────
  Future<void> _updatePermissions() async {
    if (_deviceId == null) return;
    try {
      final accessibility = await FlutterAccessibilityService
              .isAccessibilityPermissionEnabled() ?? false;
      final usageAccess   = await NativeChannelService.checkUsageAccessGranted();
      final deviceAdmin   = await NativeChannelService.checkDeviceAdminActive();
      final notification  = await Permission.notification.isGranted;
      final overlay       = await Permission.systemAlertWindow.isGranted;

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

    await _detectionService.stop();
    await BackgroundServiceManager.stop();
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
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.link_off,
                size: 34, color: AppColors.error),
          ),
          const SizedBox(height: 16),
          const Text('Device Unlinked',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          const Text(
            'The parent has removed this device from SafeChild. '
            'Monitoring has stopped.',
            style: TextStyle(
                fontSize: 13,
                color: AppColors.textSub,
                height: 1.5),
            textAlign: TextAlign.center,
          ),
        ]),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 44)),
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
    _linkSub?.cancel();
    // Do NOT stop background service on dispose —
    // it must keep running after screen is destroyed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

                const SizedBox(height: 32),

                // Monitoring active badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(
                        color: AppColors.primary.withOpacity(0.2)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle,
                          size: 10, color: Color(0xFF2E7D32)),
                      SizedBox(width: 8),
                      Text('Monitoring Active',
                          style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Add Parent button
                TextButton.icon(
                  onPressed: _showAddParentDialog,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Parent'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}