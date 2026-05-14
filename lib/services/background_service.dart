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
import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import '../models/screen_time_models.dart';
import '../utils/app_utils.dart';

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
  // 1. Ensure flutter bindings are available in this isolate
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // Suppress the continuous "FlutterJNI detached" warnings from the
  // flutter_accessibility_service plugin. DartPluginRegistrant registers ALL
  // plugins including the accessibility service, so the native
  // AccessibilityService tries to deliver events to this background engine
  // too. Since bypass detection only runs in the main UI isolate we register
  // a no-op binary message handler here so the native side always finds a
  // live receiver and never hits a detached JNI.
  try {
    WidgetsBinding.instance.defaultBinaryMessenger
        .setMessageHandler('x-slayer/accessibility_event', (_) async => null);
  } catch (_) {}

  // 2. Init Firebase in this isolate
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}

  debugPrint('BACKGROUND_SVC: Service started in background isolate');
  
  service.on('stopService').listen((_) {
    debugPrint('BACKGROUND_SVC: Stopping service...');
    service.stopSelf();
  });

  final prefs = await SharedPreferences.getInstance();
  final deviceId = prefs.getString('device_id');
  if (deviceId == null) {
    debugPrint('BACKGROUND_SVC: No device ID found, stopping.');
    service.stopSelf();
    return;
  }

  bool isCurrentlyLocked = false;
  bool isManualLock = false;

  // ── 0. Listen for Unlink — background safety net ────────────────────────
  // The UI isolate (ChildActiveScreen) also listens, but that listener is
  // throttled by Android when the app is backgrounded. This listener survives
  // in the foreground service isolate and acts as the reliable fallback.
  FirebaseFirestore.instance
      .collection('parent_child_links')
      .where('device_id', isEqualTo: deviceId)
      .snapshots()
      .listen((snap) async {
    final hasActive = snap.docs.any((doc) {
      final d = doc.data();
      return d['link_status'] == 'active' && d['pairing_status'] != 'expired';
    });
    if (!hasActive) {
      debugPrint('BACKGROUND_SVC: No active links detected — stopping service.');
      final p = await SharedPreferences.getInstance();
      await p.remove('role');
      await p.remove('link_id');
      await p.remove('device_id');
      service.stopSelf();
    }
  }, onError: (_) {});

  // ── 1. Listen for Lock State changes (Instant response) ─────────────────
  FirebaseFirestore.instance
      .collection('screen_time_locks')
      .doc(deviceId)
      .snapshots()
      .listen((snap) {
    if (snap.exists) {
      final lock = ScreenTimeLock.fromFirestore(snap);
      isCurrentlyLocked = lock.isLocked;
      isManualLock = lock.unlockedAt == null;
      _checkScreenTimeLock(deviceId);
    }
  });

  // ── 2. Listen for Schedule changes ─────────────────────────────────────
  FirebaseFirestore.instance
      .collection('screen_time_schedules')
      .where('device_id', isEqualTo: deviceId)
      .snapshots()
      .listen((_) {
    _checkScreenTimeLock(deviceId);
  });

  // ── 3. High-frequency Enforcement + FCM flag poll (Every 3 seconds) ─────
  // When Android Doze throttles the Firestore WebSocket, the FCM background
  // handler writes flags to SharedPreferences. This timer reads them so the
  // response time stays under 3 seconds even when backgrounded.
  Timer.periodic(const Duration(seconds: 3), (_) async {
    final p = await SharedPreferences.getInstance();

    // FCM-triggered unlink (written by _onFcmBackground in main.dart)
    if (p.getBool('fcm_unlink_pending') == true) {
      debugPrint('BACKGROUND_SVC: FCM unlink signal — stopping service.');
      await p.remove('fcm_unlink_pending');
      service.stopSelf();
      return;
    }

    // FCM-triggered lock change
    final fcmLock = p.get('fcm_lock_pending');
    if (fcmLock != null) {
      final locked = fcmLock == true;
      debugPrint('BACKGROUND_SVC: FCM lock signal: isLocked=$locked');
      await p.remove('fcm_lock_pending');
      isCurrentlyLocked = locked;
      isManualLock = p.getBool('fcm_lock_is_manual') ?? true;
      await p.remove('fcm_lock_is_manual');
    }

    if (isCurrentlyLocked) {
      await _enforceForegroundIfLocked(deviceId, isManualLock: isManualLock);
    }
  });

  // ── 4. Periodic Schedule Check (Every 15 seconds) ──────────────────────
  Timer.periodic(const Duration(seconds: 15), (_) async {
    await _checkScreenTimeLock(deviceId);
  });

  // ── 5. Heartbeat & Stats (Every 10 minutes) ────────────────────────────
  Timer.periodic(const Duration(minutes: 10), (_) async {
    await _sendHeartbeat(service);
  });

  // Initial checks
  await _sendHeartbeat(service);
  await _checkScreenTimeLock(deviceId);
}

Future<void> _sendHeartbeat(ServiceInstance service) async {
  try {
    final prefs    = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');
    final linkId   = prefs.getString('link_id');

    if (deviceId == null || linkId == null) return;

    final db  = FirebaseFirestore.instance;
    final now = DateTime.now();

    // Battery level
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

    // Write today's usage stats
    try {
      await _writeUsageStats(db, deviceId, now);
    } catch (e) {
      debugPrint('BACKGROUND_SVC: Usage stats Firestore write failed: $e');
    }

    // ── Re-check permissions 
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
    final hasPermission = await UsageStats.checkUsagePermission() ?? false;
    if (!hasPermission) {
      debugPrint('BACKGROUND_SVC: usage access not granted — skipping stats');
      return;
    }

    final startOfDay = DateTime(now.year, now.month, now.day);
    final rawStats   = await UsageStats.queryUsageStats(startOfDay, now);

    if (rawStats == null || rawStats.isEmpty) {
      debugPrint('BACKGROUND_SVC: no usage stats returned');
      return;
    }

    final List<Map<String, dynamic>> apps = [];
    for (var s in rawStats) {
      if (s.packageName != null &&
          s.totalTimeInForeground != null &&
          int.tryParse(s.totalTimeInForeground ?? '0') != null &&
          int.parse(s.totalTimeInForeground!) > 60000) {
        
        final usageMs      = int.parse(s.totalTimeInForeground!);
        final usageMinutes = (usageMs / 60000).round();
        final packageName  = s.packageName!;
        final appName      = AppUtils.getFriendlyAppName(packageName);

        apps.add({
          'package_name':  packageName,
          'app_name':      appName,
          'usage_minutes': usageMinutes,
          'usage_ms':      usageMs,
        });
      }
    }

    apps.sort((a, b) => (b['usage_ms'] as int).compareTo(a['usage_ms'] as int));

    if (apps.isEmpty) {
      debugPrint('BACKGROUND_SVC: no apps with usage > 1 min');
      return;
    }

    final topApps      = apps.take(10).toList();
    final totalMinutes = topApps.fold<int>(
        0, (sum, a) => sum + (a['usage_minutes'] as int));

    final importantApps = ['WhatsApp', 'Chrome', 'Instagram', 'TikTok', 'Telegram', 'YouTube', 'Facebook', 'Messenger', 'X / Twitter', 'Snapchat', 'Discord', 'Reddit', 'Netflix', 'Spotify'];
    final filteredApps = <Map<String, dynamic>>[];
    int totalOtherMinutes = 0;

    for (var a in topApps) {
      if (importantApps.contains(a['app_name'])) {
        filteredApps.add(a);
      } else {
        totalOtherMinutes += (a['usage_minutes'] as int);
      }
    }

    if (totalOtherMinutes > 0) {
      filteredApps.add({
        'package_name': 'com.other.apps',
        'app_name': 'Other',
        'icon_base64': '',
        'usage_minutes': totalOtherMinutes,
      });
    }

    final dateKey = DateFormat('yyyy-MM-dd').format(now);
    final docRef = db.collection('screen_time').doc(deviceId).collection('daily').doc(dateKey);

    List<int> hourlyTotals = List.filled(24, 0);
    int previousTotal = 0;

    try {
      final docSnap = await docRef.get();
      if (docSnap.exists) {
        final data = docSnap.data()!;
        previousTotal = (data['total_minutes'] as num?)?.toInt() ?? 0;
        final existingHourly = (data['hourly_totals'] as List<dynamic>? ?? []).cast<int>();
        if (existingHourly.length == 24) {
          hourlyTotals = List<int>.from(existingHourly);
        }
      }
    } catch (_) {}

    final deltaMinutes = totalMinutes - previousTotal;
    if (deltaMinutes > 0) {
      hourlyTotals[now.hour] += deltaMinutes;
    }

    await docRef.set({
      'device_id':     deviceId,
      'date':          dateKey,
      'total_minutes': totalMinutes,
      'updated_at':    Timestamp.fromDate(now),
      'hourly_totals': hourlyTotals,
      'apps':          filteredApps,
    });

    if (topApps.isNotEmpty) {
      await db.collection('child_devices').doc(deviceId).set({
        'recent_apps': topApps.take(5).map((a) => {
              'package_name':  a['package_name'],
              'app_name':      a['app_name'],
              'usage_minutes': a['usage_minutes'],
            }).toList(),
        'recent_apps_updated_at': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    }

    debugPrint('BACKGROUND_SVC: usage stats written — $totalMinutes min total ✓');
  } catch (e) {
    debugPrint('BACKGROUND_SVC: _writeUsageStats error — $e');
  }
}

Future<void> _checkScreenTimeLock(String deviceId) async {
  try {
    final db = FirebaseFirestore.instance;
    
    final lockDoc = await db.collection('screen_time_locks').doc(deviceId).get();
    final lock = lockDoc.exists 
        ? ScreenTimeLock.fromFirestore(lockDoc)
        : ScreenTimeLock(lockId: deviceId, deviceId: deviceId, isLocked: false);
        
    final schedDocs = await db.collection('screen_time_schedules')
        .where('device_id', isEqualTo: deviceId)
        .where('is_active', isEqualTo: true)
        .get();
        
    final schedules = schedDocs.docs.map(ScreenTimeSchedule.fromFirestore).toList();
    
    final now = DateTime.now();
    final timeOfDay = TimeOfDay(hour: now.hour, minute: now.minute);
    final weekday = now.weekday;
    
    bool shouldBeLockedBySchedule = false;
    ScreenTimeSchedule? activeSchedule;
    for (var s in schedules) {
      if (s.contains(timeOfDay, weekday)) {
        shouldBeLockedBySchedule = true;
        activeSchedule = s;
        break;
      }
    }
    
    if (shouldBeLockedBySchedule && !lock.isLocked && lock.unlockedAt != null && lock.unlockedAt!.isAfter(now)) {
      shouldBeLockedBySchedule = false;
    }
    
    if (lock.isLocked && lock.unlockedAt == null) {
      _bringAppToForeground(hardwareLock: true);
      return;
    }
    
    if (shouldBeLockedBySchedule && (!lock.isLocked || lock.unlockedAt == null)) {
      DateTime? scheduleEndTime;
      if (activeSchedule != null) {
         final eParts = activeSchedule.endTime.split(':');
         if (eParts.length == 2) {
            scheduleEndTime = DateTime(now.year, now.month, now.day, int.parse(eParts[0]), int.parse(eParts[1]));
            if (scheduleEndTime.isBefore(now)) scheduleEndTime = scheduleEndTime.add(const Duration(days: 1));
         }
      }

      await db.collection('screen_time_locks').doc(deviceId).set({
        'device_id': deviceId,
        'is_locked': true,
        'start_time': FieldValue.serverTimestamp(),
        if (scheduleEndTime != null) 'unlocked_at': Timestamp.fromDate(scheduleEndTime),
      }, SetOptions(merge: true));
      _bringAppToForeground(hardwareLock: true);
    } else if (!shouldBeLockedBySchedule && lock.isLocked && lock.unlockedAt != null) {
      await db.collection('screen_time_locks').doc(deviceId).set({
         'is_locked': false,
         'unlocked_at': FieldValue.delete(),
      }, SetOptions(merge: true));
    } else if (lock.isLocked) {
      _bringAppToForeground(hardwareLock: false);
    }

  } catch (e) {
    debugPrint('BACKGROUND_SVC: ScreenTime error = $e');
  }
}

Future<void> _enforceForegroundIfLocked(String deviceId, {required bool isManualLock}) async {
  try {
    final now = DateTime.now();
    final start = now.subtract(const Duration(seconds: 10));
    final stats = await UsageStats.queryUsageStats(start, now);
    
    if (stats != null && stats.isNotEmpty) {
      stats.sort((a, b) => b.lastTimeUsed!.compareTo(a.lastTimeUsed!));
      final topApp = stats.first.packageName;
      
      if (topApp != 'com.safechild.safechild') {
        debugPrint('BACKGROUND_SVC: Locked but top app is $topApp. Bringing SafeChild back.');
        _bringAppToForeground(hardwareLock: isManualLock);
      }
    }
  } catch (_) {}
}

void _bringAppToForeground({bool hardwareLock = false}) async {
  try {
     if (hardwareLock) {
         await DevicePolicyManager.lockNow();
         await Future.delayed(const Duration(milliseconds: 500));
     }

     const intent = AndroidIntent(
        action: 'android.intent.action.MAIN',
        package: 'com.safechild.safechild',
        componentName: 'com.safechild.safechild.MainActivity',
        flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
  } catch (_) {}
}

String _formatTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}