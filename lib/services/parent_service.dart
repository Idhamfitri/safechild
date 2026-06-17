// lib/services/parent_service.dart
// The Firebase Cloud Function reads this token to send incident alerts.
// Call saveFcmToken() after parent login .

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/parent_model.dart';

class ParentService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('parents');

  Future<void> createParentProfile({
    required String parentId,
    required String email,
    required String fullName,
  }) async {
    final model = ParentModel(
      parentId:    parentId,
      email:       email,
      fullName:    fullName,
      dateCreated: DateTime.now(),
    );
    await _col.doc(parentId).set(model.toFirestore());
  }

  Future<ParentModel?> getParentById(String parentId) async {
    final doc = await _col.doc(parentId).get();
    if (!doc.exists) return null;
    return ParentModel.fromFirestore(doc);
  }

  Stream<ParentModel?> watchParent(String parentId) =>
      _col.doc(parentId).snapshots().map(
            (doc) => doc.exists ? ParentModel.fromFirestore(doc) : null,
          );

  // ── Update email in Firestore after Firebase Auth email change ────────────
  Future<void> updateEmail(String parentId, String newEmail) =>
      _col.doc(parentId).update({'email': newEmail.trim()});

  // ── Save parent FCM token so Cloud Function can send alerts ───────────────
  // Call this once after parent logs in and on token refresh.
  Future<void> saveFcmToken(String parentId) async {
    try {
      // Request notification permission (required on Android 13+ and iOS).
      await FirebaseMessaging.instance.requestPermission(
        alert: true, sound: true, badge: true,
      );

      // Create the alert channel that the Cloud Function targets.
      // Android 8+ silently drops FCM notifications if the channel doesn't exist.
      const alertChannel = AndroidNotificationChannel(
        'safechild_alerts',
        'SafeChild Alerts',
        description: 'Real-time safety alerts from child devices',
        importance: Importance.high,
        playSound: true,
      );
      final notifPlugin = FlutterLocalNotificationsPlugin();
      await notifPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(alertChannel);

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await _col.doc(parentId).update({'fcm_token': token});

      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _col.doc(parentId).update({'fcm_token': newToken});
      });
    } catch (_) {}
  }
}