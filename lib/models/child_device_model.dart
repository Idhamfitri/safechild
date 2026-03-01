// lib/models/child_device_model.dart
// Replaces old CHILD table. No login credentials.
// Personal info entered by parent. Hardware info populated by child device at pairing.

import 'package:cloud_firestore/cloud_firestore.dart';

class ChildDeviceModel {
  final String deviceId;
  final String deviceName;
  final String? deviceModel;        // null until child device pairs
  final String? androidVersion;     // null until child device pairs
  final String? registrationToken;  // FCM token — null until paired
  final int age;
  final String fullName;
  final DateTime dateCreated;
  final DateTime? lastSync;
  final String? image;

  ChildDeviceModel({
    required this.deviceId,
    required this.deviceName,
    this.deviceModel,
    this.androidVersion,
    this.registrationToken,
    required this.age,
    required this.fullName,
    required this.dateCreated,
    this.lastSync,
    this.image,
  });

  factory ChildDeviceModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ChildDeviceModel(
      deviceId: doc.id,
      deviceName: d['device_name'] ?? '',
      deviceModel: d['device_model'],
      androidVersion: d['android_version'],
      registrationToken: d['registration_token'],
      age: d['age'] ?? 0,
      fullName: d['full_name'] ?? '',
      dateCreated: (d['date_created'] as Timestamp).toDate(),
      lastSync: d['last_sync'] != null
          ? (d['last_sync'] as Timestamp).toDate()
          : null,
      image: d['image'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'device_name': deviceName,
        if (deviceModel != null) 'device_model': deviceModel,
        if (androidVersion != null) 'android_version': androidVersion,
        if (registrationToken != null) 'registration_token': registrationToken,
        'age': age,
        'full_name': fullName,
        'date_created': Timestamp.fromDate(dateCreated),
        if (lastSync != null) 'last_sync': Timestamp.fromDate(lastSync!),
        if (image != null) 'image': image,
      };

  bool get isPaired =>
      deviceModel != null && androidVersion != null && registrationToken != null;
}