// lib/models/notification_model.dart
// ─────────────────────────────────────────────────────────────────────────────
// Maps to Firestore collection: notifications/{notification_id}
// Created when FCM is sent to the parent device.
// Provides a history log of all alerts sent.
//
// Schema (MODULE3_WORKFLOW Part 4):
//   parent_id     – which parent received this notification
//   device_id     – which child device triggered it
//   message_type  – "bypass_alert" | "incident_alert" | "heartbeat_loss"
//   fcm_message_id – FCM delivery receipt ID
//   sent_at        – timestamp
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

enum NotificationMessageType { bypassAlert, incidentAlert, heartbeatLoss }

NotificationMessageType _typeFromString(String? s) {
  switch (s) {
    case 'bypass_alert':   return NotificationMessageType.bypassAlert;
    case 'incident_alert': return NotificationMessageType.incidentAlert;
    default:               return NotificationMessageType.heartbeatLoss;
  }
}

class NotificationModel {
  final String                  notificationId;
  final String                  parentId;
  final String                  deviceId;
  final NotificationMessageType messageType;
  final String?                 fcmMessageId;
  final DateTime                sentAt;

  NotificationModel({
    required this.notificationId,
    required this.parentId,
    required this.deviceId,
    required this.messageType,
    this.fcmMessageId,
    required this.sentAt,
  });

  factory NotificationModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return NotificationModel(
      notificationId: doc.id,
      parentId:       d['parent_id']  ?? '',
      deviceId:       d['device_id']  ?? '',
      messageType:    _typeFromString(d['message_type']),
      fcmMessageId:   d['fcm_message_id'],
      sentAt:         (d['sent_at'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'parent_id':  parentId,
        'device_id':  deviceId,
        'message_type': messageType == NotificationMessageType.bypassAlert
            ? 'bypass_alert'
            : messageType == NotificationMessageType.incidentAlert
                ? 'incident_alert'
                : 'heartbeat_loss',
        if (fcmMessageId != null) 'fcm_message_id': fcmMessageId,
        'sent_at': Timestamp.fromDate(sentAt),
      };

  String get typeLabel {
    switch (messageType) {
      case NotificationMessageType.bypassAlert:   return 'Bypass Alert';
      case NotificationMessageType.incidentAlert: return 'Content Alert';
      case NotificationMessageType.heartbeatLoss: return 'Heartbeat Lost';
    }
  }
}