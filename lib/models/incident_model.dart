// lib/models/incident_model.dart
// UPDATED for Module 2:
// Categories now include 'toxic' and 'threatening' — exactly what Gemini returns.
// Old categories (violence, adult etc.) kept for future modules.
// detection_model is now 'gemini' | 'offline_backup' matching Module 2 workflow.

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum IncidentCategory {
  toxic,        // Module 2 — general harmful/toxic content
  threatening,  // Module 2 — threatening content (bullying, threats)
  violence,
  adult,
  gambling,
  drugs,
  bullying,
  unknown,
}

extension IncidentCategoryX on IncidentCategory {
  String get value {
    switch (this) {
      case IncidentCategory.toxic:       return 'toxic';
      case IncidentCategory.threatening: return 'threatening';
      case IncidentCategory.violence:    return 'violence';
      case IncidentCategory.adult:       return 'adult';
      case IncidentCategory.gambling:    return 'gambling';
      case IncidentCategory.drugs:       return 'drugs';
      case IncidentCategory.bullying:    return 'bullying';
      case IncidentCategory.unknown:     return 'unknown';
    }
  }

  String get displayLabel {
    switch (this) {
      case IncidentCategory.toxic:       return 'Toxic Content';
      case IncidentCategory.threatening: return 'Threatening';
      case IncidentCategory.violence:    return 'Violence';
      case IncidentCategory.adult:       return 'Adult Content';
      case IncidentCategory.gambling:    return 'Gambling';
      case IncidentCategory.drugs:       return 'Drugs';
      case IncidentCategory.bullying:    return 'Bullying';
      case IncidentCategory.unknown:     return 'Unknown';
    }
  }

  Color get color {
    switch (this) {
      case IncidentCategory.toxic:       return const Color(0xFFE65100);
      case IncidentCategory.threatening: return const Color(0xFFD32F2F);
      case IncidentCategory.violence:    return const Color(0xFFD32F2F);
      case IncidentCategory.adult:       return const Color(0xFFE91E63);
      case IncidentCategory.gambling:    return const Color(0xFF6A1B9A);
      case IncidentCategory.drugs:       return const Color(0xFF1565C0);
      case IncidentCategory.bullying:    return const Color(0xFFE65100);
      case IncidentCategory.unknown:     return const Color(0xFF757575);
    }
  }

  IconData get icon {
    switch (this) {
      case IncidentCategory.toxic:       return Icons.warning_amber_outlined;
      case IncidentCategory.threatening: return Icons.gpp_bad_outlined;
      case IncidentCategory.violence:    return Icons.dangerous_outlined;
      case IncidentCategory.adult:       return Icons.no_adult_content_outlined;
      case IncidentCategory.gambling:    return Icons.casino_outlined;
      case IncidentCategory.drugs:       return Icons.medication_outlined;
      case IncidentCategory.bullying:    return Icons.person_off_outlined;
      case IncidentCategory.unknown:     return Icons.help_outline;
    }
  }
}

IncidentCategory _catFromString(String? s) {
  switch (s) {
    case 'toxic':       return IncidentCategory.toxic;
    case 'threatening': return IncidentCategory.threatening;
    case 'violence':    return IncidentCategory.violence;
    case 'adult':       return IncidentCategory.adult;
    case 'gambling':    return IncidentCategory.gambling;
    case 'drugs':       return IncidentCategory.drugs;
    case 'bullying':    return IncidentCategory.bullying;
    default:            return IncidentCategory.unknown;
  }
}

class IncidentModel {
  final String           incidentId;
  final String           deviceId;
  final String           textSummary;
  final String           source;
  final double           confidenceScore;
  final IncidentCategory category;
  final String           detectionModel; // 'gemini' | 'offline_backup'
  final DateTime         detectedAt;
  final bool             isReviewed;
  final DateTime?        reviewedAt;
  final bool             isAlertSend;
  final DateTime?        alertSendAt;

  IncidentModel({
    required this.incidentId,
    required this.deviceId,
    required this.textSummary,
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

  static List<IncidentModel> dummies(String deviceId) {
    final now = DateTime.now();
    return [
      IncidentModel(
        incidentId: 'i1', deviceId: deviceId,
        textSummary: 'Threatening content detected in WhatsApp',
        source: 'com.whatsapp', confidenceScore: 0.87,
        category: IncidentCategory.threatening,
        detectionModel: 'gemini',
        detectedAt: now.subtract(const Duration(hours: 1, minutes: 30)),
        isReviewed: false, isAlertSend: true,
        alertSendAt: now.subtract(const Duration(hours: 1, minutes: 29)),
      ),
      IncidentModel(
        incidentId: 'i2', deviceId: deviceId,
        textSummary: 'Toxic content detected in Chrome',
        source: 'com.android.chrome', confidenceScore: 0.76,
        category: IncidentCategory.toxic,
        detectionModel: 'gemini',
        detectedAt: now.subtract(const Duration(hours: 3)),
        isReviewed: false, isAlertSend: true,
        alertSendAt: now.subtract(const Duration(hours: 2, minutes: 59)),
      ),
      IncidentModel(
        incidentId: 'i3', deviceId: deviceId,
        textSummary: 'Toxic content detected in Instagram',
        source: 'com.instagram.android', confidenceScore: 0.61,
        category: IncidentCategory.toxic,
        detectionModel: 'gemini',
        detectedAt: now.subtract(const Duration(days: 1, hours: 2)),
        isReviewed: true,
        reviewedAt: now.subtract(const Duration(days: 1, hours: 1)),
        isAlertSend: false,
      ),
    ];
  }
}