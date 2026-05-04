// lib/models/monitoring_setting_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class MonitoringSettingModel {
 
  final String  linkId;
  final bool    offlineMode;           
  final bool    notificationEnabled;   
  final DateTime? updatedAt;

  // ── Extended settings 
  final bool    contentMonitoringEnabled;
  final bool    geminiContentFilterEnabled;
  final bool    smsNotificationEnabled;
  final bool    notifyWhenDeviceOff;
  final bool    bypassDetectionEnabled; // Added field

  MonitoringSettingModel({
    required this.linkId,
    this.offlineMode               = false,
    this.notificationEnabled       = true,
    this.updatedAt,
    this.contentMonitoringEnabled  = true,
    this.geminiContentFilterEnabled = true,
    this.smsNotificationEnabled    = false,
    this.notifyWhenDeviceOff       = true,
    this.bypassDetectionEnabled    = true, // Default to true
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
     
      contentMonitoringEnabled:   d['content_monitoring_enabled']    ?? true,
      geminiContentFilterEnabled: d['gemini_content_filter_enabled'] ?? true,
      smsNotificationEnabled:     d['sms_notification_enabled']      ?? false,
      notifyWhenDeviceOff:        d['notify_when_device_off']        ?? true,
      bypassDetectionEnabled:     d['bypass_detection_enabled']     ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
      
        'link_id':              linkId,
        'offline_mode':         offlineMode,
        'notification_enabled': notificationEnabled,
        'updated_at':           FieldValue.serverTimestamp(),
       
        'content_monitoring_enabled':    contentMonitoringEnabled,
        'gemini_content_filter_enabled': geminiContentFilterEnabled,
        'sms_notification_enabled':      smsNotificationEnabled,
        'notify_when_device_off':        notifyWhenDeviceOff,
        'bypass_detection_enabled':      bypassDetectionEnabled,
      };

  MonitoringSettingModel copyWith({
    bool? offlineMode,
    bool? notificationEnabled,
    bool? contentMonitoringEnabled,
    bool? geminiContentFilterEnabled,
    bool? smsNotificationEnabled,
    bool? notifyWhenDeviceOff,
    bool? bypassDetectionEnabled,
  }) =>
      MonitoringSettingModel(
        linkId:                     linkId,
        offlineMode:                offlineMode               ?? this.offlineMode,
        notificationEnabled:        notificationEnabled        ?? this.notificationEnabled,
        contentMonitoringEnabled:   contentMonitoringEnabled  ?? this.contentMonitoringEnabled,
        geminiContentFilterEnabled: geminiContentFilterEnabled ?? this.geminiContentFilterEnabled,
        smsNotificationEnabled:     smsNotificationEnabled    ?? this.smsNotificationEnabled,
        notifyWhenDeviceOff:        notifyWhenDeviceOff       ?? this.notifyWhenDeviceOff,
        bypassDetectionEnabled:     bypassDetectionEnabled    ?? this.bypassDetectionEnabled,
      );
}