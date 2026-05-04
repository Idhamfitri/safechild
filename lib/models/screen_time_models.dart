import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ── Schedule Model ────────────────────────────────────────────────────────
class ScreenTimeSchedule {
  final String scheduleId;
  final String deviceId;
  final String scheduleName;
  final int iconIndex; // To store symbolic icon index (e.g., 0=Lock, 1=Book, 2=School)
  final String startTime; // e.g. "20:00"
  final String endTime;   // e.g. "22:00"
  final List<String> days;   // 'monday', 'tuesday', etc.
  final bool isActive;
  final DateTime createdAt;

  ScreenTimeSchedule({
    required this.scheduleId,
    required this.deviceId,
    required this.scheduleName,
    required this.iconIndex,
    required this.startTime,
    required this.endTime,
    required this.days,
    required this.isActive,
    required this.createdAt,
  });

  factory ScreenTimeSchedule.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ScreenTimeSchedule(
      scheduleId:   doc.id,
      deviceId:     d['device_id'] ?? '',
      scheduleName: d['schedule_name'] ?? 'Lock Block',
      iconIndex:    d['icon_index'] ?? 0,
      startTime:    d['start_time'] ?? '00:00',
      endTime:      d['end_time'] ?? '00:00',
      days:         List<String>.from(d['days'] ?? []),
      isActive:     d['is_active'] ?? true,
      createdAt:    (d['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'device_id':     deviceId,
        'schedule_name': scheduleName,
        'icon_index':    iconIndex,
        'start_time':    startTime,
        'end_time':      endTime,
        'days':          days,
        'is_active':     isActive,
        'created_at':    FieldValue.serverTimestamp(),
      };

  bool contains(TimeOfDay now, int weekday) {
    final weekdayStr = _weekdayToString(weekday);
    if (!isActive || !days.contains(weekdayStr)) return false;
    
    int tMin = now.hour * 60 + now.minute;
    
    final sParts = startTime.split(':');
    final eParts = endTime.split(':');
    if (sParts.length != 2 || eParts.length != 2) return false;

    int sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
    int eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);

    if (eMin < sMin) {
      // Crosses midnight
      return tMin >= sMin || tMin <= eMin;
    }
    return tMin >= sMin && tMin < eMin;
  }
  static String _weekdayToString(int weekday) {
    const daysMap = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    if (weekday >= 1 && weekday <= 7) return daysMap[weekday - 1];
    return '';
  }
}

// ── Request Model ─────────────────────────────────────────────────────────
class ScreenTimeRequest {
  final String requestId;
  final String deviceId;
  final int requestedTime; // minutes
  final String reason;
  final String status; // 'pending', 'approved', 'rejected'
  final DateTime requestedAt;
  final DateTime? replyAt;

  ScreenTimeRequest({
    required this.requestId,
    required this.deviceId,
    required this.requestedTime,
    required this.reason,
    required this.status,
    required this.requestedAt,
    this.replyAt,
  });

  factory ScreenTimeRequest.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ScreenTimeRequest(
      requestId:     doc.id,
      deviceId:      d['device_id'] ?? '',
      requestedTime: d['requested_time'] ?? 0,
      reason:        d['reason'] ?? '',
      status:        d['status'] ?? 'pending',
      requestedAt:   (d['requested_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      replyAt:       (d['reply_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'device_id':      deviceId,
        'requested_time': requestedTime,
        'reason':         reason,
        'status':         status,
        'requested_at':   FieldValue.serverTimestamp(),
        if (replyAt != null) 'reply_at': Timestamp.fromDate(replyAt!),
      };
}

// ── Lock State Model ──────────────────────────────────────────────────────
class ScreenTimeLock {
  final String lockId;
  final String deviceId;
  final bool isLocked;
  final DateTime? startTime;
  final DateTime? unlockedAt;

  ScreenTimeLock({
    required this.lockId,
    required this.deviceId,
    required this.isLocked,
    this.startTime,
    this.unlockedAt,
  });

  factory ScreenTimeLock.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ScreenTimeLock(
      lockId:    doc.id,
      deviceId:  d['device_id'] ?? '',
      isLocked:  d['is_locked'] ?? false,
      startTime:  (d['start_time'] as Timestamp?)?.toDate(),
      unlockedAt: (d['unlocked_at'] as Timestamp?)?.toDate(),
    );
  }
  
  Map<String, dynamic> toFirestore() => {
       'device_id':  deviceId,
       'is_locked':  isLocked,
       if (startTime  != null) 'start_time': Timestamp.fromDate(startTime!),
       if (unlockedAt != null) 'unlocked_at': Timestamp.fromDate(unlockedAt!),
  };
}
