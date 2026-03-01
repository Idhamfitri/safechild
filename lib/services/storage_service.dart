// lib/services/storage_service.dart
// Handles Firebase Storage operations.
// Used for uploading child profile photos during Add Child Device flow.

import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ─── Upload child profile image ───────────────────────────────────────────
  /// Uploads [imageFile] to Firebase Storage under child_images/{deviceId}.jpg
  /// Returns the public download URL string.
  /// Returns null if upload fails.
  Future<String?> uploadChildProfileImage({
    required String deviceId,
    required File imageFile,
  }) async {
    try {
      final ref = _storage
          .ref()
          .child('child_images')
          .child('$deviceId.jpg');

      final uploadTask = await ref.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final url = await uploadTask.ref.getDownloadURL();
      return url;
    } catch (e) {
      return null;
    }
  }

  // ─── Delete child profile image ───────────────────────────────────────────
  Future<void> deleteChildProfileImage(String deviceId) async {
    try {
      await _storage
          .ref()
          .child('child_images')
          .child('$deviceId.jpg')
          .delete();
    } catch (_) {}
  }
}