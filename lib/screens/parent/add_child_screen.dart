// lib/screens/parent/add_child_screen.dart
// Parent fills child name, age, device nickname → generates 6-digit pairing code.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/pairing_service.dart';
import '../../utils/validators.dart';
import '../../utils/app_theme.dart';
import 'pairing_code_screen.dart';

class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key});

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  final _formKey       = GlobalKey<FormState>();
  final _pairingService = PairingService();

  final _childNameCtrl  = TextEditingController();
  final _childAgeCtrl   = TextEditingController();
  final _deviceNameCtrl = TextEditingController();

  bool _loading = false;

  Future<void> _generateCode() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final parentId = FirebaseAuth.instance.currentUser!.uid;
      final link = await _pairingService.createChildAndGeneratePairingCode(
        parentId: parentId,
        childFullName: _childNameCtrl.text.trim(),
        childAge: int.parse(_childAgeCtrl.text.trim()),
        deviceName: _deviceNameCtrl.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Child Device')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info banner
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
                          fontSize: 13, color: AppColors.textPrimary, height: 1.4),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 28),

              _label('Child Information'),
              const SizedBox(height: 14),

              TextFormField(
                controller: _childNameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Child\'s Full Name',
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
                    labelText: 'Child\'s Age',
                    prefixIcon: Icon(Icons.cake_outlined),
                    hintText: '6 – 15',
                    helperText: 'SafeChild supports ages 6 to 15.'),
                keyboardType: TextInputType.number,
                validator: Validators.childAge,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 28),

              _label('Device Information'),
              const SizedBox(height: 14),

              TextFormField(
                controller: _deviceNameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Device Nickname',
                    prefixIcon: Icon(Icons.phone_android_outlined),
                    hintText: 'e.g. Amir\'s Tablet',
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
                label: Text(_loading ? 'Generating...' : 'Generate Pairing Code'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Text(text,
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