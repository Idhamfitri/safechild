// lib/models/child_device_model.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PermissionStatus {
  final bool      accessibility;
  final bool      deviceAdmin;
  final bool      notifications;
  final bool      overlay;
  final bool      usageAccess;
  final DateTime? lastUpdated;

  PermissionStatus({
    this.accessibility = false,
    this.deviceAdmin   = false,
    this.notifications = false,
    this.overlay       = false,
    this.usageAccess   = false,
    this.lastUpdated,
  });

  factory PermissionStatus.fromMap(Map<String, dynamic> map) {
    return PermissionStatus(
      accessibility: map['accessibility'] ?? false,
      deviceAdmin:   map['device_admin']  ?? false,
      notifications: map['notifications'] ?? false,
      overlay:       map['overlay']       ?? false,
      usageAccess:   map['usage_access']  ?? false,
      lastUpdated: map['last_updated'] != null
          ? (map['last_updated'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'accessibility':  accessibility,
        'device_admin':   deviceAdmin,
        'notifications':  notifications,
        'overlay':        overlay,
        'usage_access':   usageAccess,
        if (lastUpdated != null)
          'last_updated': Timestamp.fromDate(lastUpdated!),
      };
}

class ChildDeviceModel {
  final String           deviceId;
  final String           deviceName;
  final String           fullName;
  final int              age;
  final String           deviceModel;
  final String           manufacturer;
  final String           androidVersion;

  final DateTime         dateCreated;
  final DateTime?        lastSync;
  final String?          registrationToken;
  final bool             setupComplete;
  final PermissionStatus permissionStatus;
  final String?          imageUrl;


  final int?     batteryLevel;
  final String   signalStatus;
  final bool     safechidRunning;
  final DateTime? lastSeen;

  ChildDeviceModel({
    required this.deviceId,
    required this.deviceName,
    required this.fullName,
    required this.age,
    required this.deviceModel,
    required this.manufacturer,
    required this.androidVersion,
    required this.dateCreated,
    this.lastSync,
    this.registrationToken,
    this.setupComplete      = false,
    required this.permissionStatus,
    this.imageUrl,
    this.batteryLevel,
    this.signalStatus       = 'lost',
    this.safechidRunning    = false,
    this.lastSeen,
  });

  factory ChildDeviceModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ChildDeviceModel(
      deviceId:       doc.id,
      deviceName:     d['device_name']     ?? '',
      fullName:       d['full_name']        ?? '',
      age:            (d['age'] as num?)?.toInt() ?? 0,
      deviceModel:    d['device_model']     ?? '',
      manufacturer:   d['manufacturer']    ?? '',
      androidVersion: d['android_version'] ?? '',
      dateCreated:    (d['date_created'] as Timestamp).toDate(),
      lastSync: d['last_sync'] != null
          ? (d['last_sync'] as Timestamp).toDate()
          : null,
      registrationToken: d['registration_token'],
      setupComplete:     d['setup_complete'] ?? false,
      permissionStatus: d['permission_status'] != null
          ? PermissionStatus.fromMap(
              Map<String, dynamic>.from(d['permission_status']))
          : PermissionStatus(),
      imageUrl:        d['image_url'],
      batteryLevel:    (d['battery_level'] as num?)?.toInt(),
      signalStatus:    d['signal_status']     ?? 'lost',
      safechidRunning: d['safechild_running'] ?? false,
      lastSeen: d['last_seen'] != null
          ? (d['last_seen'] as Timestamp).toDate()
          : null,
    );
  }

  bool get isOnline => signalStatus == 'active';

  String get lastSeenLabel {
    final ref = lastSeen ?? lastSync;
    if (ref == null) return 'Never';
    final diff = DateTime.now().difference(ref);
    if (diff.inSeconds < 60)  return 'Just now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

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
}