// lib/services/heartbeat_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Reads from Firestore collection: heartbeat
// Each heartbeat is a SEPARATE document (one per 10-minute cycle).
// To get the latest status we query: device_id == X, orderBy timestamp desc, limit 1.
//
// This matches MODULE3_WORKFLOW Part 3:
//   "Firestore Snapshot Listener → fires instantly when new heartbeat arrives"
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/heartbeat_model.dart';

class HeartbeatService {
  final _db = FirebaseFirestore.instance;

  // Collection name matches schema exactly (MODULE3_WORKFLOW Part 4)
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('heartbeat');

  // ── Real-time stream — latest heartbeat for a device ─────────────────────
  // Fires instantly when Module 3 child service writes a new heartbeat doc.
  // Falls back to dummy data if no heartbeat exists yet.
  Stream<HeartbeatModel> watchLatestHeartbeat(String deviceId) {
    return _col
        .where('device_id', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) {
        return HeartbeatModel.dummy(deviceId);
      }
      return HeartbeatModel.fromFirestore(snap.docs.first);
    });
  }

  // ── One-time fetch of latest heartbeat ────────────────────────────────────
  Future<HeartbeatModel> getLatestHeartbeat(String deviceId) async {
    final snap = await _col
        .where('device_id', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return HeartbeatModel.dummy(deviceId);
    return HeartbeatModel.fromFirestore(snap.docs.first);
  }

  // ── Stream of last N heartbeats (for history / trend) ────────────────────
  Stream<List<HeartbeatModel>> watchHeartbeatHistory(
      String deviceId, {int limit = 12}) {
    return _col
        .where('device_id', isEqualTo: deviceId)
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map(HeartbeatModel.fromFirestore).toList());
  }
}