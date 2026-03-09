import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum IncidentCategory {
  toxic,        // Module 2 — general harmful/toxic content
  threatening,  // Module 2 — threatening content (bullying, threats)
}

extension IncidentCategoryX on IncidentCategory {
  String get value {
    switch (this) {
      case IncidentCategory.toxic:       return 'toxic';
      case IncidentCategory.threatening: return 'threatening';
    }
  }

  String get displayLabel {
    switch (this) {
      case IncidentCategory.toxic:       return 'Toxic Content';
      case IncidentCategory.threatening: return 'Threatening';
    }
  }

  Color get color {
    switch (this) {
      case IncidentCategory.toxic:       return const Color(0xFFE65100);
      case IncidentCategory.threatening: return const Color(0xFFD32F2F);
    }
  }

  IconData get icon {
    switch (this) {
      case IncidentCategory.toxic:       return Icons.warning_amber_outlined;
      case IncidentCategory.threatening: return Icons.gpp_bad_outlined;
    }
  }
}

IncidentCategory _catFromString(String? s) {
  switch (s) {
    case 'toxic':       return IncidentCategory.toxic;
    case 'threatening': return IncidentCategory.threatening;
    default:            return IncidentCategory.toxic;
  }
}

class IncidentModel {
  final String           incidentId;
  final String           deviceId;
  final String           textSummary;
  final String           description;   
  final String           source;
  final double           confidenceScore;
  final IncidentCategory category;
  final String           detectionModel;
  final DateTime         detectedAt;
  final bool             isReviewed;
  final DateTime?        reviewedAt;
  final bool             isAlertSend;
  final DateTime?        alertSendAt;

  IncidentModel({
    required this.incidentId,
    required this.deviceId,
    required this.textSummary,
    required this.description,
    required this.source,
    required this.confidenceScore,
    required this.category,
    required this.detectionModel,
    required this.detectedAt,
    required this.isReviewed,
    this.reviewedAt,
    required this.isAlertSend,
    this.alertSendAt,
  });

  factory IncidentModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return IncidentModel(
      incidentId:      doc.id,
      deviceId:        d['device_id']        ?? '',
      textSummary:     d['text_summary']      ?? '',
      description:     d['description']       ?? '',   // ← new field
      source:          d['source']            ?? '',
      confidenceScore: (d['confidence_score'] ?? 0.0).toDouble(),
      category:        _catFromString(d['category']),
      detectionModel:  d['detection_model']   ?? 'gemini',
      detectedAt:      (d['detected_at'] as Timestamp).toDate(),
      isReviewed:      d['is_reviewed']        ?? false,
      reviewedAt: d['reviewed_at'] != null
          ? (d['reviewed_at'] as Timestamp).toDate()
          : null,
      isAlertSend: d['is_alert_send'] ?? false,
      alertSendAt: d['alert_send_at'] != null
          ? (d['alert_send_at'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'device_id':        deviceId,
        'text_summary':     textSummary,
        'description':      description,   // ← new field
        'source':           source,
        'confidence_score': confidenceScore,
        'category':         category.value,
        'detection_model':  detectionModel,
        'detected_at':      FieldValue.serverTimestamp(),
        'is_reviewed':      isReviewed,
        if (reviewedAt != null) 'reviewed_at': Timestamp.fromDate(reviewedAt!),
        'is_alert_send':    isAlertSend,
        if (alertSendAt != null) 'alert_send_at': Timestamp.fromDate(alertSendAt!),
      };

  bool get alertThresholdMet => confidenceScore >= 0.75;
  bool get logThresholdMet   => confidenceScore >= 0.5;

  String get confidenceLabel {
    if (confidenceScore >= 0.90) return 'Very High';
    if (confidenceScore >= 0.75) return 'High';
    if (confidenceScore >= 0.50) return 'Medium';
    return 'Low';
  }
}