// lib/services/bypass_event_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Reads from Firestore collection: bypass_events
// Uses Firestore Snapshot Listener — fires instantly when Module 3 child
// service detects and writes a bypass event (MODULE3_WORKFLOW Part 3).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/bypass_event_model.dart';

class BypassEventService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('bypass_events');

  // ── Real-time stream ordered by detected_at desc ──────────────────────────
  Stream<List<BypassEventModel>> watchBypassEvents(String deviceId) =>
      _col
          .where('device_id', isEqualTo: deviceId)
          .orderBy('detected_at', descending: true)
          .snapshots()
          .map((s) => s.docs.map(BypassEventModel.fromFirestore).toList());

  // ── Today's events only ───────────────────────────────────────────────────
  Stream<List<BypassEventModel>> watchTodayBypassEvents(String deviceId) {
    final startOfDay = DateTime.now().copyWith(
        hour: 0, minute: 0, second: 0, millisecond: 0);
    return _col
        .where('device_id', isEqualTo: deviceId)
        .where('detected_at',
            isGreaterThanOrEqualTo: startOfDay.millisecondsSinceEpoch)
        .orderBy('detected_at', descending: true)
        .snapshots()
        .map((s) => s.docs.map(BypassEventModel.fromFirestore).toList());
  }

  // ── Unread count stream (for badge on Alerts tab) ─────────────────────────
  Stream<int> watchUnreviewedCount(String deviceId) =>
      _col
          .where('device_id', isEqualTo: deviceId)
          .where('is_reviewed', isEqualTo: false)
          .snapshots()
          .map((s) => s.docs.length);

  // ── Mark a single event as reviewed ──────────────────────────────────────
  Future<void> markReviewed(String bypassId) =>
      _col.doc(bypassId).update({'is_reviewed': true});

  Future<void> deleteBypassEvent(String bypassId) async {
  await FirebaseFirestore.instance
      .collection('bypass_events')
      .doc(bypassId)
      .delete();
}

  // ── Mark all events for a device as reviewed ──────────────────────────────
  Future<void> markAllReviewed(String deviceId) async {
    final snap = await _col
        .where('device_id', isEqualTo: deviceId)
        .where('is_reviewed', isEqualTo: false)
        .get();
    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'is_reviewed': true});
    }
    await batch.commit();
  }
}