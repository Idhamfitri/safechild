// lib/services/monitoring_setting_service.dart
// Reads/writes Firestore collection: monitoring_settings
// Uses the linkId as the document ID (one doc per parent-child link).

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/monitoring_setting_model.dart';

class MonitoringSettingService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('monitoring_settings');

  Stream<MonitoringSettingModel> watchSettings(String linkId) =>
      _col.doc(linkId).snapshots().map((doc) {
        if (doc.exists && doc.data() != null) {
          return MonitoringSettingModel.fromFirestore(doc);
        }
        return MonitoringSettingModel.defaults(linkId);
      });

  Future<void> saveSettings(MonitoringSettingModel s) =>
      _col.doc(s.linkId).set(s.toFirestore(), SetOptions(merge: true));

  Future<void> updateField(String linkId, String field, dynamic value) =>
      _col.doc(linkId).set(
            {field: value, 'updated_at': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
}