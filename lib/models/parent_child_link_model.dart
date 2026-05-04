// lib/models/parent_child_link_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum PairingStatus { pending, linked, expired }
enum LinkStatus    { active, removed }

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


class ParentChildLinkModel {
  final String        pCLinkId;
  final String        parentId;
  final String?       deviceId;
  final String        pairingCode;
  final PairingStatus pairingStatus;
  final DateTime?     linkedAt;
  final LinkStatus    linkStatus;

  ParentChildLinkModel({
    required this.pCLinkId,
    required this.parentId,
    this.deviceId,
    required this.pairingCode,
    this.pairingStatus = PairingStatus.pending,
    this.linkedAt,
    this.linkStatus   = LinkStatus.active,
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
    );
  }

  Map<String, dynamic> toFirestore() => {
        'parent_id':      parentId,
        'device_id':      deviceId,
        'pairing_code':   pairingCode,
        'pairing_status': pairingStatus.value,
        if (linkedAt != null) 'linked_at': Timestamp.fromDate(linkedAt!),
        'link_status':    linkStatus.value,
      };

  bool get isLinked      => pairingStatus == PairingStatus.linked;
  bool get isPending     => pairingStatus == PairingStatus.pending;
  bool get isExpired     => pairingStatus == PairingStatus.expired;
}