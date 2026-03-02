// lib/services/native_channel_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Dart wrapper around the NativeHelperPlugin MethodChannel.
// Provides typed methods for permission checking and usage stats.
//
// Channel: "com.safechild/native_helper"
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/services.dart';

class NativeChannelService {
  static const _channel = MethodChannel('com.safechild/native_helper');

  // ── Permission checks ─────────────────────────────────────────────────────
  // All return false on any error (safe default — don't mark as granted).

  /// Checks PACKAGE_USAGE_STATS via AppOpsManager.
  static Future<bool> checkUsageAccessGranted() async {
    try {
      return await _channel.invokeMethod<bool>('checkUsageAccessGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if SafeChildAccessibilityService is in ENABLED_ACCESSIBILITY_SERVICES.
  /// Returns false until Module 3 creates the accessibility service class.
  static Future<bool> checkAccessibilityEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('checkAccessibilityEnabled') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Checks if SafeChildDeviceAdminReceiver is an active device admin.
  /// Returns false until Module 3 creates the device admin receiver class.
  static Future<bool> checkDeviceAdminActive() async {
    try {
      return await _channel.invokeMethod<bool>('checkDeviceAdminActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Usage stats ───────────────────────────────────────────────────────────
  /// Returns top 10 apps used today sorted by usage time (descending).
  /// Returns empty list if PACKAGE_USAGE_STATS not granted.
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
  final Duration usageTime;

  AppUsageStat({
    required this.packageName,
    required this.appName,
    required this.usageTime,
  });

  factory AppUsageStat.fromMap(Map<String, dynamic> map) => AppUsageStat(
        packageName: map['packageName'] as String? ?? '',
        appName:     map['appName']     as String? ?? map['packageName'] as String? ?? '',
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