// lib/models/heartbeat_model.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum HeartbeatStatus { active, lost, unknown }

extension HeartbeatStatusX on HeartbeatStatus {
  Color get statusColor {
    switch (this) {
      case HeartbeatStatus.active:  return const Color(0xFF2E7D32);
      case HeartbeatStatus.lost:    return const Color(0xFFC62828);
      case HeartbeatStatus.unknown: return const Color(0xFF757575);
    }
  }

  IconData get statusIcon {
    switch (this) {
      case HeartbeatStatus.active:  return Icons.favorite;
      case HeartbeatStatus.lost:    return Icons.heart_broken;
      case HeartbeatStatus.unknown: return Icons.help_outline;
    }
  }

  String get statusLabel {
    switch (this) {
      case HeartbeatStatus.active:  return 'Online';
      case HeartbeatStatus.lost:    return 'Offline';
      case HeartbeatStatus.unknown: return 'Unknown';
    }
  }
}

class HeartbeatModel {
  final String          heartbeatId;
  final String          deviceId;
  final DateTime        timestamp;
  final HeartbeatStatus signalStatus;
  final bool            safecheckRunning;
  final bool            deviceAdminActive;
  final bool            accessibilityActive;
  final int?            batteryLevel;   // NEW — 0 to 100, null if unavailable

  HeartbeatModel({
    required this.heartbeatId,
    required this.deviceId,
    required this.timestamp,
    required this.signalStatus,
    required this.safecheckRunning,
    required this.deviceAdminActive,
    required this.accessibilityActive,
    this.batteryLevel,
  });

  factory HeartbeatModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return HeartbeatModel(
      heartbeatId:         doc.id,
      deviceId:            d['device_id']           ?? '',
      timestamp:           (d['timestamp'] as Timestamp).toDate(),
      signalStatus:        (d['signal_status'] == 'active')
          ? HeartbeatStatus.active
          : HeartbeatStatus.lost,
      safecheckRunning:    d['safechild_running']    ?? false,
      deviceAdminActive:   d['device_admin_active']  ?? false,
      accessibilityActive: d['accessibility_active'] ?? false,
      batteryLevel:        d['battery_level'] as int?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'device_id':           deviceId,
        'timestamp':           FieldValue.serverTimestamp(),
        'signal_status':       signalStatus == HeartbeatStatus.active ? 'active' : 'lost',
        'safechild_running':   safecheckRunning,
        'device_admin_active': deviceAdminActive,
        'accessibility_active': accessibilityActive,
        if (batteryLevel != null) 'battery_level': batteryLevel,
      };

  // ── Helpers for UI ────────────────────────────────────────────────────────
  Color get statusColor  => signalStatus.statusColor;
  IconData get statusIcon => signalStatus.statusIcon;
  String get statusLabel => signalStatus.statusLabel;

  bool get isOnline => signalStatus == HeartbeatStatus.active;

  // How long since last heartbeat
  String get lastSeenLabel {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 1)  return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // Battery icon based on level
  IconData get batteryIcon {
    if (batteryLevel == null) return Icons.battery_unknown;
    if (batteryLevel! >= 80)  return Icons.battery_full;
    if (batteryLevel! >= 60)  return Icons.battery_5_bar;
    if (batteryLevel! >= 40)  return Icons.battery_3_bar;
    if (batteryLevel! >= 20)  return Icons.battery_2_bar;
    return Icons.battery_alert;
  }

  Color get batteryColor {
    if (batteryLevel == null) return const Color(0xFF757575);
    if (batteryLevel! >= 40)  return const Color(0xFF2E7D32);
    if (batteryLevel! >= 20)  return const Color(0xFFE65100);
    return const Color(0xFFC62828);
  }

  // ── Dummy — shown before first real heartbeat arrives ────────────────────
  static HeartbeatModel dummy(String deviceId) => HeartbeatModel(
        heartbeatId:         'dummy',
        deviceId:            deviceId,
        timestamp:           DateTime.now().subtract(const Duration(minutes: 3)),
        signalStatus:        HeartbeatStatus.unknown,
        safecheckRunning:    false,
        deviceAdminActive:   false,
        accessibilityActive: false,
        batteryLevel:        null,
      );
}