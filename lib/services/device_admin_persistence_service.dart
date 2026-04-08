// lib/services/device_admin_persistence_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_policy_manager/device_policy_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceAdminPersistenceService {

  // ── Call on every app start ────────────────────────────────────────────
  // Checks if an active parent-child link exists.
  // If YES  → ensure device admin stays active
  // If NO   → remove device admin (allow clean uninstall)
  static Future<void> checkAndEnforce() async {
    try {
      final prefs    = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('device_id');

      if (deviceId == null) {
        debugPrint('ADMIN_PERSIST: no device_id — skipping');
        return;
      }

      // Check for active parent-child link
      final snap = await FirebaseFirestore.instance
          .collection('parent_child_links')
          .where('device_id',   isEqualTo: deviceId)
          .where('link_status', isEqualTo: 'active')
          .limit(1)
          .get();

      final hasActiveLink = snap.docs.isNotEmpty;
      debugPrint('ADMIN_PERSIST: hasActiveLink = $hasActiveLink');

      final adminActive = await DevicePolicyManager.isPermissionGranted();
      debugPrint('ADMIN_PERSIST: adminActive = $adminActive');

      if (hasActiveLink) {
        // Parent is monitoring — keep device admin active
        if (!adminActive) {
          // Admin was revoked — log bypass event and request re-enable
          debugPrint('ADMIN_PERSIST: admin was revoked — logging bypass event');
          await _logAdminRevoked(deviceId);
          // Note: Cannot force re-enable — Android requires user consent
          // The permission setup screen will prompt on next app open
        } else {
          debugPrint('ADMIN_PERSIST: device admin active and link exists — OK');
        }
      } else {
        // No active parent link — remove device admin to allow clean uninstall
        if (adminActive) {
          debugPrint('ADMIN_PERSIST: no active link — removing device admin');
          await DevicePolicyManager.removeActiveAdmin();
        }
      }
    } catch (e) {
      debugPrint('ADMIN_PERSIST: error — $e');
    }
  }

  // ── Log admin revocation as bypass event ──────────────────────────────
  static Future<void> _logAdminRevoked(String deviceId) async {
    try {
      await FirebaseFirestore.instance.collection('bypass_events').add({
        'device_id':         deviceId,
        'event_type':        'permission_revoked',
        'event_description': 'Device Administrator permission was revoked by child',
        'is_blocked':        false,
        'is_reviewed':       false,
        'is_alert_send':     false,
        'detected_at':       FieldValue.serverTimestamp(),
      });
      debugPrint('ADMIN_PERSIST: bypass event logged ✓');
    } catch (e) {
      debugPrint('ADMIN_PERSIST: Firestore write failed — $e');
    }
  }
}