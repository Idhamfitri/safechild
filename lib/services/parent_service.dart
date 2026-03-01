// lib/services/parent_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/parent_model.dart';

class ParentService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('parents');

  Future<void> createParentProfile({
    required String parentId,
    required String email,
    required String fullName,
  }) async {
    final model = ParentModel(
      parentId: parentId,
      email: email,
      fullName: fullName,
      dateCreated: DateTime.now(),
    );
    await _col.doc(parentId).set(model.toFirestore());
  }

  Future<ParentModel?> getParentById(String parentId) async {
    final doc = await _col.doc(parentId).get();
    if (!doc.exists) return null;
    return ParentModel.fromFirestore(doc);
  }

  Stream<ParentModel?> watchParent(String parentId) =>
      _col.doc(parentId).snapshots().map(
            (doc) => doc.exists ? ParentModel.fromFirestore(doc) : null,
          );
}