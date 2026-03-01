// lib/services/pairing_service.dart
// Handles the full pairing flow for BOTH roles in one service.
//
// PARENT side:
//   createChildAndGeneratePairingCode() → creates CHILD_DEVICE + PARENT_CHILD_LINK
//   watchLinkStatus()                   → real-time listener for pairing completion
//
// CHILD side:
//   submitPairingCode()                 → matches code, updates device info, flips status to linked

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

  /// Called when parent submits the "Add Child Device" form.
  /// Returns the link document (which contains the pairing code to show on screen).
  Future<ParentChildLinkModel> createChildAndGeneratePairingCode({
    required String parentId,
    required String childFullName,
    required int childAge,
    required String deviceName,
  }) async {
    final code     = _generateCode();
    final deviceId = _uuid.v4();
    final linkId   = _uuid.v4();

    // 1. Create CHILD_DEVICE document (hardware fields null until child pairs)
    final device = ChildDeviceModel(
      deviceId: deviceId,
      deviceName: deviceName,
      age: childAge,
      fullName: childFullName,
      dateCreated: DateTime.now(),
    );
    await _devices.doc(deviceId).set(device.toFirestore());

    // 2. Create PARENT_CHILD_LINK with the pairing code
    final link = ParentChildLinkModel(
      pCLinkId: linkId,
      parentId: parentId,
      deviceId: deviceId,
      pairingCode: code,
      pairingStatus: PairingStatus.pending,
      linkStatus: LinkStatus.active,
    );
    await _links.doc(linkId).set(link.toFirestore());

    return link;
  }

  /// Real-time listener — parent app watches this to detect when child links.
  Stream<ParentChildLinkModel> watchLinkStatus(String linkId) =>
      _links.doc(linkId).snapshots().map(ParentChildLinkModel.fromFirestore);

  /// Fetch all active linked devices for the dashboard.
  Stream<List<ParentChildLinkModel>> watchLinkedDevices(String parentId) =>
      _links
          .where('parent_id', isEqualTo: parentId)
          .where('link_status', isEqualTo: 'active')
          .snapshots()
          .map((s) =>
              s.docs.map(ParentChildLinkModel.fromFirestore).toList());

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

  /// Called when the child role user enters the 6-digit code.
  /// Returns null on success, or an error message string on failure.
  Future<String?> submitPairingCode(String code) async {
    try {
      // 1. Find a matching pending link
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
      final linkData = linkDoc.data();
      final deviceId = linkData['device_id'] as String?;

      if (deviceId == null || deviceId.isEmpty) {
        return 'Setup error. Please ask the parent to generate a new code.';
      }

      // 2. Collect device hardware info
      final info     = await _getDeviceInfo();
      final fcmToken = await _getFcmToken();

      // 3. Update CHILD_DEVICE with hardware info
      await _devices.doc(deviceId).update({
        'device_model': info['model'],
        'android_version': info['version'],
        if (fcmToken != null) 'registration_token': fcmToken,
        'last_sync': Timestamp.now(),
      });

      // 4. Flip PARENT_CHILD_LINK to linked
      await _links.doc(linkDoc.id).update({
        'pairing_status': 'linked',
        'linked_at': Timestamp.now(),
      });

      // Return the link_id so the child app can store it locally
      return null; // null = success

    } catch (e) {
      return 'Pairing failed. Please try again. ($e)';
    }
  }

  /// After successful pairing, child app needs the link_id for local storage.
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
      final plugin = DeviceInfoPlugin();
      final android = await plugin.androidInfo;
      return {
        'model': '${android.manufacturer} ${android.model}',
        'version': android.version.release,
      };
    } catch (_) {
      return {'model': 'Unknown Device', 'version': 'Unknown'};
    }
  }

  Future<String?> _getFcmToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return null;
    }
  }
}