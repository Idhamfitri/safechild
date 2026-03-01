// lib/models/incident_model.dart
// ─────────────────────────────────────────────────────────────────────────────
// Maps to Firestore collection: incidents/{incident_id}
// Written by Module 2 content detection (Gemini API + Random Forest).
//
// Business rules (MODULE3_WORKFLOW Part 7):
//   - confidence_score >= 0.5  → incident is logged
//   - confidence_score >= 0.75 → FCM alert is also sent to parent
//   - Raw text is NEVER stored — only text_summary (privacy NFR)
//
// Schema:
//   device_id        – which child device triggered this
//   text_summary     – privacy-safe AI summary of what was detected
//   source           – "accessibility_service" | "screenshot" | "url"
//   confidence_score – 0.0–1.0 from detection model
//   category         – "violence" | "adult" | "gambling" | "drugs" | "bullying"
//   detection_model  – "gemini_api" | "random_forest" | "combined"
//   detected_at      – timestamp
//   is_reviewed      – parent has viewed
//   reviewed_at      – when parent reviewed
//   is_alert_send    – FCM was sent (only when score >= 0.75)
//   alert_send_at    – when FCM was sent
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum IncidentCategory { violence, adult, gambling, drugs, bullying, unknown }
enum DetectionModel   { geminiApi, randomForest, combined }

extension IncidentCategoryX on IncidentCategory {
  String get displayLabel {
    switch (this) {
      case IncidentCategory.violence:  return 'Violence';
      case IncidentCategory.adult:     return 'Adult Content';
      case IncidentCategory.gambling:  return 'Gambling';
      case IncidentCategory.drugs:     return 'Drugs';
      case IncidentCategory.bullying:  return 'Bullying';
      case IncidentCategory.unknown:   return 'Unknown';
    }
  }

  Color get color {
    switch (this) {
      case IncidentCategory.violence:  return const Color(0xFFD32F2F);
      case IncidentCategory.adult:     return const Color(0xFFE91E63);
      case IncidentCategory.gambling:  return const Color(0xFF6A1B9A);
      case IncidentCategory.drugs:     return const Color(0xFF1565C0);
      case IncidentCategory.bullying:  return const Color(0xFFE65100);
      case IncidentCategory.unknown:   return const Color(0xFF757575);
    }
  }

  IconData get icon {
    switch (this) {
      case IncidentCategory.violence:  return Icons.dangerous_outlined;
      case IncidentCategory.adult:     return Icons.no_adult_content_outlined;
      case IncidentCategory.gambling:  return Icons.casino_outlined;
      case IncidentCategory.drugs:     return Icons.medication_outlined;
      case IncidentCategory.bullying:  return Icons.person_off_outlined;
      case IncidentCategory.unknown:   return Icons.help_outline;
    }
  }
}

IncidentCategory _catFromString(String? s) {
  switch (s) {
    case 'violence':  return IncidentCategory.violence;
    case 'adult':     return IncidentCategory.adult;
    case 'gambling':  return IncidentCategory.gambling;
    case 'drugs':     return IncidentCategory.drugs;
    case 'bullying':  return IncidentCategory.bullying;
    default:          return IncidentCategory.unknown;
  }
}

DetectionModel _modelFromString(String? s) {
  switch (s) {
    case 'gemini_api':     return DetectionModel.geminiApi;
    case 'random_forest':  return DetectionModel.randomForest;
    default:               return DetectionModel.combined;
  }
}

class IncidentModel {
  final String          incidentId;
  final String          deviceId;
  final String          textSummary;
  final String          source;
  final double          confidenceScore;
  final IncidentCategory category;
  final DetectionModel  detectionModel;
  final DateTime        detectedAt;
  final bool            isReviewed;
  final DateTime?       reviewedAt;
  final bool            isAlertSend;
  final DateTime?       alertSendAt;

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
      deviceId:        d['device_id']    ?? '',
      textSummary:     d['text_summary'] ?? '',
      source:          d['source']       ?? '',
      confidenceScore: (d['confidence_score'] ?? 0.0).toDouble(),
      category:        _catFromString(d['category']),
      detectionModel:  _modelFromString(d['detection_model']),
      detectedAt:      (d['detected_at'] as Timestamp).toDate(),
      isReviewed:      d['is_reviewed']   ?? false,
      reviewedAt: d['reviewed_at'] != null
          ? (d['reviewed_at'] as Timestamp).toDate()
          : null,
      isAlertSend:  d['is_alert_send']  ?? false,
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
        'category':         category.name,
        'detection_model':  detectionModel == DetectionModel.geminiApi
            ? 'gemini_api'
            : detectionModel == DetectionModel.randomForest
                ? 'random_forest'
                : 'combined',
        'detected_at':    Timestamp.fromDate(detectedAt),
        'is_reviewed':    isReviewed,
        if (reviewedAt != null) 'reviewed_at': Timestamp.fromDate(reviewedAt!),
        'is_alert_send':  isAlertSend,
        if (alertSendAt != null) 'alert_send_at': Timestamp.fromDate(alertSendAt!),
      };

  // ── Business rule helpers ─────────────────────────────────────────────────
  bool get alertThresholdMet => confidenceScore >= 0.75;
  bool get logThresholdMet   => confidenceScore >= 0.5;

  String get confidenceLabel {
    if (confidenceScore >= 0.90) return 'Very High';
    if (confidenceScore >= 0.75) return 'High';
    if (confidenceScore >= 0.50) return 'Medium';
    return 'Low';
  }

  // ── Dummy incidents (shown until Module 2 writes real data) ───────────────
  static List<IncidentModel> dummies(String deviceId) {
    final now = DateTime.now();
    return [
      IncidentModel(
        incidentId: 'i1', deviceId: deviceId,
        textSummary: 'Content involving violence detected on YouTube browsing',
        source: 'accessibility_service', confidenceScore: 0.87,
        category: IncidentCategory.violence,
        detectionModel: DetectionModel.combined,
        detectedAt: now.subtract(const Duration(hours: 1, minutes: 30)),
        isReviewed: false, isAlertSend: true,
        alertSendAt: now.subtract(const Duration(hours: 1, minutes: 29)),
      ),
      IncidentModel(
        incidentId: 'i2', deviceId: deviceId,
        textSummary: 'Possible adult content detected during web browsing session',
        source: 'accessibility_service', confidenceScore: 0.76,
        category: IncidentCategory.adult,
        detectionModel: DetectionModel.geminiApi,
        detectedAt: now.subtract(const Duration(hours: 3, minutes: 0)),
        isReviewed: false, isAlertSend: true,
        alertSendAt: now.subtract(const Duration(hours: 2, minutes: 59)),
      ),
      IncidentModel(
        incidentId: 'i3', deviceId: deviceId,
        textSummary: 'Gambling-related terms found in messaging app',
        source: 'accessibility_service', confidenceScore: 0.61,
        category: IncidentCategory.gambling,
        detectionModel: DetectionModel.randomForest,
        detectedAt: now.subtract(const Duration(days: 1, hours: 2)),
        isReviewed: true,
        reviewedAt: now.subtract(const Duration(days: 1, hours: 1)),
        isAlertSend: false,
      ),
    ];
  }
}