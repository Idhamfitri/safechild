// lib/services/heartbeat_service.dart
// READ side only 
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/heartbeat_model.dart';

class HeartbeatService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('heartbeat');
      
  Stream<HeartbeatModel> watchHeartbeat(String deviceId) {
    return _col.doc(deviceId).snapshots().map((snap) {
      if (!snap.exists) return HeartbeatModel.empty(deviceId);
      return HeartbeatModel.fromFirestore(snap);
    });
  }
}