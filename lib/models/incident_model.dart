import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum IncidentCategory {
  toxic,        
  threatening,  
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
  final String           description;   
  final String           source;
  final double           confidenceScore;
  final IncidentCategory category;
  final String           detectionModel;
  final DateTime         detectedAt;
  final bool             isReviewed;
  final DateTime?        reviewedAt;
  final bool             isFalsePositive; // Added for false positive review
  final bool             isResolved;      // True if handled/acknowledged by parent
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
    this.isFalsePositive = false, // default false
    this.isResolved      = false,
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
      description:     d['description']       ?? '',  
      source:          d['source']            ?? '',
      confidenceScore: (d['confidence_score'] ?? 0.0).toDouble(),
      category:        _catFromString(d['category']),
      detectionModel:  d['detection_model']   ?? 'gemini',
      detectedAt: d['detected_at'] != null 
          ? (d['detected_at'] as Timestamp).toDate()
          : DateTime.now(),
      isReviewed:      d['is_reviewed']        ?? false,
      reviewedAt: d['reviewed_at'] != null
          ? (d['reviewed_at'] as Timestamp).toDate()
          : null,
      isFalsePositive: d['is_false_positive']  ?? false,
      isResolved:      d['is_resolved']       ?? false,
      isAlertSend: d['is_alert_send'] ?? false,
      alertSendAt: d['alert_send_at'] != null
          ? (d['alert_send_at'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'device_id':        deviceId,
        'text_summary':     textSummary,
        'description':      description,   
        'source':           source,
        'confidence_score': confidenceScore,
        'category':         category.value,
        'detection_model':  detectionModel,
        'detected_at':      FieldValue.serverTimestamp(),
        'is_reviewed':      isReviewed,
        if (reviewedAt != null) 'reviewed_at': Timestamp.fromDate(reviewedAt!),
        'is_false_positive': isFalsePositive,
        'is_resolved':       isResolved,
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