// lib/services/heartbeat_service.dart
// READ side only — parent dashboard watches the single heartbeat doc per device.
// Document ID = device_id (upsert pattern — one doc per device, updated not created)

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/heartbeat_model.dart';

class HeartbeatService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('heartbeat');

  // Real-time stream — fires whenever child updates its heartbeat doc
  Stream<HeartbeatModel> watchHeartbeat(String deviceId) {
    return _col.doc(deviceId).snapshots().map((snap) {
      if (!snap.exists) return HeartbeatModel.empty(deviceId);
      return HeartbeatModel.fromFirestore(snap);
    });
  }
}