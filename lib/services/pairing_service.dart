// lib/services/pairing_service.dart
// UPDATED: createChildAndGeneratePairingCode now accepts optional deviceId
// (so StorageService can upload the photo to the same ID before this is called)
// and childImageUrl from Firebase Storage.

import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:uuid/uuid.dart';
import '../models/child_device_model.dart';
import '../models/parent_child_link_model.dart';

class PairingService {
  final _db   = FirebaseFirestore.instance;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> get _devices =>
      _db.collection('child_devices');
  CollectionReference<Map<String, dynamic>> get _links =>
      _db.collection('parent_child_links');

  // ══════════════════════════════════════════════════════════════
  //  PARENT SIDE
  // ══════════════════════════════════════════════════════════════

  /// Creates CHILD_DEVICE + PARENT_CHILD_LINK.
  /// [deviceId] can be pre-supplied (so storage upload uses same ID).
  /// [childImageUrl] is the Firebase Storage URL from StorageService.
  Future<ParentChildLinkModel> createChildAndGeneratePairingCode({
    required String parentId,
    required String childFullName,
    required int    childAge,
    required String deviceName,
    String? childImageUrl,
    String? deviceId,           // ← NEW: pass the pre-generated ID
  }) async {
    final code = _generateCode();
    final dId  = deviceId ?? _uuid.v4();
    final linkId = _uuid.v4();

    // 1. Create CHILD_DEVICE document
    final device = ChildDeviceModel(
      deviceId: dId,
      deviceName: deviceName,
      age: childAge,
      fullName: childFullName,
      dateCreated: DateTime.now(),
      image: childImageUrl,
    );
    await _devices.doc(dId).set(device.toFirestore());

    // 2. Create PARENT_CHILD_LINK with pairing code
    final link = ParentChildLinkModel(
      pCLinkId: linkId,
      parentId: parentId,
      deviceId: dId,
      pairingCode: code,
      pairingStatus: PairingStatus.pending,
      linkStatus: LinkStatus.active,
    );
    await _links.doc(linkId).set(link.toFirestore());

    return link;
  }

  /// Real-time listener — parent watches for pairing_status → linked.
  Stream<ParentChildLinkModel> watchLinkStatus(String linkId) =>
      _links.doc(linkId).snapshots().map(ParentChildLinkModel.fromFirestore);

  /// Stream all active links for a parent (for dashboard).
  Stream<List<ParentChildLinkModel>> watchLinkedDevices(String parentId) =>
      _links
          .where('parent_id', isEqualTo: parentId)
          .where('link_status', isEqualTo: 'active')
          .snapshots()
          .map((s) => s.docs.map(ParentChildLinkModel.fromFirestore).toList());

  Future<ChildDeviceModel?> getChildDevice(String deviceId) async {
    final doc = await _devices.doc(deviceId).get();
    return doc.exists ? ChildDeviceModel.fromFirestore(doc) : null;
  }

  Future<void> expirePairingCode(String linkId) =>
      _links.doc(linkId).update({'pairing_status': 'expired'});

  Future<void> unlinkDevice(String linkId) =>
      _links.doc(linkId).update({'link_status': 'removed'});

  // ══════════════════════════════════════════════════════════════
  //  CHILD SIDE
  // ══════════════════════════════════════════════════════════════

  /// Matches the 6-digit code, updates CHILD_DEVICE hardware info,
  /// flips PARENT_CHILD_LINK to linked.
  /// Returns null on success, error string on failure.
  Future<String?> submitPairingCode(String code) async {
    try {
      final snap = await _links
          .where('pairing_code', isEqualTo: code.trim())
          .where('pairing_status', isEqualTo: 'pending')
          .where('link_status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        return 'Invalid or expired code. Please check and try again.';
      }

      final linkDoc  = snap.docs.first;
      final deviceId = linkDoc.data()['device_id'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        return 'Setup error. Please ask the parent to generate a new code.';
      }

      final info     = await _getDeviceInfo();
      final fcmToken = await _getFcmToken();

      // Update CHILD_DEVICE with hardware info
      await _devices.doc(deviceId).update({
        'device_model': info['model'],
        'android_version': info['version'],
        if (fcmToken != null) 'registration_token': fcmToken,
        'last_sync': Timestamp.now(),
      });

      // Flip PARENT_CHILD_LINK to linked
      await _links.doc(linkDoc.id).update({
        'pairing_status': 'linked',
        'linked_at': Timestamp.now(),
      });

      return null; // success

    } catch (e) {
      return 'Pairing failed. Please try again. ($e)';
    }
  }

  /// Returns the link_id for a given code (used to store locally after pairing).
  Future<String?> getLinkIdByCode(String code) async {
    final snap = await _links
        .where('pairing_code', isEqualTo: code.trim())
        .limit(1)
        .get();
    return snap.docs.isEmpty ? null : snap.docs.first.id;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _generateCode() {
    final n = Random.secure().nextInt(1000000);
    return n.toString().padLeft(6, '0');
  }

  Future<Map<String, String>> _getDeviceInfo() async {
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      return {
        'model':   '${android.manufacturer} ${android.model}',
        'version': android.version.release,
      };
    } catch (_) {
      return {'model': 'Unknown Device', 'version': 'Unknown'};
    }
  }

  Future<String?> _getFcmToken() async {
    try { return await FirebaseMessaging.instance.getToken(); }
    catch (_) { return null; }
  }
}