// lib/models/child_device_model.dart
// UPDATED: Added manufacturer, androidSdk, permissionStatus fields.
// permission_status map is written by child device during/after permission setup.
// Parent dashboard reads this in real-time to show protection status.

import 'package:cloud_firestore/cloud_firestore.dart';

// ─── Permission status snapshot ───────────────────────────────────────────────
class DevicePermissionStatus {
  final bool notifications;
  final bool overlay;
  final bool usageAccess;
  final bool accessibility;
  final bool deviceAdmin;
  final DateTime? lastUpdated;

  const DevicePermissionStatus({
    this.notifications = false,
    this.overlay       = false,
    this.usageAccess   = false,
    this.accessibility = false,
    this.deviceAdmin   = false,
    this.lastUpdated,
  });

  factory DevicePermissionStatus.fromMap(Map<String, dynamic> m) =>
      DevicePermissionStatus(
        notifications: m['notifications'] as bool? ?? false,
        overlay:       m['overlay']       as bool? ?? false,
        usageAccess:   m['usage_access']  as bool? ?? false,
        accessibility: m['accessibility'] as bool? ?? false,
        deviceAdmin:   m['device_admin']  as bool? ?? false,
        lastUpdated:   m['last_updated'] != null
            ? (m['last_updated'] as Timestamp).toDate()
            : null,
      );

  Map<String, dynamic> toMap() => {
        'notifications': notifications,
        'overlay':       overlay,
        'usage_access':  usageAccess,
        'accessibility': accessibility,
        'device_admin':  deviceAdmin,
        'last_updated':  Timestamp.now(),
      };

  // How many permissions are granted
  int get grantedCount => [
    notifications, overlay, usageAccess, accessibility, deviceAdmin,
  ].where((b) => b).length;

  int get totalCount => 5;

  bool get allGranted => grantedCount == totalCount;

  static DevicePermissionStatus get none => const DevicePermissionStatus();
}

// ─── Child device model ───────────────────────────────────────────────────────
class ChildDeviceModel {
  final String   deviceId;
  final String   deviceName;
  final String?  deviceModel;       // e.g. "Pixel 7 Pro"
  final String?  manufacturer;      // e.g. "Google"
  final String?  androidVersion;    // e.g. "14"
  final int?     androidSdk;        // e.g. 34
  final String?  registrationToken;
  final int      age;
  final String   fullName;
  final DateTime dateCreated;
  final DateTime? lastSync;
  final String?  image;
  final DevicePermissionStatus permissionStatus;
  final bool     setupComplete;

  ChildDeviceModel({
    required this.deviceId,
    required this.deviceName,
    this.deviceModel,
    this.manufacturer,
    this.androidVersion,
    this.androidSdk,
    this.registrationToken,
    required this.age,
    required this.fullName,
    required this.dateCreated,
    this.lastSync,
    this.image,
    this.permissionStatus = const DevicePermissionStatus(),
    this.setupComplete    = false,
  });

  factory ChildDeviceModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ChildDeviceModel(
      deviceId:      doc.id,
      deviceName:    d['device_name']       ?? '',
      deviceModel:   d['device_model'],
      manufacturer:  d['manufacturer'],
      androidVersion: d['android_version'],
      androidSdk:    d['android_sdk']       as int?,
      registrationToken: d['registration_token'],
      age:           d['age']               ?? 0,
      fullName:      d['full_name']         ?? '',
      dateCreated:   (d['date_created'] as Timestamp).toDate(),
      lastSync:      d['last_sync'] != null
          ? (d['last_sync'] as Timestamp).toDate()
          : null,
      image:         d['image'],
      permissionStatus: d['permission_status'] != null
          ? DevicePermissionStatus.fromMap(
              Map<String, dynamic>.from(d['permission_status']))
          : const DevicePermissionStatus(),
      setupComplete: d['setup_complete'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'device_name':     deviceName,
        if (deviceModel   != null) 'device_model':   deviceModel,
        if (manufacturer  != null) 'manufacturer':   manufacturer,
        if (androidVersion != null) 'android_version': androidVersion,
        if (androidSdk    != null) 'android_sdk':    androidSdk,
        if (registrationToken != null) 'registration_token': registrationToken,
        'age':             age,
        'full_name':       fullName,
        'date_created':    Timestamp.fromDate(dateCreated),
        if (lastSync != null) 'last_sync': Timestamp.fromDate(lastSync!),
        if (image    != null) 'image':     image,
        'permission_status': permissionStatus.toMap(),
        'setup_complete':  setupComplete,
      };

  // Human-readable device info line
  String get deviceInfoLine {
    final parts = <String>[];
    if (manufacturer != null && manufacturer!.isNotEmpty) parts.add(manufacturer!);
    if (deviceModel != null && deviceModel!.isNotEmpty) {
      // Avoid duplicating manufacturer if already in model string
      final model = deviceModel!;
      final m = manufacturer ?? '';
      parts.add(model.startsWith(m) && m.isNotEmpty
          ? model.substring(m.length).trim()
          : model);
    }
    return parts.isNotEmpty ? parts.join(' ') : 'Unknown Device';
  }

  String get androidLabel =>
      androidVersion != null ? 'Android $androidVersion' : 'Android —';

  bool get isPaired =>
      deviceModel != null && registrationToken != null;
}