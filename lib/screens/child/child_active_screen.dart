// lib/screens/child/child_active_screen.dart
import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:pinput/pinput.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/content_detection_service.dart';
import '../../utils/app_theme.dart';
import '../auth/register_screen.dart';
import '../../services/pairing_service.dart';

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
  final _pairingService = PairingService();

  static const _heartbeatInterval = Duration(minutes: 10);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _linkId   = prefs.getString('link_id');
    _deviceId = prefs.getString('device_id');

    if (_linkId == null || _deviceId == null) {
      _forceLogout();
      return;
    }

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

    await _detectionService.start();

    await _writeHeartbeat();
    _heartbeatTimer =
        Timer.periodic(_heartbeatInterval, (_) => _writeHeartbeat());

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

  Future<void> _writeHeartbeat() async {
    if (_deviceId == null) return;

    int? batteryLevel;
    try { batteryLevel = await _battery.batteryLevel; } catch (_) {}

    bool accessibilityOn = false;
    try {
      final deviceDoc = await FirebaseFirestore.instance
          .collection('child_devices')
          .doc(_deviceId)
          .get();
      final permMap = deviceDoc.data()?['permission_status'];
      if (permMap is Map) accessibilityOn = permMap['accessibility'] == true;
    } catch (_) {}

    final now = FieldValue.serverTimestamp();
    try {
      await FirebaseFirestore.instance
          .collection('heartbeat')
          .doc(_deviceId)
          .set({
        'device_id':            _deviceId,
        'last_sync':            now,
        'signal_status':        'active',
        'safechild_running':    true,
        'accessibility_active': accessibilityOn,
        if (batteryLevel != null) 'battery_level': batteryLevel,
      }, SetOptions(merge: true));
    } catch (_) {}
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

  // ── Add Parent dialog ────────────────────────────────────────────────────
  void _showAddParentDialog() {
  final codeCtrl  = TextEditingController();
  final codeFocus = FocusNode();
  bool   loading  = false;
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
                            fontSize: 12, color: AppColors.error)),
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

                    // ── Reuse same service as registration ──────────────
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

                    // No navigation needed — already on active screen
                    // Just dismiss and show success
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
                        strokeWidth: 2, color: Colors.white))
                : const Text('Link Parent'),
          ),
        ],
      ),
    ),
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [

            const SizedBox(height: 16),

            // ── Shield icon + status ───────────────────────────────────
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shield,
                  size: 56, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text('SafeChild is Active',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary)),
            const SizedBox(height: 8),
            const Text(
              'This device is being monitored.\n'
              'SafeChild runs silently in the background.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSub,
                  height: 1.6),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.2)),
              ),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 9, color: Color(0xFF2E7D32)),
                SizedBox(width: 8),
                Text('Monitoring Active',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
              ]),
            ),

            const SizedBox(height: 32),

            // ── Parents monitoring section ─────────────────────────────
            Row(children: [
              const Text('Parents Monitoring',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
              const Spacer(),
              // Add Parent button
              TextButton.icon(
                onPressed: _showAddParentDialog,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add Parent'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),

            const SizedBox(height: 12),

            // ── Parent list from Firestore ─────────────────────────────
            _deviceId == null
                ? const SizedBox.shrink()
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('parent_child_links')
                        .where('device_id', isEqualTo: _deviceId)
                        .where('link_status', isEqualTo: 'active')
                        .snapshots(),
                    builder: (context, linkSnap) {
                      if (linkSnap.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator()));
                      }

                      final links = linkSnap.data?.docs ?? [];

                      if (links.isEmpty) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                            Icon(Icons.person_off_outlined,
                                size: 40,
                                color: AppColors.textSub.withOpacity(0.4)),
                            const SizedBox(height: 10),
                            const Text('No parents linked',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSub)),
                            const SizedBox(height: 4),
                            const Text(
                                'Tap Add Parent to link a parent account.',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSub)),
                          ]),
                        );
                      }

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.divider),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics:
                              const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.zero,
                          itemCount: links.length,
                          separatorBuilder: (_, __) => const Divider(
                              height: 1, indent: 16, endIndent: 16),
                          itemBuilder: (context, index) {
                            final linkData = links[index].data();
                            final parentId = linkData['parent_id'] as String?;

                            if (parentId == null) {
                              return const SizedBox.shrink();
                            }

                            // Fetch parent details
                            return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              future: FirebaseFirestore.instance
                                  .collection('parents')
                                  .doc(parentId)
                                  .get(),
                              builder: (context, parentSnap) {
                                final parentData = parentSnap.data?.data();
                                final name = parentData?['full_name'] ?? 'Parent';
                                final email = parentData?['email'] ?? '—';
                                final linkedAt = linkData['linked_at'];
                                String linkedLabel = '';
                                if (linkedAt != null) {
                                  final dt = (linkedAt as Timestamp)
                                      .toDate();
                                  linkedLabel =
                                      'Linked ${_timeAgo(dt)}';
                                }

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                  child: Row(children: [
                                    // Avatar
                                    Container(
                                      width: 44, height: 44,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary
                                            .withOpacity(0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          name.isNotEmpty
                                              ? name[0].toUpperCase()
                                              : 'P',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight:
                                                  FontWeight.bold,
                                              color: AppColors.primary),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),

                                    // Name + email
                                    Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Text(name,
                                            style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color: AppColors
                                                    .textPrimary)),
                                        const SizedBox(height: 2),
                                        Text(email,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color:
                                                    AppColors.textSub)),
                                        if (linkedLabel.isNotEmpty)
                                          Text(linkedLabel,
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors
                                                      .textSub)),
                                      ]),
                                    ),

                                    // Monitoring badge
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF2E7D32)
                                            .withOpacity(0.10),
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                      child: const Row(
                                          mainAxisSize:
                                              MainAxisSize.min,
                                          children: [
                                        Icon(Icons.visibility_outlined,
                                            size: 12,
                                            color: Color(0xFF2E7D32)),
                                        SizedBox(width: 4),
                                        Text('Monitoring',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color: Color(
                                                    0xFF2E7D32))),
                                      ]),
                                    ),
                                  ]),
                                );
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),

            const SizedBox(height: 32),
          ]),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0)    return '${diff.inDays}d ago';
    if (diff.inHours > 0)   return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'just now';
  }
}