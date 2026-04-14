// lib/services/admin_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class AdminService {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  static const String adminEmail = 'admin@safechild.com';
  static bool isAdminEmail(String? email) =>
      email?.toLowerCase().trim() == adminEmail;

  // ── System Stats ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getSystemStats() async {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayTs = Timestamp.fromDate(today);

    final results = await Future.wait([
      _db.collection('parents').get(),
      _db.collection('child_devices').get(),
      _db.collection('parent_child_links')
          .where('status', isEqualTo: 'active').get(),
      // Today's alerts = incidents + bypass_events
      _db.collection('incidents')
          .where('created_at', isGreaterThanOrEqualTo: todayTs).get(),
      _db.collection('bypass_events')
          .where('timestamp', isGreaterThanOrEqualTo: todayTs).get(),
    ]);

    final totalAlerts =
        (results[3] as QuerySnapshot).docs.length +
        (results[4] as QuerySnapshot).docs.length;

    return {
      'total_parents': (results[0] as QuerySnapshot).docs.length,
      'total_devices': (results[1] as QuerySnapshot).docs.length,
      'active_links':  (results[2] as QuerySnapshot).docs.length,
      'alerts_today':  totalAlerts,
    };
  }

  /// Returns latency in ms, or -1 if unreachable.
  Future<int> checkFirebaseLatency() async {
    final sw = Stopwatch()..start();
    try {
      await _db.collection('_ping').doc('probe').get();
      sw.stop();
      return sw.elapsedMilliseconds;
    } catch (_) {
      return -1;
    }
  }

  /// Checks if Gemini (VertexAI / Generative Language API) endpoint is reachable.
  /// Returns 'operational', 'degraded', or 'unreachable'.
  Future<String> checkGeminiApiStatus() async {
    try {
      final resp = await http
          .get(Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200 || resp.statusCode == 400) {
        // 400 = "API key missing" but server IS reachable
        return 'operational';
      } else if (resp.statusCode >= 500) {
        return 'degraded';
      }
      return 'operational';
    } catch (_) {
      return 'unreachable';
    }
  }

  /// 7-day traffic: returns list of {date, incidents, bypass} maps.
  Future<List<Map<String, dynamic>>> getWeeklyTraffic() async {
    final now = DateTime.now();
    final results = <Map<String, dynamic>>[];

    for (int i = 6; i >= 0; i--) {
      final day   = DateTime(now.year, now.month, now.day - i);
      final next  = day.add(const Duration(days: 1));
      final dayTs  = Timestamp.fromDate(day);
      final nextTs = Timestamp.fromDate(next);

      final inc = await _db.collection('incidents')
          .where('created_at', isGreaterThanOrEqualTo: dayTs)
          .where('created_at', isLessThan: nextTs)
          .get();
      final byp = await _db.collection('bypass_events')
          .where('timestamp', isGreaterThanOrEqualTo: dayTs)
          .where('timestamp', isLessThan: nextTs)
          .get();

      results.add({
        'date':      '${day.month}/${day.day}',
        'incidents': inc.docs.length,
        'bypass':    byp.docs.length,
      });
    }
    return results;
  }

  // ── User Account Management ─────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> watchParentsWithDevices() {
    return _db.collection('parents').snapshots().asyncMap((snap) async {
      final List<Map<String, dynamic>> result = [];
      for (final doc in snap.docs) {
        final data = {...doc.data(), 'id': doc.id};

        final linksSnap = await _db
            .collection('parent_child_links')
            .where('parent_id', isEqualTo: doc.id)
            .where('status', isEqualTo: 'active')
            .get();
        data['device_count'] = linksSnap.docs.length;

        result.add(data);
      }
      // Sort: active first, then by name
      result.sort((a, b) {
        final sa = a['account_status'] as String? ?? 'active';
        final sb = b['account_status'] as String? ?? 'active';
        if (sa != sb) return sa == 'active' ? -1 : 1;
        final na = a['full_name'] as String? ?? '';
        final nb = b['full_name'] as String? ?? '';
        return na.compareTo(nb);
      });
      return result;
    });
  }

  Future<void> _logAdminAction({
    required String parentId,
    required String action,
    String? note,
  }) async {
    await _db.collection('admin_audit_log').add({
      'parent_id':    parentId,
      'action':       action,
      'note':         note,
      'performed_by': _auth.currentUser?.email,
      'timestamp':    Timestamp.now(),
    });
  }

  Future<void> suspendParent(String parentId) async {
    await _db.collection('parents').doc(parentId)
        .update({'account_status': 'suspended'});
    await _logAdminAction(
        parentId: parentId, action: 'suspend',
        note: 'Account suspended by admin');
  }

  Future<void> activateParent(String parentId) async {
    await _db.collection('parents').doc(parentId)
        .update({'account_status': 'active'});
    await _logAdminAction(
        parentId: parentId, action: 'activate',
        note: 'Account reactivated by admin');
  }

  Future<void> deleteParentAccount(String parentId) async {
    final batch = _db.batch();

    final links = await _db.collection('parent_child_links')
        .where('parent_id', isEqualTo: parentId).get();
    for (final l in links.docs) batch.delete(l.reference);
    batch.delete(_db.collection('parents').doc(parentId));
    await batch.commit();

    await _db.collection('admin_deletion_queue').add({
      'parent_id':    parentId,
      'requested_at': Timestamp.now(),
      'requested_by': _auth.currentUser?.email,
    });
    await _logAdminAction(
        parentId: parentId, action: 'delete',
        note: 'Account permanently deleted by admin');
  }

  Future<void> unlinkDevice(String linkId) async {
    await _db.collection('parent_child_links')
        .doc(linkId).update({'status': 'unlinked'});
  }
}
