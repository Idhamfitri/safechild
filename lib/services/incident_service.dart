// lib/services/incident_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Reads from Firestore collection: incidents
// Uses Firestore Snapshot Listener — fires instantly when Module 2 content
// detection writes a new incident (MODULE3_WORKFLOW Part 3).
//
// Only incidents with confidence_score >= 0.5 are in Firestore.
// Only those with score >= 0.75 also have is_alert_send = true.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/incident_model.dart';

class IncidentService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('incidents');

  // ── All incidents for a device (ordered by detected_at desc) ─────────────
  Stream<List<IncidentModel>> watchIncidents(String deviceId) =>
      _col
          .where('device_id', isEqualTo: deviceId)
          .orderBy('detected_at', descending: true)
          .snapshots()
          .map((s) => s.docs.map(IncidentModel.fromFirestore).toList());

  // ── High-confidence incidents only (score >= 0.75) ────────────────────────
  Stream<List<IncidentModel>> watchHighConfidenceIncidents(String deviceId) =>
      _col
          .where('device_id', isEqualTo: deviceId)
          .where('confidence_score', isGreaterThanOrEqualTo: 0.75)
          .orderBy('confidence_score', descending: true)
          .snapshots()
          .map((s) => s.docs.map(IncidentModel.fromFirestore).toList());

  // ── Unreviewed count (for badge) ─────────────────────────────────────────
  Stream<int> watchUnreviewedCount(String deviceId) =>
      _col
          .where('device_id', isEqualTo: deviceId)
          .where('is_reviewed', isEqualTo: false)
          .snapshots()
          .map((s) => s.docs.length);

  // ── Mark reviewed ─────────────────────────────────────────────────────────
  Future<void> markReviewed(String incidentId) => _col.doc(incidentId).update({
        'is_reviewed': true,
        'reviewed_at': FieldValue.serverTimestamp(),
      });
  
  Future<void> deleteIncident(String incidentId) async {
  await FirebaseFirestore.instance
      .collection('incidents')
      .doc(incidentId)
      .delete();
}

  Future<void> markAllReviewed(String deviceId) async {
    final snap = await _col
        .where('device_id', isEqualTo: deviceId)
        .where('is_reviewed', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {
        'is_reviewed': true,
        'reviewed_at': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
}