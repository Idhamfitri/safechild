// lib/screens/parent/add_child_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../../services/pairing_service.dart';
import '../../services/storage_service.dart';
import '../../utils/validators.dart';
import '../../utils/app_theme.dart';
import 'pairing_code_screen.dart';

class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key});

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  final _formKey        = GlobalKey<FormState>();
  final _pairingService = PairingService();
  final _storageService = StorageService();
  final _picker         = ImagePicker();
  final _uuid           = const Uuid();

  final _childNameCtrl  = TextEditingController();
  final _childAgeCtrl   = TextEditingController();
  final _deviceNameCtrl = TextEditingController();

  File?   _selectedImage;   // locally picked file
  bool    _loading = false;
  String? _uploadError;

  // ─── Pick image from camera or gallery ───────────────────────────────────
  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 512,
        maxHeight: 512,
      );
      if (picked != null) {
        setState(() {
          _selectedImage = File(picked.path);
          _uploadError   = null;
        });
      }
    } catch (e) {
      setState(() => _uploadError = 'Could not pick image. Please try again.');
    }
  }

  // ─── Show bottom sheet to choose source ──────────────────────────────────
  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Choose Photo',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.primary,
              child: Icon(Icons.camera_alt, color: Colors.white, size: 20),
            ),
            title: const Text('Take a Photo'),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: AppColors.accent,
              child: Icon(Icons.photo_library, color: Colors.white, size: 20),
            ),
            title: const Text('Choose from Gallery'),
            onTap: () {
              Navigator.pop(context);
              _pickImage(ImageSource.gallery);
            },
          ),
          if (_selectedImage != null)
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.error,
                child: Icon(Icons.delete, color: Colors.white, size: 20),
              ),
              title: const Text('Remove Photo',
                  style: TextStyle(color: AppColors.error)),
              onTap: () {
                Navigator.pop(context);
                setState(() => _selectedImage = null);
              },
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  // ─── Generate pairing code ────────────────────────────────────────────────
  Future<void> _generateCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _uploadError = null; });

    try {
      final parentId = FirebaseAuth.instance.currentUser!.uid;
      final tempDeviceId = _uuid.v4();

      String? imageUrl;
      if (_selectedImage != null) {
        imageUrl = await _storageService.uploadChildProfileImage(
          deviceId: tempDeviceId,
          imageFile: _selectedImage!,
        );
        if (imageUrl == null) {
          setState(() {
            _uploadError = 'Photo upload failed. You can add it later.';
            _loading = false;
          });
        }
      }

      // 2. Create CHILD_DEVICE + PARENT_CHILD_LINK
      final link = await _pairingService.createChildAndGeneratePairingCode(
        parentId: parentId,
        childFullName: _childNameCtrl.text.trim(),
        childAge: int.parse(_childAgeCtrl.text.trim()),
        deviceName: _deviceNameCtrl.text.trim(),
        childImageUrl: imageUrl,
        deviceId: tempDeviceId,   
      );

      if (!mounted) return;
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => PairingCodeScreen(link: link)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to generate code: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Child Device')),
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Photo picker ──────────────────────────────────────────────
              Center(child: _buildPhotoPicker()),
              if (_uploadError != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text(_uploadError!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 12)),
                ),
              ],
              const SizedBox(height: 28),

              // ── Info banner ───────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.accent.withOpacity(0.35)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: AppColors.primary, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Fill in your child\'s details. A 6-digit pairing code '
                      'will be generated for you to enter on the child\'s device.',
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textPrimary,
                          height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),

              // ── Child information ─────────────────────────────────────────
              _sectionLabel('Child Information'),
              const SizedBox(height: 14),

              TextFormField(
                controller: _childNameCtrl,
                decoration: const InputDecoration(
                    labelText: "Child's Full Name",
                    prefixIcon: Icon(Icons.child_care_outlined),
                    hintText: 'e.g. Muhammad Amir'),
                textCapitalization: TextCapitalization.words,
                validator: Validators.fullName,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),

              TextFormField(
                controller: _childAgeCtrl,
                decoration: const InputDecoration(
                    labelText: "Child's Age",
                    prefixIcon: Icon(Icons.cake_outlined),
                    hintText: '6 – 15',
                    helperText: 'SafeChild supports ages 6 to 15.'),
                keyboardType: TextInputType.number,
                validator: Validators.childAge,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 28),

              // ── Device information ────────────────────────────────────────
              _sectionLabel('Device Information'),
              const SizedBox(height: 14),

              TextFormField(
                controller: _deviceNameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Device Nickname',
                    prefixIcon: Icon(Icons.phone_android_outlined),
                    hintText: "e.g. Amir's Tablet",
                    helperText: 'A label shown on your dashboard.'),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    Validators.required(v, fieldName: 'Device nickname'),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _generateCode(),
              ),
              const SizedBox(height: 36),

              ElevatedButton.icon(
                onPressed: _loading ? null : _generateCode,
                icon: _loading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.link),
                label: Text(
                    _loading ? 'Generating...' : 'Generate Pairing Code'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Photo picker avatar ───────────────────────────────────────────────────
  Widget _buildPhotoPicker() {
    return GestureDetector(
      onTap: _showImageSourceSheet,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 56,
            backgroundColor: AppColors.primary.withOpacity(0.1),
            backgroundImage:
                _selectedImage != null ? FileImage(_selectedImage!) : null,
            child: _selectedImage == null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.person_outline,
                          size: 36,
                          color: AppColors.primary.withOpacity(0.6)),
                      const SizedBox(height: 4),
                      Text('Add Photo',
                          style: TextStyle(
                              fontSize: 10,
                              color: AppColors.primary.withOpacity(0.7),
                              fontWeight: FontWeight.w500)),
                    ],
                  )
                : null,
          ),
          // Camera badge
          Positioned(
            bottom: 0, right: 0,
            child: Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.camera_alt,
                  size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text,
      style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary));

  @override
  void dispose() {
    _childNameCtrl.dispose();
    _childAgeCtrl.dispose();
    _deviceNameCtrl.dispose();
    super.dispose();
  }
}