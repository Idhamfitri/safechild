// lib/screens/auth/register_screen.dart
//
// FLOW:
//  Step 1 — User selects role: "Parent" or "Child Device"
//
//  If PARENT selected:
//    Step 2 — Fill: Full Name, Email, Password, Confirm Password
//    Step 3 — Submit → Firebase Auth + Firestore PARENT doc created
//    Step 4 → Navigate to ParentDashboardScreen
//             (parent then uses "Add Child Device" from dashboard to generate pairing code)
//
//  If CHILD selected:
//    Step 2 — Enter 6-digit pairing code (given by parent)
//    Step 3 → ChildPairingService matches code → updates CHILD_DEVICE + PARENT_CHILD_LINK
//    Step 4 → Navigate to ChildActiveScreen (monitoring mode)

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:pinput/pinput.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../services/parent_service.dart';
import '../../services/pairing_service.dart';
import '../../utils/validators.dart';
import '../../utils/app_theme.dart';
import 'login_screen.dart';
import '../parent/dashboard_screen.dart';
import '../child/child_active_screen.dart';
import '../child/permission_setup_screen.dart';

// ─── Which role the user picked ──────────────────────────────────────────────
enum _Role { none, parent, child }

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────
  final _authService    = AuthService();
  final _parentService  = ParentService();
  final _pairingService = PairingService();

  // ── State ─────────────────────────────────────────────────────────────────
  _Role _selectedRole = _Role.none;
  bool  _loading      = false;

  // ── Animation (slide-in for the form below role cards) ───────────────────
  late AnimationController _animCtrl;
  late Animation<Offset>   _slideAnim;
  late Animation<double>   _fadeAnim;

  // ── Parent form ───────────────────────────────────────────────────────────
  final _parentFormKey   = GlobalKey<FormState>();
  final _nameCtrl        = TextEditingController();
  final _emailCtrl       = TextEditingController();
  final _passCtrl        = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool  _obscurePass     = true;
  bool  _obscureConfirm  = true;

  // ── Child pairing ─────────────────────────────────────────────────────────
  final _codeCtrl   = TextEditingController();
  final _codeFocus  = FocusNode();
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeIn);
  }

  // ─── Select role ──────────────────────────────────────────────────────────
  void _selectRole(_Role role) {
    if (_selectedRole == role) return;
    setState(() {
      _selectedRole = role;
      _codeError    = null;
    });
    _animCtrl.forward(from: 0);
    if (role == _Role.child) {
      Future.delayed(const Duration(milliseconds: 400),
          () => _codeFocus.requestFocus());
    }
  }

  // ─── PARENT: Register ─────────────────────────────────────────────────────
  Future<void> _registerParent() async {
    if (!_parentFormKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final cred = await _authService.registerParent(
        email: _emailCtrl.text,
        password: _passCtrl.text,
      );
      await _parentService.createParentProfile(
        parentId: cred.user!.uid,
        email: _emailCtrl.text.trim(),
        fullName: _nameCtrl.text.trim(),
      );
      // Store role
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('role', 'parent');

      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
            (_) => false);
      }
    } on FirebaseAuthException catch (e) {
      _snack(AuthService.getErrorMessage(e), color: AppColors.error);
    } catch (_) {
      _snack('Registration failed. Please try again.', color: AppColors.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── CHILD: Submit pairing code ───────────────────────────────────────────
  Future<void> _submitPairingCode(String code) async {
    if (code.length != 6) return;
    setState(() {
      _loading   = true;
      _codeError = null;
    });
    try {
      final error = await _pairingService.submitPairingCode(code);
      if (error != null) {
        setState(() => _codeError = error);
        _codeCtrl.clear();
        _codeFocus.requestFocus();
        return;
      }
      // Get link_id to store locally
      final linkId = await _pairingService.getLinkIdByCode(code);
      final prefs  = await SharedPreferences.getInstance();
      await prefs.setString('role', 'child');
      if (linkId != null) await prefs.setString('link_id', linkId);

      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const PermissionSetupScreen()),
            (_) => false);
      }
    } catch (_) {
      setState(() => _codeError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, {required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  BUILD
  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              const SizedBox(height: 12),
              Row(children: [
                const Icon(Icons.shield, size: 32, color: AppColors.primary),
                const SizedBox(width: 10),
                const Text('SafeChild',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
              ]),
              const SizedBox(height: 28),

              const Text('Create Account',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('Select your role to get started.',
                  style: TextStyle(fontSize: 14, color: AppColors.textSub)),

              const SizedBox(height: 28),

              // ── Role Selection Cards ───────────────────────────────────────
              const Text('I am a...',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSub,
                      letterSpacing: 0.5)),
              const SizedBox(height: 12),

              Row(children: [
                Expanded(
                    child: _RoleCard(
                  icon: Icons.supervisor_account_outlined,
                  label: 'Parent',
                  subtitle: 'Monitor my child\'s device',
                  selected: _selectedRole == _Role.parent,
                  onTap: () => _selectRole(_Role.parent),
                )),
                const SizedBox(width: 14),
                Expanded(
                    child: _RoleCard(
                  icon: Icons.phone_android_outlined,
                  label: 'Child Device',
                  subtitle: 'Set up with a pairing code',
                  selected: _selectedRole == _Role.child,
                  onTap: () => _selectRole(_Role.child),
                )),
              ]),

              // ── Role-specific form (animated slide-in) ────────────────────
              if (_selectedRole != _Role.none) ...[
                const SizedBox(height: 32),
                SlideTransition(
                  position: _slideAnim,
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: _selectedRole == _Role.parent
                        ? _buildParentForm()
                        : _buildChildPairingForm(),
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // ── Already have account ──────────────────────────────────────
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Text('Already have an account?',
                    style: TextStyle(color: AppColors.textSub)),
                TextButton(
                  onPressed: () => Navigator.pushReplacement(context,
                      MaterialPageRoute(builder: (_) => const LoginScreen())),
                  child: const Text('Log In',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // ── Parent registration form ──────────────────────────────────────────────
  Widget _buildParentForm() {
    return Form(
      key: _parentFormKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Section label
        _sectionLabel('Parent Details'),
        const SizedBox(height: 14),

        // Full Name
        TextFormField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
              labelText: 'Full Name',
              prefixIcon: Icon(Icons.person_outline)),
          textCapitalization: TextCapitalization.words,
          validator: Validators.fullName,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),

        // Email
        TextFormField(
          controller: _emailCtrl,
          decoration: const InputDecoration(
              labelText: 'Email Address',
              prefixIcon: Icon(Icons.email_outlined)),
          keyboardType: TextInputType.emailAddress,
          validator: Validators.email,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),

        // Password
        TextFormField(
          controller: _passCtrl,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscurePass
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: () => setState(() => _obscurePass = !_obscurePass),
            ),
          ),
          obscureText: _obscurePass,
          validator: Validators.password,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 14),

        // Confirm Password
        TextFormField(
          controller: _confirmPassCtrl,
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscureConfirm
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: () =>
                  setState(() => _obscureConfirm = !_obscureConfirm),
            ),
          ),
          obscureText: _obscureConfirm,
          validator: (v) => Validators.confirmPassword(v, _passCtrl.text),
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _registerParent(),
        ),

        const SizedBox(height: 28),

        // Submit
        ElevatedButton(
          onPressed: _loading ? null : _registerParent,
          child: _loading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Create Parent Account'),
        ),
      ]),
    );
  }

  // ── Child pairing code form ───────────────────────────────────────────────
  Widget _buildChildPairingForm() {
    final defaultTheme = PinTheme(
      width: 50,
      height: 58,
      textStyle: const TextStyle(
          fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.primary),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
    );

    final focusedTheme = defaultTheme.copyWith(
      decoration: defaultTheme.decoration!.copyWith(
          border: Border.all(color: AppColors.primary, width: 2)),
    );

    final errorTheme = defaultTheme.copyWith(
      decoration: defaultTheme.decoration!.copyWith(
          border: Border.all(color: AppColors.error, width: 2)),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('Device Setup'),
      const SizedBox(height: 6),
      const Text(
        'Ask your parent to open SafeChild on their phone and go to '
        '"Add Child Device" to get the 6-digit pairing code.',
        style: TextStyle(fontSize: 13, color: AppColors.textSub, height: 1.5),
      ),
      const SizedBox(height: 24),

      // 6-digit PIN input — centred
      Center(
        child: Pinput(
          controller: _codeCtrl,
          focusNode: _codeFocus,
          length: 6,
          keyboardType: TextInputType.number,
          defaultPinTheme: defaultTheme,
          focusedPinTheme: focusedTheme,
          errorPinTheme: _codeError != null ? errorTheme : null,
          onCompleted: _submitPairingCode,
          enabled: !_loading,
        ),
      ),

      // Error
      if (_codeError != null) ...[
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 15),
          const SizedBox(width: 6),
          Flexible(
            child: Text(_codeError!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: AppColors.error, fontSize: 13)),
          ),
        ]),
      ],

      const SizedBox(height: 24),

      // Submit
      ElevatedButton(
        onPressed: _loading ? null : () => _submitPairingCode(_codeCtrl.text),
        child: _loading
            ? const SizedBox(
                width: 22, height: 22,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Text('Link This Device'),
      ),
    ]);
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary),
      );

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    _codeCtrl.dispose();
    _codeFocus.dispose();
    super.dispose();
  }
}

// ─── Role Selection Card widget ───────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                      color: AppColors.primary.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Column(children: [
          Icon(icon,
              size: 36, color: selected ? Colors.white : AppColors.primary),
          const SizedBox(height: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11,
                  color: selected
                      ? Colors.white.withOpacity(0.8)
                      : AppColors.textSub,
                  height: 1.3)),
        ]),
      ),
    );
  }
}