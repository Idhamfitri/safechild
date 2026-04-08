// lib/models/heartbeat_model.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HeartbeatModel {
  final String    deviceId;
  final DateTime? lastSync;
  final String    signalStatus;    // 'active' | 'lost'
  final bool      accessibilityActive;

  final int?      batteryLevel;

  HeartbeatModel({
    required this.deviceId,
    this.lastSync,
    this.signalStatus      = 'lost',
    this.accessibilityActive = false,
    this.batteryLevel,
  });

  factory HeartbeatModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return HeartbeatModel(
      deviceId:  doc.id,
      lastSync:  d['last_sync'] != null
          ? (d['last_sync'] as Timestamp).toDate()
          : null,
      signalStatus:         d['signal_status']      ?? 'lost',
      accessibilityActive:  d['accessibility_active'] ?? false,
      batteryLevel:         (d['battery_level'] as num?)?.toInt(),
    );
  }

  /// True only if last heartbeat arrived within the last 15 minutes.
  /// If last_sync is missing or > 15 min old, the device is considered Offline.
  /// This correctly handles: phone off, no internet, app killed.
  bool get isOnline {
    if (lastSync == null) return false;
    return DateTime.now().difference(lastSync!).inMinutes < 15;
  }

  String get lastSeenLabel {
    if (lastSync == null) return 'Never';
    final diff = DateTime.now().difference(lastSync!);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color get statusColor =>
      isOnline ? const Color(0xFF2E7D32) : const Color(0xFF757575);

  String get statusLabel => isOnline ? 'Online' : 'Offline';

  IconData get statusIcon =>
      isOnline ? Icons.circle : Icons.circle_outlined;

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

  static HeartbeatModel empty(String deviceId) => HeartbeatModel(
        deviceId:     deviceId,
        signalStatus: 'lost',
      );
}