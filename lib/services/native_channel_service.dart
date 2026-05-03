// lib/services/native_channel_service.dart


import 'package:flutter/services.dart';

class NativeChannelService {
  static const _channel = MethodChannel('com.safechild/native_helper');

  // ── Permission checks ─────────────────────────────────────────────────────
  // All return false on any error (safe default — don't mark as granted).


  static Future<bool> checkUsageAccessGranted() async {
    try {
      return await _channel.invokeMethod<bool>('checkUsageAccessGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> checkAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('checkAccessibilityEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> checkDeviceAdminActive() async {
    try {
      return await _channel.invokeMethod<bool>('checkDeviceAdminActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Usage stats ───────────────────────────────────────────────────────────
  static Future<List<AppUsageStat>> getTodayUsageStats() async {
    try {
      final now   = DateTime.now();
      final start = DateTime(now.year, now.month, now.day); // midnight today

      final raw = await _channel.invokeMethod<List>('getUsageStats', {
        'startMs': start.millisecondsSinceEpoch,
        'endMs':   now.millisecondsSinceEpoch,
      });

      if (raw == null) return [];
      return raw
          .map((item) => AppUsageStat.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

// ─── App usage data class ─────────────────────────────────────────────────────
class AppUsageStat {
  final String packageName;
  final String appName;
  final String iconBase64;
  final Duration usageTime;

  AppUsageStat({
    required this.packageName,
    required this.appName,
    required this.iconBase64,
    required this.usageTime,
  });

  factory AppUsageStat.fromMap(Map<String, dynamic> map) => AppUsageStat(
        packageName: map['packageName'] as String? ?? '',
        appName:     map['appName']     as String? ?? map['packageName'] as String? ?? '',
        iconBase64:  map['iconBase64']  as String? ?? '',
        usageTime:   Duration(
            milliseconds: (map['usageMs'] as num?)?.toInt() ?? 0),
      );

  String get usageText {
    final h = usageTime.inHours;
    final m = usageTime.inMinutes % 60;
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  int get usageMinutes => usageTime.inMinutes;
}