// lib/services/bypass_detection_service.dart
import 'dart:async';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_policy_manager/device_policy_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/accessibility_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BypassDetectionService {
  static StreamSubscription? _subscription;
  static const _channel = MethodChannel('com.safechild/native_helper');

  String?             _deviceId;
  String?             _childName;
  DateTime?           _lastRedirect;
  DateTime?           _lastSettingsLog;
  DateTime?           _lastTamperingLog;
  DateTime?           _lastLockEnforce;
  bool                _isLocked = false;
  // Per-package log throttle — prevents spam in terminal
  final Map<String, DateTime> _lastLogTime = {};

  void setLocked(bool locked) {
    _isLocked = locked;
    debugPrint('BYPASS: lock state updated to: $locked');
  }

  // ── General settings app (log only, no alert) ─────────────────────────
  static const _generalSettingsPackages = {
    'com.android.settings',
  };

  // ── Permission/security packages (alert parent) ───────────────────────
  static const _tamperingPackages = {
    'com.miui.securitycenter',
    'com.miui.permcenter',
    'com.android.packageinstaller',
    'com.google.android.packageinstaller',
    'com.miui.appmanager',
    'com.android.vending',
  };

  // ── IME/keyboard packages — excluded from lock enforcement ────────────
  // On some MIUI devices keyboard events briefly fire lifecycle paused,
  // causing lockNow() to trigger repeatedly while the dialog is open.
  static const _imePackageFragments = [
    'inputmethod', 'keyboard', 'ime', 'pinyin', 'honeyboard',
  ];

  // ── Cooldowns ─────────────────────────────────────────────────────────
  static const _redirectCooldown   = Duration(seconds: 3);
  static const _logCooldown        = Duration(minutes: 1);
  // Prevents lockNow() spam — one enforcement per 2 s while locked
  static const _lockEnforceCooldown = Duration(seconds: 2);

  Future<void> start() async {
    if (_subscription != null) {
      debugPrint('BYPASS: already running, ignoring start request');
      return;
    }

    // GUARD: Check permission before starting stream
    final isEnabled = await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (isEnabled != true) {
      debugPrint('BYPASS: Accessibility not granted. Aborting stream start.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _deviceId   = prefs.getString('device_id');

    if (_deviceId == null) {
      debugPrint('BYPASS: start() aborted — device_id not found');
      return;
    }

    // Fetch child name once so notifications can include it
    try {
      final doc = await FirebaseFirestore.instance
          .collection('child_devices')
          .doc(_deviceId)
          .get();
      _childName = doc.data()?['full_name'] as String?;
    } catch (_) {}

    _subscription = FlutterAccessibilityService.accessStream.listen(
      _onEvent,
      onError: (e) => debugPrint('BYPASS: stream error — $e'),
    );
    debugPrint('BYPASS: bypass detection started ✓');
  }

  Future<void> stop() async {
    try {
      if (_subscription != null) {
        await _subscription?.cancel();
      }
    } catch (e) {
      debugPrint('BYPASS: Warning - Accessibility stream de-activation error: $e');
    } finally {
      _subscription = null;
      debugPrint('BYPASS: bypass detection stopped');
    }
  }

  final List<AccessibilityEvent> _eventQueue = [];
  bool _isProcessing = false;

  void _onEvent(AccessibilityEvent event) {
    _eventQueue.add(event);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_eventQueue.isNotEmpty) {
      final event = _eventQueue.removeAt(0);
      
      // Yield to UI thread to prevent skipped frames (Choreographer lag)
      await Future.delayed(Duration.zero);
      
      await _handleEvent(event);
    }

    _isProcessing = false;
  }

  Future<void> _handleEvent(AccessibilityEvent event) async {
    final pkg = event.packageName?.toLowerCase() ?? '';
    if (pkg.isEmpty) return;

    final now = DateTime.now();
    final lastLog = _lastLogTime[pkg];
    if (lastLog == null || now.difference(lastLog).inSeconds >= 2) {
      _lastLogTime[pkg] = now;
    }

    // ── 1. Permission/security tampering packages ─────────────────────────
    // Checked FIRST — must fire even when the device is screen-time locked,
    // because the locked-enforcement section would otherwise return early and
    // the device_tampering event would never be logged.
    final isTampering = _tamperingPackages.any((p) => pkg.contains(p));
    if (isTampering) {
      debugPrint('BYPASS: tampering package detected — pkg=$pkg');

      if (_lastTamperingLog == null ||
          now.difference(_lastTamperingLog!) > _redirectCooldown) {
        _lastTamperingLog = now;
        _logBypassEvent(
          eventType:   'device_tampering',
          description: '${_childName ?? 'Child'} trying to tamper the permission',
          isBlocked:   true,
          silentLog:   false,
        );
      }

      // When locked, bring back to SafeChild; otherwise go to home and force-close
      if (_isLocked) {
        if (_lastLockEnforce == null ||
            now.difference(_lastLockEnforce!) > _lockEnforceCooldown) {
          _lastLockEnforce = now;
          DevicePolicyManager.lockNow();
          _redirectToSafeChild();
        }
      } else {
        _redirectToHome();
        // Kill after 400 ms — app must be in background first
        Future.delayed(const Duration(milliseconds: 400), () => _forceCloseApp(pkg));
      }
      return;
    }

    // ── 2. Screen-time lock enforcement (all other non-SafeChild packages) ──
    if (_isLocked &&
        !pkg.contains('com.safechild.safechild') &&
        !pkg.contains('android.systemui') &&
        !_imePackageFragments.any((f) => pkg.contains(f))) {
      if (_lastLockEnforce == null ||
          now.difference(_lastLockEnforce!) > _lockEnforceCooldown) {
        _lastLockEnforce = now;
        debugPrint('BYPASS: locked — blocking pkg=$pkg');
        DevicePolicyManager.lockNow();
        _redirectToSafeChild();
      }
      return;
    }

    // ── 3. General settings app ───────────────────────────────────────────
    final isGeneralSettings = _generalSettingsPackages.any((p) => pkg.contains(p));
    if (!isGeneralSettings) return;

    // Collect screen text to check if child navigated to SafeChild's app page
    String text = (event.text ?? '').toLowerCase();
    if (event.subNodes != null) {
      final sub = event.subNodes!
          .where((n) => n.text != null && n.text != 'null' && n.text!.trim().isNotEmpty)
          .map((n) => n.text!.toLowerCase())
          .join(' ');
      text += ' $sub';
    }
    final eventString = event.toString().toLowerCase();
    final onSafeChildPage =
        text.contains('safechild') || eventString.contains('safechild');

    if (onSafeChildPage) {
      // Child navigated to SafeChild's app info / permission page → tamper alert
      debugPrint('BYPASS: SafeChild permission page detected inside settings');
      _redirectToHome();
      // Kill settings after it moves to background
      Future.delayed(const Duration(milliseconds: 400), () => _forceCloseApp('com.android.settings'));

      if (_lastTamperingLog == null ||
          now.difference(_lastTamperingLog!) > _redirectCooldown) {
        _lastTamperingLog = now;
        _logBypassEvent(
          eventType:   'device_tampering',
          description: '${_childName ?? 'Child'} trying to tamper the permission',
          isBlocked:   true,
          silentLog:   false,
        );
      }
    } else {
      // Just opened the general settings home page — log only, no alert
      debugPrint('BYPASS: general settings opened — pkg=$pkg');
      if (_lastSettingsLog == null ||
          now.difference(_lastSettingsLog!) > _logCooldown) {
        _lastSettingsLog = now;
        _logBypassEvent(
          eventType:   'settings_opened',
          description: '${_childName ?? 'Child'} open the general setting',
          isBlocked:   false,
          silentLog:   true,
        );
      }
    }
  }

  // ── Force-close a package via ActivityManager.killBackgroundProcesses ────
  // Redirect to home first so the target app is in the background, then kill.
  Future<void> _forceCloseApp(String pkg) async {
    try {
      await _channel.invokeMethod('killPackage', {'package': pkg});
      debugPrint('BYPASS: force-closed $pkg');
    } catch (e) {
      debugPrint('BYPASS: killPackage failed — $e');
    }
  }

  // ── Redirect child to home screen ───
  void _redirectToHome() {
    final now = DateTime.now();
    if (_lastRedirect != null &&
        now.difference(_lastRedirect!) < _redirectCooldown) {
      return; // Already redirected recently
    }
    _lastRedirect = now;

    AndroidIntent(
      action:   'android.intent.action.MAIN',
      category: 'android.intent.category.HOME',
    ).launch().catchError((e) {
      debugPrint('BYPASS: redirect failed — $e');
    });

    debugPrint('BYPASS: redirected to home screen.......');
  }

  void _redirectToSafeChild() {
    AndroidIntent(
      action: 'android.intent.action.MAIN',
      package: 'com.safechild.safechild',
      componentName: 'com.safechild.safechild.MainActivity',
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_ACTIVITY_REORDER_TO_FRONT],
    ).launch().catchError((e) {
       debugPrint('BYPASS: SafeChild redirect failed: $e');
    });
  }

  // ── Log bypass event to Firestore ─────────────────────────────────────
  // silentLog=true → stored in parent log only, no push notification sent.
  Future<void> _logBypassEvent({
    required String eventType,
    required String description,
    required bool   isBlocked,
    bool            silentLog = false,
  }) async {
    if (_deviceId == null) return;
    try {
      await FirebaseFirestore.instance.collection('bypass_events').add({
        'device_id':         _deviceId,
        'child_name':        _childName ?? 'Unknown',
        'event_type':        eventType,
        'event_description': description,
        'is_blocked':        isBlocked,
        'is_reviewed':       false,
        'is_alert_send':     silentLog, // true = CF skips push notification
        'detected_at':       FieldValue.serverTimestamp(),
      });
      debugPrint('BYPASS: event logged — $eventType isBlocked=$isBlocked silent=$silentLog');
    } catch (e) {
      debugPrint('BYPASS: Firestore write failed — $e');
    }
  }
}