// lib/models/parent_child_link_model.dart
// UPDATED: Added SetupPhase enum + setup_phase + setup_step fields.
// setup_phase tracks how far the child device has progressed in setup:
//   pending  → parent generated code, waiting for child to enter it
//   paired   → child entered code, now in permission setup wizard
//   active   → child finished all permissions, on ChildActiveScreen
// setup_step → which permission step (0–4) child is currently on

import 'package:cloud_firestore/cloud_firestore.dart';

enum PairingStatus { pending, linked, expired }
enum LinkStatus    { active, removed }
enum SetupPhase    { pending, paired, active }

extension PairingStatusX on PairingStatus {
  String get value => name;
  static PairingStatus fromString(String s) =>
      PairingStatus.values.firstWhere((e) => e.name == s,
          orElse: () => PairingStatus.expired);
}

extension LinkStatusX on LinkStatus {
  String get value => name;
  static LinkStatus fromString(String s) =>
      LinkStatus.values.firstWhere((e) => e.name == s,
          orElse: () => LinkStatus.active);
}

extension SetupPhaseX on SetupPhase {
  String get value => name;
  static SetupPhase fromString(String? s) =>
      SetupPhase.values.firstWhere((e) => e.name == s,
          orElse: () => SetupPhase.pending);
}

class ParentChildLinkModel {
  final String        pCLinkId;
  final String        parentId;
  final String?       deviceId;
  final String        pairingCode;
  final PairingStatus pairingStatus;
  final DateTime?     linkedAt;
  final LinkStatus    linkStatus;
  final SetupPhase    setupPhase;     // NEW
  final int           setupStep;      // NEW — 0-4 permission step index

  ParentChildLinkModel({
    required this.pCLinkId,
    required this.parentId,
    this.deviceId,
    required this.pairingCode,
    this.pairingStatus = PairingStatus.pending,
    this.linkedAt,
    this.linkStatus   = LinkStatus.active,
    this.setupPhase   = SetupPhase.pending,
    this.setupStep    = 0,
  });

  factory ParentChildLinkModel.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return ParentChildLinkModel(
      pCLinkId:      doc.id,
      parentId:      d['parent_id']      ?? '',
      deviceId:      d['device_id'],
      pairingCode:   d['pairing_code']   ?? '',
      pairingStatus: PairingStatusX.fromString(d['pairing_status'] ?? 'pending'),
      linkedAt:      d['linked_at'] != null
          ? (d['linked_at'] as Timestamp).toDate()
          : null,
      linkStatus:  LinkStatusX.fromString(d['link_status'] ?? 'active'),
      setupPhase:  SetupPhaseX.fromString(d['setup_phase']),
      setupStep:   d['setup_step'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'parent_id':      parentId,
        'device_id':      deviceId,
        'pairing_code':   pairingCode,
        'pairing_status': pairingStatus.value,
        if (linkedAt != null) 'linked_at': Timestamp.fromDate(linkedAt!),
        'link_status':    linkStatus.value,
        'setup_phase':    setupPhase.value,
        'setup_step':     setupStep,
      };

  bool get isLinked      => pairingStatus == PairingStatus.linked;
  bool get isPending     => pairingStatus == PairingStatus.pending;
  bool get isExpired     => pairingStatus == PairingStatus.expired;
  bool get isSetupActive => setupPhase == SetupPhase.active;
}