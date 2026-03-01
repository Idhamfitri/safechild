// lib/models/heartbeat_model.dart
// ─────────────────────────────────────────────────────────────────────────────
// Maps to Firestore collection: heartbeat/{heartbeat_id}
// One NEW document is written every 10 minutes by the child device
// foreground service (Module 3). The parent app queries the LATEST document
// for a given device_id (orderBy timestamp desc, limit 1).
//
// Schema (matches MODULE3_WORKFLOW.md Part 4):
//   device_id            – links to child_devices/{device_id}
//   timestamp            – when this heartbeat was sent
//   signal_status        – "active" | "lost"
//   safechild_running    – true if foreground service is alive
//   device_admin_active  – DevicePolicyManager.isAdminActive()
//   accessibility_active – AccessibilityManager.isEnabled()
//
// Dashboard colour logic (Part 7 business rules):
//   GREEN  — last heartbeat < 12 minutes ago
//   YELLOW — last heartbeat 12–20 minutes ago
//   RED    — last heartbeat > 20 minutes ago
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Signal states written to Firestore
enum SignalStatus { active, lost }

// Dashboard colour derived from last-seen age
enum HeartbeatStatus { green, yellow, red }

class HeartbeatModel {
  final String        heartbeatId;
  final String        deviceId;
  final DateTime      timestamp;
  final SignalStatus  signalStatus;
  final bool          safechildRunning;
  final bool          deviceAdminActive;
  final bool          accessibilityActive;

  HeartbeatModel({
    required this.heartbeatId,
    required this.deviceId,
    required this.timestamp,
    required this.signalStatus,
    required this.safechildRunning,
    required this.deviceAdminActive,
    required this.accessibilityActive,
  });

  // ── Firestore deserialization ─────────────────────────────────────────────
  factory HeartbeatModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return HeartbeatModel(
      heartbeatId:         doc.id,
      deviceId:            d['device_id']  ?? '',
      timestamp:           (d['timestamp'] as Timestamp).toDate(),
      signalStatus:        d['signal_status'] == 'lost'
          ? SignalStatus.lost
          : SignalStatus.active,
      safechildRunning:    d['safechild_running']    ?? false,
      deviceAdminActive:   d['device_admin_active']   ?? false,
      accessibilityActive: d['accessibility_active']  ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'device_id':            deviceId,
        'timestamp':            Timestamp.fromDate(timestamp),
        'signal_status':        signalStatus == SignalStatus.active ? 'active' : 'lost',
        'safechild_running':    safechildRunning,
        'device_admin_active':  deviceAdminActive,
        'accessibility_active': accessibilityActive,
      };

  // ── Dummy data (used until Module 3 child service writes real heartbeats) ──
  factory HeartbeatModel.dummy(String deviceId) => HeartbeatModel(
        heartbeatId:         'dummy',
        deviceId:            deviceId,
        timestamp:           DateTime.now().subtract(const Duration(minutes: 3)),
        signalStatus:        SignalStatus.active,
        safechildRunning:    true,
        deviceAdminActive:   true,
        accessibilityActive: true,
      );

  // ── Business rule: dashboard colour (Part 7, MODULE3_WORKFLOW) ────────────
  HeartbeatStatus get dashboardStatus {
    final age = DateTime.now().difference(timestamp).inMinutes;
    if (age < 12)  return HeartbeatStatus.green;
    if (age <= 20) return HeartbeatStatus.yellow;
    return HeartbeatStatus.red;
  }

  // ── Derived display properties ────────────────────────────────────────────
  bool get isOnline => dashboardStatus != HeartbeatStatus.red
      && signalStatus == SignalStatus.active;

  Color get statusColor {
    switch (dashboardStatus) {
      case HeartbeatStatus.green:  return const Color(0xFF1A7F64);
      case HeartbeatStatus.yellow: return const Color(0xFFF9A825);
      case HeartbeatStatus.red:    return const Color(0xFFD32F2F);
    }
  }

  String get statusLabel {
    switch (dashboardStatus) {
      case HeartbeatStatus.green:  return 'Online';
      case HeartbeatStatus.yellow: return 'Delayed';
      case HeartbeatStatus.red:    return 'Offline';
    }
  }

  IconData get statusIcon {
    switch (dashboardStatus) {
      case HeartbeatStatus.green:  return Icons.check_circle_outline;
      case HeartbeatStatus.yellow: return Icons.warning_amber_outlined;
      case HeartbeatStatus.red:    return Icons.cancel_outlined;
    }
  }

  String get lastSeenText {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}