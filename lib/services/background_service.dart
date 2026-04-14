// lib/services/background_service.dart
// Owns ALL heartbeat logic. Survives app kill, cache clear, and reboots.
import 'dart:async';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_policy_manager/device_policy_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usage_stats/usage_stats.dart';
import 'package:flutter/foundation.dart';
import 'native_channel_service.dart';

const _kNotifChannelId   = 'safechild_monitoring';
const _kNotifChannelName = 'SafeChild Monitoring';
const _kNotifId          = 888;

class BackgroundServiceManager {

  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    // Skip if already running
    if (await service.isRunning()) return;

    // Create notification channel
    const notifChannel = AndroidNotificationChannel(
      _kNotifChannelId,
      _kNotifChannelName,
      description: 'SafeChild background monitoring service',
      importance: Importance.low,
    );

    final notifPlugin = FlutterLocalNotificationsPlugin();
    final androidPlugin = notifPlugin
    .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(notifChannel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart:                         onStart,
        autoStart:                       true,
        isForegroundMode:                true,
        notificationChannelId:           _kNotifChannelId,
        initialNotificationTitle:        'SafeChild Active',
        initialNotificationContent:      'Protecting this device in the background',
        foregroundServiceNotificationId: _kNotifId,
        foregroundServiceTypes:          [AndroidForegroundType.dataSync],
        autoStartOnBoot:                 true,
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );

    await service.startService();
  }

  static Future<void> stop() async {
    FlutterBackgroundService().invoke('stopService');
  }

  static Future<bool> isRunning() async {
    return FlutterBackgroundService().isRunning();
  }
}

@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Init Firebase in this isolate
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}

 
  service.on('stopService').listen((_) => service.stopSelf());


  await _sendHeartbeat(service);

  // Then every 10 minutes
  Timer.periodic(const Duration(minutes: 10), (_) async {
    await _sendHeartbeat(service);
  });
}

Future<void> _sendHeartbeat(ServiceInstance service) async {
  try {
    final prefs    = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');
    final linkId   = prefs.getString('link_id');

    if (deviceId == null || linkId == null) return;

    final db  = FirebaseFirestore.instance;
    final now = DateTime.now();

    // Battery level — works fine in background isolate
    int? batteryLevel;
    try { batteryLevel = await Battery().batteryLevel; } catch (_) {}

    // ── Heartbeat  
    try {
      await db.collection('heartbeat').doc(deviceId).set({
        'device_id':         deviceId,
        'last_sync':         Timestamp.fromDate(now),
        'signal_status':     'active',
        if (batteryLevel != null) 'battery_level': batteryLevel,
      }, SetOptions(merge: true));

      await db.collection('child_devices').doc(deviceId).set({
        'last_seen': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('BACKGROUND_SVC: Heartbeat Firestore write failed: $e');
    }

    // Write today's usage stats to screen_time/{deviceId}/daily/{date}
    try {
      await _writeUsageStats(db, deviceId, now);
    } catch (e) {
      debugPrint('BACKGROUND_SVC: Usage stats Firestore write failed: $e');
    }

    // ── Re-check permissions from background isolate ────────────
    // Note: Only usage_access and device_admin can be checked here.
    // Accessibility & overlay require main isolate (MethodChannel).
    bool? usageAccess;
    bool? deviceAdmin;
    try { 
      usageAccess = await UsageStats.checkUsagePermission(); 
    } catch (_) {}
    try { 
      deviceAdmin = await DevicePolicyManager.isPermissionGranted(); 
    } catch (_) {}

    if (usageAccess != null || deviceAdmin != null) {
      final updates = <String, dynamic>{};
      if (usageAccess != null) updates['permission_status.usage_access']  = usageAccess;
      if (deviceAdmin != null)  updates['permission_status.device_admin'] = deviceAdmin;
      updates['permission_status.last_updated'] = Timestamp.fromDate(now);
      try {
        await db.collection('child_devices').doc(deviceId).update(updates);
      } catch (_) {}
    }

    if (service is AndroidServiceInstance) {
      try {
        await service.setForegroundNotificationInfo(
          title:   'SafeChild Active',
          content: 'Last sync: ${_formatTime(now)}',
        );
      } catch (e) {
        debugPrint('BACKGROUND_SVC: Notification update failed: $e');
      }
    }
  } catch (e) {
    debugPrint('BACKGROUND_SVC: _sendHeartbeat generic error: $e');
  }
}

Future<void> _writeUsageStats(
    FirebaseFirestore db, String deviceId, DateTime now) async {
  try {
    final stats = await NativeChannelService.getTodayUsageStats();
    if (stats.isEmpty) return;

    final dateKey = DateFormat('yyyy-MM-dd').format(now);
    final docRef  = db
        .collection('screen_time')
        .doc(deviceId)
        .collection('daily')
        .doc(dateKey);

    final totalMinutes =
        stats.fold<int>(0, (sum, s) => sum + s.usageMinutes);

    await docRef.set({
      'device_id':     deviceId,
      'date':          dateKey,
      'total_minutes': totalMinutes,
      'updated_at':    Timestamp.fromDate(now),
      'apps': stats.map((s) => {
            'package_name':  s.packageName,
            'app_name':      s.appName,
            'usage_minutes': s.usageMinutes,
          }).toList(),
    });
  } catch (_) {}
}

String _formatTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}