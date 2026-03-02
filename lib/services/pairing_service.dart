// lib/services/pairing_service.dart
// UPDATED: Added setup phase tracking methods called by child device.
//   updateSetupPhase()      → called when child enters code (paired) and finishes (active)
//   updateSetupStep()       → called after each permission is granted
//   updatePermissionStatus()→ updates permission_status map in child_devices

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

  // ══════════════════════════════════════════════════════════════════════════
  //  PARENT SIDE
  // ══════════════════════════════════════════════════════════════════════════

  Future<ParentChildLinkModel> createChildAndGeneratePairingCode({
    required String parentId,
    required String childFullName,
    required int    childAge,
    required String deviceName,
    String? childImageUrl,
    String? deviceId,
  }) async {
    final code   = _generateCode();
    final dId    = deviceId ?? _uuid.v4();
    final linkId = _uuid.v4();

    final device = ChildDeviceModel(
      deviceId:    dId,
      deviceName:  deviceName,
      age:         childAge,
      fullName:    childFullName,
      dateCreated: DateTime.now(),
      image:       childImageUrl,
    );
    await _devices.doc(dId).set(device.toFirestore());

    final link = ParentChildLinkModel(
      pCLinkId:      linkId,
      parentId:      parentId,
      deviceId:      dId,
      pairingCode:   code,
      pairingStatus: PairingStatus.pending,
      linkStatus:    LinkStatus.active,
      setupPhase:    SetupPhase.pending,
      setupStep:     0,
    );
    await _links.doc(linkId).set(link.toFirestore());

    return link;
  }

  /// Real-time listener — fires whenever any field on the link changes.
  /// Parent's PairingCodeScreen subscribes to track setup phases.
  Stream<ParentChildLinkModel> watchLinkStatus(String linkId) =>
      _links.doc(linkId).snapshots().map(ParentChildLinkModel.fromFirestore);

  /// Stream all active links for a parent.
  Stream<List<ParentChildLinkModel>> watchLinkedDevices(String parentId) =>
      _links
          .where('parent_id',    isEqualTo: parentId)
          .where('link_status',  isEqualTo: 'active')
          .snapshots()
          .map((s) => s.docs.map(ParentChildLinkModel.fromFirestore).toList());

  Future<ChildDeviceModel?> getChildDevice(String deviceId) async {
    final doc = await _devices.doc(deviceId).get();
    return doc.exists ? ChildDeviceModel.fromFirestore(doc) : null;
  }

  /// Real-time stream of child device doc (device info + permission status).
  Stream<ChildDeviceModel?> watchChildDevice(String deviceId) =>
      _devices.doc(deviceId).snapshots().map((doc) =>
          doc.exists ? ChildDeviceModel.fromFirestore(doc) : null);

  Future<void> expirePairingCode(String linkId) =>
      _links.doc(linkId).update({'pairing_status': 'expired'});

  Future<void> unlinkDevice(String linkId) =>
      _links.doc(linkId).update({'link_status': 'removed'});

  // ══════════════════════════════════════════════════════════════════════════
  //  CHILD SIDE
  // ══════════════════════════════════════════════════════════════════════════

  /// Matches 6-digit code, updates device hardware info, flips link to linked.
  /// Also sets setup_phase = 'paired' so parent sees child is in permission setup.
  Future<String?> submitPairingCode(String code) async {
    try {
      final snap = await _links
          .where('pairing_code',   isEqualTo: code.trim())
          .where('pairing_status', isEqualTo: 'pending')
          .where('link_status',    isEqualTo: 'active')
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

      // Update child device with hardware info from this physical device
      await _devices.doc(deviceId).update({
        'device_model':    info['model'],
        'manufacturer':    info['manufacturer'],
        'android_version': info['version'],
        'android_sdk':     info['sdk'],
        if (fcmToken != null) 'registration_token': fcmToken,
        'last_sync':       Timestamp.now(),
        // Initialise permission_status map (all false until granted)
        'permission_status': DevicePermissionStatus.none.toMap(),
        'setup_complete': false,
      });

      // Flip link to linked + set phase = paired
      await _links.doc(linkDoc.id).update({
        'pairing_status': 'linked',
        'linked_at':      Timestamp.now(),
        'setup_phase':    'paired',   // ← parent now shows "granting permissions"
        'setup_step':     0,
      });

      return null; // success

    } catch (e) {
      return 'Pairing failed. Please try again. ($e)';
    }
  }

  /// Called after each permission is granted during setup wizard.
  /// Updates BOTH the setup_step in link AND the permission field in device.
  Future<void> updatePermissionGranted({
    required String linkId,
    required String deviceId,
    required int    stepIndex,      // 0=notifications, 1=overlay, 2=usage, 3=accessibility, 4=deviceAdmin
    required String permissionKey,  // 'notifications' | 'overlay' | 'usage_access' | 'accessibility' | 'device_admin'
  }) async {
    await Future.wait([
      // Advance the step shown to parent
      _links.doc(linkId).update({'setup_step': stepIndex + 1}),
      // Mark permission as granted in device doc
      _devices.doc(deviceId).update({
        'permission_status.$permissionKey': true,
        'permission_status.last_updated':   Timestamp.now(),
      }),
    ]);
  }

  /// Called when child arrives at ChildActiveScreen — all setup is complete.
  /// Sets setup_phase = 'active' which triggers parent navigation.
  Future<void> markSetupComplete({
    required String linkId,
    required String deviceId,
    required DevicePermissionStatus finalStatus,
  }) async {
    await Future.wait([
      _links.doc(linkId).update({
        'setup_phase': 'active',
        'setup_step':  5,           // all 5 steps done
      }),
      _devices.doc(deviceId).update({
        'permission_status': finalStatus.toMap(),
        'setup_complete':    true,
        'last_sync':         Timestamp.now(),
      }),
    ]);
  }

  /// Returns the link_id for a given code (stored locally after pairing).
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

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    try {
      final android = await DeviceInfoPlugin().androidInfo;
      return {
        'model':        android.model,
        'manufacturer': android.manufacturer,
        'version':      android.version.release,
        'sdk':          android.version.sdkInt,
      };
    } catch (_) {
      return {
        'model': 'Unknown', 'manufacturer': 'Unknown',
        'version': 'Unknown', 'sdk': 0,
      };
    }
  }

  Future<String?> _getFcmToken() async {
    try { return await FirebaseMessaging.instance.getToken(); }
    catch (_) { return null; }
  }

  /// Returns the device_id for a given code (stored locally alongside link_id).
  Future<String?> getDeviceIdByCode(String code) async {
    final snap = await _links
        .where('pairing_code', isEqualTo: code.trim())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return snap.docs.first.data()['device_id'] as String?;
  }
}