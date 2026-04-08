// lib/services/bypass_detection_service.dart
import 'dart:async';
import 'package:android_intent_plus/android_intent.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/accessibility_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BypassDetectionService {
  static StreamSubscription? _subscription;
  String?             _deviceId;
  DateTime?           _lastRedirect;
  DateTime?           _lastSettingsLog;

  // ── Settings packages to monitor ─────────────────────────────────────
  static const _settingsPackages = {
    'com.android.settings',
    'com.miui.securitycenter',
    'com.miui.permcenter',
    'com.android.packageinstaller',
    'com.google.android.packageinstaller',
    'com.miui.appmanager',
    'com.android.vending', // Google Play Store
  };

  // ── Dangerous Action Keywords ─────────────────────────────────────────
  // These are specific buttons/menus that shouldn't be accessible.
  static const _dangerousActions = [
    'uninstall',                    // English uninstall
    'nyahpasang',                   // Malay uninstall
    'force stop',                   // English force stop
    'paksa berhenti',               // Malay force stop
    'remove',                       // English remove
    'buang',                        // Malay remove
    'deactivate',                   // English deactivate
    'nyahaktif',                    // Malay deactivate
    'device administrator',         // English device admin
    'pentadbir peranti',            // Malay device admin
  ];

  // ── Throttle — only redirect once every 3 seconds ─────────────────────
  static const _redirectCooldown  = Duration(seconds: 3);
  // ── Log settings access once per minute ───────────────────────────────
  static const _logCooldown       = Duration(minutes: 1);

  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId   = prefs.getString('device_id');

    if (_deviceId == null) {
      debugPrint('BYPASS: start() aborted — device_id not found');
      return;
    }

    _subscription = FlutterAccessibilityService.accessStream.listen(
      _onEvent,
      onError: (e) => debugPrint('BYPASS: stream error — $e'),
    );
    debugPrint('BYPASS: bypass detection started ✓');
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    debugPrint('BYPASS: bypass detection stopped');
  }

  void _onEvent(AccessibilityEvent event) {
    final pkg  = event.packageName?.toLowerCase() ?? '';
    
    // ── Is this a settings package? ─────────────────────────────────
    final isSettings = _settingsPackages.any((p) => pkg.contains(p));
    if (!isSettings) return;

    String text = (event.text ?? '').toLowerCase();
    
    // Fallback — extract text from subNodes as well
    if (event.subNodes != null) {
      final subTexts = event.subNodes!
          .where((n) => n.text != null && n.text != 'null' && n.text!.trim().isNotEmpty)
          .map((n) => n.text!.toLowerCase())
          .join(' ');
      text += ' ' + subTexts;
    }

    debugPrint('BYPASS: settings screen detected — pkg=$pkg text=$text');

    // ── Log settings access (throttled) ───────────────────────────────
    final now = DateTime.now();
    if (_lastSettingsLog == null ||
        now.difference(_lastSettingsLog!) > _logCooldown) {
      _lastSettingsLog = now;
      _logBypassEvent(
        eventType:   'settings_access',
        description: 'Child opened system settings',
        isBlocked:   false,
      );
    }

    // ── Check for dangerous keywords → redirect ────────────────────────
    final eventString = event.toString().toLowerCase();
    
    bool isDangerous = false;

    // 1. Are they specifically looking at SafeChild inside a settings/installer context?
    // If 'safechild' appears anywhere on the screen (App Info, App List, Play Store), block it.
    if (text.contains('safechild') || eventString.contains('safechild')) {
      isDangerous = true;
    }

    // 2. Are they on a known dangerous Android internal Activity?
    // This bypasses any local language translation of the UI text.
    if (eventString.contains('deviceadmin') || 
        eventString.contains('accessibilitysettings') ||
        eventString.contains('devicepolicy')) {
      isDangerous = true;
    }

    // 3. Are they seeing specific dangerous action buttons?
    if (_dangerousActions.any((action) => text.contains(action))) {
      isDangerous = true;
    }

    if (isDangerous) {
      debugPrint('BYPASS: dangerous settings page detected — redirecting');
      _redirectToHome();
      _logBypassEvent(
        eventType:   'settings_access',
        description: 'Child attempted to access SafeChild settings/uninstall: "$text"',
        isBlocked:   true,
      );
    }
  }

  // ── Redirect child to home screen ─────────────────────────────────────
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

    debugPrint('BYPASS: redirected to home screen ✓');
  }

  // ── Log bypass event to Firestore ─────────────────────────────────────
  Future<void> _logBypassEvent({
    required String eventType,
    required String description,
    required bool   isBlocked,
  }) async {
    if (_deviceId == null) return;
    try {
      await FirebaseFirestore.instance.collection('bypass_events').add({
        'device_id':        _deviceId,
        'event_type':       eventType,
        'event_description': description,
        'is_blocked':       isBlocked,
        'is_reviewed':      false,
        'is_alert_send':    false,
        'detected_at':      FieldValue.serverTimestamp(),
      });
      debugPrint('BYPASS: event logged — $eventType isBlocked=$isBlocked');
    } catch (e) {
      debugPrint('BYPASS: Firestore write failed — $e');
    }
  }
}