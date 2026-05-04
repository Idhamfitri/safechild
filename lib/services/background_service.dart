// lib/services/background_service.dart
// Owns ALL heartbeat logic. Survives app kill, cache clear, and reboots.
import 'dart:async';
import 'dart:convert';
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
import '../models/screen_time_models.dart';
import 'package:flutter/material.dart';
import 'package:safechild/models/screen_time_models.dart';
import 'package:safechild/services/native_channel_service.dart';
import 'package:installed_apps/installed_apps.dart';
import 'package:installed_apps/app_info.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';

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

  // Screen Time Lock Enforcement
  final prefs = await SharedPreferences.getInstance();
  final deviceId = prefs.getString('device_id');
  
  if (deviceId != null) {
    Timer.periodic(const Duration(seconds: 10), (_) async {
      await _checkScreenTimeLock(deviceId);
    });
    // Initial check
    await _checkScreenTimeLock(deviceId);
  }

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
    // ── Check permission first using usage_stats package ─────────────────
    // This works in background isolate unlike MethodChannel
    final hasPermission = await UsageStats.checkUsagePermission() ?? false;
    if (!hasPermission) {
      debugPrint('BACKGROUND_SVC: usage access not granted — skipping stats');
      return;
    }

    // ── Query today's usage directly via usage_stats package ─────────────
    final startOfDay = DateTime(now.year, now.month, now.day);
    final rawStats   = await UsageStats.queryUsageStats(startOfDay, now);

    if (rawStats == null || rawStats.isEmpty) {
      debugPrint('BACKGROUND_SVC: no usage stats returned');
      return;
    }

    // ── Filter and map to app usage list ──────────────────────────────────
    final List<Map<String, dynamic>> apps = [];
    for (var s in rawStats) {
      if (s.packageName != null &&
          s.totalTimeInForeground != null &&
          int.tryParse(s.totalTimeInForeground ?? '0') != null &&
          int.parse(s.totalTimeInForeground!) > 60000) {
        
        final usageMs      = int.parse(s.totalTimeInForeground!);
        final usageMinutes = (usageMs / 60000).round();
        final packageName  = s.packageName!;
        final appName      = _friendlyAppName(packageName);

        // Fetch icon memory
        String iconBase64 = '';
        try {
           final appInfo = await InstalledApps.getAppInfo(packageName);
           if (appInfo != null && appInfo.icon != null) {
             iconBase64 = base64Encode(appInfo.icon!);
           }
        } catch (_) {}

        apps.add({
          'package_name':  packageName,
          'app_name':      appName,
          'icon_base64':   iconBase64,
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

    // ── Take top 10 most used apps ────────────────────────────────────────
    final topApps      = apps.take(10).toList();
    final totalMinutes = topApps.fold<int>(
        0, (sum, a) => sum + (a['usage_minutes'] as int));

    // ── Group unimportant apps into "Other" ───────────────────────────────
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

    // ── Hourly Delta Tracking ─────────────────────────────────────────────
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

    // ── Write to screen_time/{deviceId}/daily/{date} ──────────────────────
    await docRef.set({
      'device_id':     deviceId,
      'date':          dateKey,
      'total_minutes': totalMinutes,
      'updated_at':    Timestamp.fromDate(now),
      'hourly_totals': hourlyTotals,
      'apps':          filteredApps,
    });

    // ── Also write most recent app separately for quick access ────────────
    if (topApps.isNotEmpty) {
      await db.collection('child_devices').doc(deviceId).set({
        'recent_apps': topApps.take(5).map((a) => {
              'package_name':  a['package_name'],
              'app_name':      a['app_name'],
              'icon_base64':   a['icon_base64'],
              'usage_minutes': a['usage_minutes'],
            }).toList(),
        'recent_apps_updated_at': Timestamp.fromDate(now),
      }, SetOptions(merge: true));
    }

    debugPrint('BACKGROUND_SVC: usage stats written — $totalMinutes min total, ${topApps.length} apps ✓');
  } catch (e) {
    debugPrint('BACKGROUND_SVC: _writeUsageStats error — $e');
  }
}

// ── Friendly app name helper ──────────────────────────────────────────────
String _friendlyAppName(String packageName) {
  if (packageName.contains('whatsapp'))  return 'WhatsApp';
  if (packageName.contains('chrome'))    return 'Chrome';
  if (packageName.contains('instagram')) return 'Instagram';
  if (packageName.contains('tiktok') || packageName.contains('trill')) return 'TikTok';
  if (packageName.contains('telegram'))  return 'Telegram';
  if (packageName.contains('youtube'))   return 'YouTube';
  if (packageName.contains('facebook')) {
    if (packageName.contains('orca')) return 'Messenger';
    return 'Facebook';
  }
  if (packageName.contains('twitter') || packageName.contains('x.com')) return 'X / Twitter';
  if (packageName.contains('snapchat'))  return 'Snapchat';
  if (packageName.contains('discord'))   return 'Discord';
  if (packageName.contains('reddit'))    return 'Reddit';
  if (packageName.contains('netflix'))   return 'Netflix';
  if (packageName.contains('spotify'))   return 'Spotify';
  final parts = packageName.split('.');
  return parts.isNotEmpty
      ? parts.last[0].toUpperCase() + parts.last.substring(1)
      : packageName;
}

Future<void> _checkScreenTimeLock(String deviceId) async {
  try {
    final db = FirebaseFirestore.instance;
    
    // 1. Get current lock state
    final lockDoc = await db.collection('screen_time_locks').doc(deviceId).get();
    final lock = lockDoc.exists 
        ? ScreenTimeLock.fromFirestore(lockDoc)
        : ScreenTimeLock(lockId: deviceId, deviceId: deviceId, isLocked: false);
        
    // 2. Get active schedules
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
    
    // If we have an active "snooze" period (approved time extension), it overrides the schedule lock temporarily
    if (shouldBeLockedBySchedule && !lock.isLocked && lock.unlockedAt != null && lock.unlockedAt!.isAfter(now)) {
      shouldBeLockedBySchedule = false;
    }
    
    // Evaluate transitions
    if (lock.isLocked && lock.unlockedAt == null) {
      // Parent manual lock supersedes everything. Do not unlock it automatically.
      _bringAppToForeground(hardwareLock: true);
      return;
    }
    
    if (shouldBeLockedBySchedule && (!lock.isLocked || lock.unlockedAt == null)) {
      // Find the end time of the active schedule to set unlocked_at
      DateTime? scheduleEndTime;
      if (activeSchedule != null) {
         final eParts = activeSchedule.endTime.split(':');
         if (eParts.length == 2) {
            scheduleEndTime = DateTime(now.year, now.month, now.day, int.parse(eParts[0]), int.parse(eParts[1]));
            if (scheduleEndTime.isBefore(now)) scheduleEndTime = scheduleEndTime.add(const Duration(days: 1));
         }
      }

      // Transition to Schedule Lock
      await db.collection('screen_time_locks').doc(deviceId).set({
        'device_id': deviceId,
        'is_locked': true,
        'start_time': FieldValue.serverTimestamp(),
        if (scheduleEndTime != null) 'unlocked_at': Timestamp.fromDate(scheduleEndTime),
      }, SetOptions(merge: true));
      // First time catching them with schedule -> hardware lock
      _bringAppToForeground(hardwareLock: true);
    } else if (!shouldBeLockedBySchedule && lock.isLocked && lock.unlockedAt != null) {
      // Transition to Unlock (Schedule over)
      await db.collection('screen_time_locks').doc(deviceId).set({
         'is_locked': false,
         'unlocked_at': FieldValue.delete(),
      }, SetOptions(merge: true));
    } else if (lock.isLocked) {
      // If it's already correctly locked, just annoy them by bringing to foreground.
      // Don't physically shut down the screen again, otherwise they can't even tap Request More Time.
      _bringAppToForeground(hardwareLock: false);
    }

  } catch (e) {
    debugPrint('BACKGROUND_SVC: ScreenTime error = $e');
  }
}

void _bringAppToForeground({bool hardwareLock = false}) async {
  try {
     if (hardwareLock) {
         // Brutally turns off the OS screen requiring PIN/Pattern to wake
         await DevicePolicyManager.lockNow();
         // Give OS 500ms to settle off before we spawn the foreground intent
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