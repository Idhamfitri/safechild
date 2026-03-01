// lib/models/parent_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class ParentModel {
  final String parentId;   // = Firebase Auth UID
  final String email;
  final String fullName;
  final DateTime dateCreated;
  final bool isActive;

  ParentModel({
    required this.parentId,
    required this.email,
    required this.fullName,
    required this.dateCreated,
    this.isActive = true,
  });

  factory ParentModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ParentModel(
      parentId: doc.id,
      email: d['email'] ?? '',
      fullName: d['full_name'] ?? '',
      dateCreated: (d['date_created'] as Timestamp).toDate(),
      isActive: d['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'email': email,
        'full_name': fullName,
        'date_created': Timestamp.fromDate(dateCreated),
        'is_active': isActive,
      };
}