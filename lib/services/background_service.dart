// lib/services/background_service.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'native_channel_service.dart';


const _kNotifChannelId   = 'safechild_monitoring';
const _kNotifChannelName = 'SafeChild Monitoring';
const _kNotifId          = 888;

class BackgroundServiceManager {
  // ── Initialize and start the foreground service ───────────────────────────
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    // Android foreground notification setup
    const notifChannel = AndroidNotificationChannel(
      _kNotifChannelId,
      _kNotifChannelName,
      description: 'SafeChild background monitoring service',
      importance: Importance.low,
    );

    final notifPlugin = FlutterLocalNotificationsPlugin();
    await notifPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(notifChannel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart:             onStart,
        autoStart:           true,
        isForegroundMode:    true,
        notificationChannelId: _kNotifChannelId,
        initialNotificationTitle: 'SafeChild Active',
        initialNotificationContent: 'Protecting this device in the background',
        foregroundServiceNotificationId: _kNotifId,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
        autoStartOnBoot: true,
      ),
      iosConfiguration: IosConfiguration(autoStart: false),
    );

    await service.startService();
  }

  // ── Stop the service (called when device is unlinked) ─────────────────────
  static Future<void> stop() async {
    final service = FlutterBackgroundService();
    service.invoke('stopService');
  }

  // ── Check if service is running ───────────────────────────────────────────
  static Future<bool> isRunning() async {
    return FlutterBackgroundService().isRunning();
  }
}


@pragma('vm:entry-point')
Future<void> onStart(ServiceInstance service) async {
  // Required for background isolate
  DartPluginRegistrant.ensureInitialized();

  // Initialize Firebase in this isolate
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    // Firebase already initialized or options not available
  }

  // Handle stop command from Flutter side
  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  // ── Send first heartbeat immediately on start ─────────────────────────────
  await _sendHeartbeat(service);

  // ── Then repeat every 10 minutes ─────────────────────────────────────────
  Timer.periodic(const Duration(minutes: 10), (_) async {
    await _sendHeartbeat(service);
  });
}

// ─── Core heartbeat logic ─────────────────────────────────────────────────────
Future<void> _sendHeartbeat(ServiceInstance service) async {
  try {
    final prefs    = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');
    final linkId   = prefs.getString('link_id');

    if (deviceId == null || linkId == null) return;

    final db  = FirebaseFirestore.instance;
    final now = DateTime.now();

    // ── Check real permission states via MethodChannel ────────────────────
    final usageGranted      = await NativeChannelService.checkUsageAccessGranted();
    final accessibilityOn   = await NativeChannelService.checkAccessibilityEnabled();
    final deviceAdminActive = await NativeChannelService.checkDeviceAdminActive();

    // ── Write heartbeat document ──────────────────────────────────────────
    await db.collection('heartbeat').add({
      'device_id':            deviceId,
      'timestamp':            Timestamp.fromDate(now),
      'signal_status':        'active',
      'safechild_running':    true,
      'device_admin_active':  deviceAdminActive,
      'accessibility_active': accessibilityOn,
      'usage_access_granted': usageGranted,
    });

    // ── Update child_devices last_seen ────────────────────────────────────
    await db.collection('child_devices').doc(deviceId).update({
      'last_seen': Timestamp.fromDate(now),
    });

    // ── Query and write usage stats ───────────────────────────────────────
    if (usageGranted) {
      await _writeUsageStats(db, deviceId, now);
    }

    // Update service notification to show last heartbeat time
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'SafeChild Active',
        content: 'Last check: ${_formatTime(now)}',
      );
    }
  } catch (e) {
    // Silently continue — do not crash the service
  }
}

// ─── Write usage stats to Firestore ──────────────────────────────────────────
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
      'device_id':      deviceId,
      'date':           dateKey,
      'total_minutes':  totalMinutes,
      'updated_at':     Timestamp.fromDate(now),
      'apps': stats.map((s) => {
            'package_name': s.packageName,
            'app_name':     s.appName,
            'usage_minutes': s.usageMinutes,
          }).toList(),
    });
  } catch (_) {

  }
}

String _formatTime(DateTime dt) {
  final h  = dt.hour.toString().padLeft(2, '0');
  final m  = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}