// lib/services/heartbeat_service.dart
// READ side — parent dashboard watches latest heartbeat written by child device.
// The WRITE side is in child_active_screen.dart (timer every 10 minutes).

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/heartbeat_model.dart';

class HeartbeatService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('heartbeat');

  // Real-time stream — fires whenever child writes a new heartbeat doc
  Stream<HeartbeatModel> watchLatestHeartbeat(String deviceId) {
    return _col
        .where('device_id', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return HeartbeatModel.dummy(deviceId);
      return HeartbeatModel.fromFirestore(snap.docs.first);
    });
  }

  Future<HeartbeatModel> getLatestHeartbeat(String deviceId) async {
    final snap = await _col
        .where('device_id', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return HeartbeatModel.dummy(deviceId);
    return HeartbeatModel.fromFirestore(snap.docs.first);
  }
}