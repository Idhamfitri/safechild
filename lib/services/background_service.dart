// lib/services/background_service.dart
// Owns ALL heartbeat logic. Survives app kill, cache clear, and reboots.
import 'dart:async';
import 'dart:ui';
import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

// ─────────────────────────────────────────────────────────────────────────────
// Background isolate entry point — runs in a SEPARATE Dart isolate.
// No access to widget tree. Must reinitialise Firebase.
// ─────────────────────────────────────────────────────────────────────────────
@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  // Init Firebase in this isolate
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}

  // Stop command from app
  service.on('stopService').listen((_) => service.stopSelf());

  // First heartbeat immediately
  await _sendHeartbeat(service);

  // Then every 10 minutes
  Timer.periodic(const Duration(minutes: 10), (_) async {
    await _sendHeartbeat(service);
  });
}

// ── Heartbeat ─────────────────────────────────────────────────────────────────
Future<void> _sendHeartbeat(ServiceInstance service) async {
  try {
    final prefs    = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');
    final linkId   = prefs.getString('link_id');

    if (deviceId == null || linkId == null) return;

    final db  = FirebaseFirestore.instance;
    final now = DateTime.now();

    // Real permission states via MethodChannel
    final usageGranted      = await NativeChannelService.checkUsageAccessGranted();
    final accessibilityOn   = await NativeChannelService.checkAccessibilityEnabled();
    final deviceAdminActive = await NativeChannelService.checkDeviceAdminActive();

    // Battery level
    int? batteryLevel;
    try { batteryLevel = await Battery().batteryLevel; } catch (_) {}

    // ── Upsert heartbeat — one doc per device, never duplicates ──────────
    await db.collection('heartbeat').doc(deviceId).set({
      'device_id':            deviceId,
      'last_sync':            Timestamp.fromDate(now),
      'signal_status':        'active',
      'safechild_running':    true,
      'device_admin_active':  deviceAdminActive,
      'accessibility_active': accessibilityOn,
      'usage_access_granted': usageGranted,
      if (batteryLevel != null) 'battery_level': batteryLevel,
    }, SetOptions(merge: true));

    // ── Update child_devices last_seen ────────────────────────────────────
    await db.collection('child_devices').doc(deviceId).update({
      'last_seen': Timestamp.fromDate(now),
    });

    // ── Write usage stats if permission granted ───────────────────────────
    if (usageGranted) {
      await _writeUsageStats(db, deviceId, now);
    }

    // ── Update notification with last sync time ───────────────────────────
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title:   'SafeChild Active',
        content: 'Last sync: ${_formatTime(now)}',
      );
    }
  } catch (_) {
    // Silently continue — never crash the service
  }
}

// ── Usage stats ───────────────────────────────────────────────────────────────
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