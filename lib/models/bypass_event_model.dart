// lib/models/bypass_event_model.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum BypassEventType {
  settingsOpened,    // child opened general settings — log only
  deviceTampering,   // child tried to tamper permissions — alert
  uninstallAttempt,
  settingsAccess,
  permissionRevoked,
  heartbeatLoss,
  safeModeBoot,
}

extension BypassEventTypeX on BypassEventType {
  String get firestoreValue {
    switch (this) {
      case BypassEventType.settingsOpened:   return 'settings_opened';
      case BypassEventType.deviceTampering:  return 'device_tampering';
      case BypassEventType.uninstallAttempt: return 'uninstall_attempt';
      case BypassEventType.settingsAccess:   return 'settings_access';
      case BypassEventType.permissionRevoked: return 'permission_revoked';
      case BypassEventType.heartbeatLoss:    return 'heartbeat_loss';
      case BypassEventType.safeModeBoot:     return 'safe_mode_boot';
    }
  }

  String get displayLabel {
    switch (this) {
      case BypassEventType.settingsOpened:   return 'Open Setting';
      case BypassEventType.deviceTampering:  return 'Device Tampering Detected';
      case BypassEventType.uninstallAttempt: return 'Uninstall Attempt';
      case BypassEventType.settingsAccess:   return 'Settings Access';
      case BypassEventType.permissionRevoked: return 'Permission Revoked';
      case BypassEventType.heartbeatLoss:    return 'Heartbeat Lost';
      case BypassEventType.safeModeBoot:     return 'Safe Mode Detected';
    }
  }

  IconData get icon {
    switch (this) {
      case BypassEventType.settingsOpened:   return Icons.settings_outlined;
      case BypassEventType.deviceTampering:  return Icons.security_outlined;
      case BypassEventType.uninstallAttempt: return Icons.delete_sweep_outlined;
      case BypassEventType.settingsAccess:   return Icons.settings_outlined;
      case BypassEventType.permissionRevoked: return Icons.no_encryption_outlined;
      case BypassEventType.heartbeatLoss:    return Icons.heart_broken_outlined;
      case BypassEventType.safeModeBoot:     return Icons.phonelink_off_outlined;
    }
  }

  Color get color {
    switch (this) {
      case BypassEventType.settingsOpened:  return const Color(0xFF1565C0);
      case BypassEventType.deviceTampering: return const Color(0xFFD32F2F);
      default:                              return const Color(0xFFD32F2F);
    }
  }
}

BypassEventType _typeFromString(String? s) {
  switch (s) {
    case 'settings_opened':    return BypassEventType.settingsOpened;
    case 'device_tampering':   return BypassEventType.deviceTampering;
    case 'uninstall_attempt':  return BypassEventType.uninstallAttempt;
    case 'settings_access':    return BypassEventType.settingsAccess;
    case 'permission_settings_opened': return BypassEventType.settingsOpened;
    case 'permission_revoked': return BypassEventType.permissionRevoked;
    case 'heartbeat_loss':     return BypassEventType.heartbeatLoss;
    case 'safe_mode_boot':     return BypassEventType.safeModeBoot;
    default:                   return BypassEventType.deviceTampering;
  }
}

class BypassEventModel {
  final String         bypassId;
  final String         deviceId;
  final BypassEventType eventType;
  final String         eventDescription;
  final bool           isBlocked;
  final bool           isReviewed;
  final bool           isAlertSend;
  final DateTime?      alertSendAt;
  final DateTime       detectedAt;

  BypassEventModel({
    required this.bypassId,
    required this.deviceId,
    required this.eventType,
    required this.eventDescription,
    required this.isBlocked,
    required this.isReviewed,
    required this.isAlertSend,
    this.alertSendAt,
    required this.detectedAt,
  });

  factory BypassEventModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return BypassEventModel(
      bypassId:         doc.id,
      deviceId:         d['device_id'] ?? '',
      eventType:        _typeFromString(d['event_type']),
      eventDescription: d['event_description'] ?? '',
      isBlocked:        d['is_blocked']    ?? false,
      isReviewed:       d['is_reviewed']   ?? false,
      isAlertSend:      d['is_alert_send'] ?? false,
      alertSendAt: d['alert_send_at'] != null
          ? (d['alert_send_at'] as Timestamp).toDate()
          : null,
      detectedAt: d['detected_at'] != null 
          ? (d['detected_at'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'device_id':         deviceId,
        'event_type':        eventType.firestoreValue,
        'event_description': eventDescription,
        'is_blocked':        isBlocked,
        'is_reviewed':       isReviewed,
        'is_alert_send':     isAlertSend,
        if (alertSendAt != null) 'alert_send_at': Timestamp.fromDate(alertSendAt!),
        'detected_at':       Timestamp.fromDate(detectedAt),
      };

  // ── Dummy events
  static List<BypassEventModel> dummies(String deviceId) {
    final now = DateTime.now();
    return [
      BypassEventModel(
        bypassId: 'd1', deviceId: deviceId,
        eventType: BypassEventType.uninstallAttempt,
        eventDescription: 'Child attempted to uninstall SafeChild',
        isBlocked: true, isReviewed: false, isAlertSend: true,
        alertSendAt: now.subtract(const Duration(hours: 2, minutes: 35)),
        detectedAt:  now.subtract(const Duration(hours: 2, minutes: 35)),
      ),
      BypassEventModel(
        bypassId: 'd2', deviceId: deviceId,
        eventType: BypassEventType.settingsAccess,
        eventDescription: 'Child attempted to open Settings app',
        isBlocked: true, isReviewed: false, isAlertSend: true,
        alertSendAt: now.subtract(const Duration(hours: 4, minutes: 30)),
        detectedAt:  now.subtract(const Duration(hours: 4, minutes: 30)),
      ),
      BypassEventModel(
        bypassId: 'd3', deviceId: deviceId,
        eventType: BypassEventType.permissionRevoked,
        eventDescription: 'Accessibility Service was disabled by child',
        isBlocked: false, isReviewed: true, isAlertSend: true,
        detectedAt: now.subtract(const Duration(days: 1, hours: 3)),
      ),
    ];
  }
}