import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/screen_time_models.dart';

class ScreenTimeService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _schedulesCol => _db.collection('screen_time_schedules');
  CollectionReference<Map<String, dynamic>> get _requestsCol  => _db.collection('screen_time_requests');
  CollectionReference<Map<String, dynamic>> get _locksCol     => _db.collection('screen_time_locks');

  // ── Watch Primary Lock State (Child / Parent) ────────────────────────
  Stream<ScreenTimeLock> watchLock(String deviceId) => _locksCol
      .doc(deviceId)
      .snapshots()
      .map((snap) => snap.exists 
         ? ScreenTimeLock.fromFirestore(snap) 
         : ScreenTimeLock(lockId: deviceId, deviceId: deviceId, isLocked: false));

  // ── Watch Schedules (Parent / Child) ────────────────────────────────
  Stream<List<ScreenTimeSchedule>> watchSchedules(String deviceId) => _schedulesCol
      .where('device_id', isEqualTo: deviceId)
      .snapshots()
      .map((snap) => snap.docs.map(ScreenTimeSchedule.fromFirestore).toList());

  // ── Manual Parent Lock Toggle ──────────────────────────────────────
  Future<void> setManualLock(String deviceId, bool isLocked) async {
    final doc = _locksCol.doc(deviceId);
    if (!isLocked) {
       await doc.set({
         'device_id': deviceId,
         'is_locked': false,
       }, SetOptions(merge: true));
       return;
    }

    await doc.set({
      'device_id': deviceId,
      'is_locked': true,
      'locked_by': 'parent',
      'unlocked_at': FieldValue.delete(), // Ensure it's treated as manual lock
      'start_time': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
  
  // ── Auto Schedule Lock Toggle ──────────────────────────────────────
  Future<void> setScheduleLock(String deviceId, bool isLocked) async {
    final doc = _locksCol.doc(deviceId);
    
    // If we want to unlock via schedule, we should verify it wasn't locked by parent manually.
    if (!isLocked) {
      final current = await doc.get();
      if (current.exists && current.data()!['locked_by'] == 'parent') {
        return; // Don't let schedule unlock a parent's force lock
      }
      
      await doc.set({
         'device_id': deviceId,
         'is_locked': false,
      }, SetOptions(merge: true));
      return;
    }
    
    // If it's already locked by parent, keep it that way.
    final current = await doc.get();
    if (current.exists && current.data()!['is_locked'] == true && current.data()!['locked_by'] == 'parent') {
      return;
    }

    await doc.set({
      'device_id': deviceId,
      'is_locked': true,
      'locked_by': 'schedule',
      'start_time': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ── Create Schedule (Parent) ────────────────────────────────────────
  Future<void> createSchedule(ScreenTimeSchedule schedule) async {
    await _schedulesCol.add(schedule.toFirestore());
  }

  // ── Delete Schedule (Parent) ────────────────────────────────────────
  Future<void> deleteSchedule(String scheduleId) async {
    await _schedulesCol.doc(scheduleId).delete();
  }

  // ── Toggle Schedule (Parent) ────────────────────────────────────────
  Future<void> toggleScheduleActive(String scheduleId, bool isActive) async {
    await _schedulesCol.doc(scheduleId).update({'is_active': isActive});
  }

  // ── Submit Request (Child) ──────────────────────────────────────────
  Future<void> submitRequest(String deviceId, int minutes, {String reason = ''}) async {
    await _requestsCol.add({
      'device_id': deviceId,
      'requested_time': minutes,
      'reason': reason,
      'status': 'pending',
      'requested_at': FieldValue.serverTimestamp(),
    });
  }

  // ── Watch Pending Requests (Parent) ─────────────────────────────────
  Stream<List<ScreenTimeRequest>> watchPendingRequests(String deviceId) {
    return _requestsCol
        .where('device_id', isEqualTo: deviceId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) {
           final list = snap.docs.map(ScreenTimeRequest.fromFirestore).toList();
           list.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
           return list;
        });
  }

  // ── Approve/Reject Request (Parent) ─────────────────────────────────
  Future<void> handleRequest(String requestId, String deviceId, int minutes, bool approve) async {
    final batch = _db.batch();

    // Update request status
    batch.update(_requestsCol.doc(requestId), {
      'status': approve ? 'approved' : 'rejected',
      'reply_at': FieldValue.serverTimestamp(),
    });

    // If approved, update lock table to grant the time (removes the lock and records the offset)
    if (approve) {
       // Since the new schema just checks isLocked from `screen_time_locks`:
       // If parent approves extra time while scheduled locked, we can just unlock it.
       // However, to prevent background service from immediately locking it again
       // because the time is still inside the schedule, we need to temporarily
       // set `end_time` to future, and the background service should respect that.
       final lockDoc = _locksCol.doc(deviceId);
       
       final unlockedUntil = DateTime.now().add(Duration(minutes: minutes));
       batch.set(lockDoc, {
          'is_locked': false,
          'unlocked_at': Timestamp.fromDate(unlockedUntil), // Use unlocked_at as "snoozed until"
       }, SetOptions(merge: true));
    }

    await batch.commit();
  }
}
