// lib/services/parent_service.dart
// The Firebase Cloud Function reads this token to send incident alerts.
// Call saveFcmToken() after parent login .

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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

  // ── Save parent FCM token so Cloud Function can send alerts ───────────────
  // Call this once after parent logs in and on token refresh.
  // when a new incident with is_alert_send = true is created.
  Future<void> saveFcmToken(String parentId) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await _col.doc(parentId).update({'fcm_token': token});

      // Also handle token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        _col.doc(parentId).update({'fcm_token': newToken});
      });
    } catch (_) {
    
    }
  }
}