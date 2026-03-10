// lib/models/monitoring_setting_model.dart
// ─────────────────────────────────────────────────────────────────────────────
// Maps to Firestore collection: monitoring_settings/{monitor_id}
// One document per parent–child link.
//
// Schema (MODULE3_WORKFLOW Part 4 — exact match):
//   link_id              – references parent_child_links
//   offline_mode         – pause all monitoring temporarily
//   notification_enabled – push notifications to parent enabled
//   updated_at           – server timestamp of last change
//
// Note: Additional settings (SMS, Gemini filter, reward system) will be
// added to the Firestore schema in a later module. They are shown in the
// UI with a "Module 2/3" label and persisted locally until the schema
// is extended.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';

class MonitoringSettingModel {
  // ── Firestore-backed (matches schema exactly) ─────────────────────────────
  final String  linkId;
  final bool    offlineMode;           // pause monitoring
  final bool    notificationEnabled;   // push notifications on/off
  final DateTime? updatedAt;

  // ── Extended settings (stored in Firestore as extra fields for future) ────
  final bool    contentMonitoringEnabled;
  final bool    geminiContentFilterEnabled;
  final bool    smsNotificationEnabled;
  final bool    notifyWhenDeviceOff;

  MonitoringSettingModel({
    required this.linkId,
    this.offlineMode               = false,
    this.notificationEnabled       = true,
    this.updatedAt,
    this.contentMonitoringEnabled  = true,
    this.geminiContentFilterEnabled = true,
    this.smsNotificationEnabled    = false,
    this.notifyWhenDeviceOff       = true,
  });

  factory MonitoringSettingModel.defaults(String linkId) =>
      MonitoringSettingModel(linkId: linkId);

  factory MonitoringSettingModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return MonitoringSettingModel(
      linkId:              doc.id,
      offlineMode:         d['offline_mode']         ?? false,
      notificationEnabled: d['notification_enabled'] ?? true,
      updatedAt: d['updated_at'] != null
          ? (d['updated_at'] as Timestamp).toDate()
          : null,
      // Extended fields (may or may not exist in Firestore yet)
      contentMonitoringEnabled:   d['content_monitoring_enabled']    ?? true,
      geminiContentFilterEnabled: d['gemini_content_filter_enabled'] ?? true,
      smsNotificationEnabled:     d['sms_notification_enabled']      ?? false,
      notifyWhenDeviceOff:        d['notify_when_device_off']        ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        // Core schema fields
        'link_id':              linkId,
        'offline_mode':         offlineMode,
        'notification_enabled': notificationEnabled,
        'updated_at':           FieldValue.serverTimestamp(),
        // Extended fields
        'content_monitoring_enabled':    contentMonitoringEnabled,
        'gemini_content_filter_enabled': geminiContentFilterEnabled,
        'sms_notification_enabled':      smsNotificationEnabled,
        'notify_when_device_off':        notifyWhenDeviceOff,
      };

  MonitoringSettingModel copyWith({
    bool? offlineMode,
    bool? notificationEnabled,
    bool? contentMonitoringEnabled,
    bool? geminiContentFilterEnabled,
    bool? smsNotificationEnabled,
    bool? notifyWhenDeviceOff,
  }) =>
      MonitoringSettingModel(
        linkId:                     linkId,
        offlineMode:                offlineMode               ?? this.offlineMode,
        notificationEnabled:        notificationEnabled        ?? this.notificationEnabled,
        contentMonitoringEnabled:   contentMonitoringEnabled  ?? this.contentMonitoringEnabled,
        geminiContentFilterEnabled: geminiContentFilterEnabled ?? this.geminiContentFilterEnabled,
        smsNotificationEnabled:     smsNotificationEnabled    ?? this.smsNotificationEnabled,
        notifyWhenDeviceOff:        notifyWhenDeviceOff       ?? this.notifyWhenDeviceOff,
      );
}