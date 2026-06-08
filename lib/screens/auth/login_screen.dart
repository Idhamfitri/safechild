// lib/screens/auth/login_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/auth_service.dart';
import '../../utils/validators.dart';
import '../../utils/app_theme.dart';
import 'register_screen.dart';
import '../parent/dashboard_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../admin/admin_screen.dart';
import '../../services/admin_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _authService = AuthService();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();

  bool _loading   = false;
  bool _obscure   = true;

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final cred = await _authService.loginParent(
          email: _emailCtrl.text, password: _passCtrl.text);

      final prefs = await SharedPreferences.getInstance();

      // ── Admin short-circuit ────────────────────────────────────────────────
      if (AdminService.isAdminEmail(cred.user?.email)) {
        await prefs.setString('role', 'admin');
        if (mounted) {
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const AdminScreen()),
              (_) => false);
        }
        return;
      }

      // ── Normal parent ─────────────────────────────────────────────────────
      // Check if account has been suspended before allowing access
      final parentDoc = await FirebaseFirestore.instance
          .collection('parents')
          .doc(cred.user!.uid)
          .get();
      final accountStatus =
          parentDoc.data()?['account_status'] as String? ?? 'active';

      if (accountStatus == 'suspended') {
        await _authService.logout();
        if (mounted) _showSuspendedDialog();
        return;
      }

      await prefs.setString('role', 'parent');
      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
            (_) => false);
      }
    } on FirebaseAuthException catch (e) {
      _error(AuthService.getErrorMessage(e));
    } catch (_) {
      _error('Login failed. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (Validators.email(email) != null) {
      _error('Enter your email address first.');
      return;
    }
    try {
      await _authService.sendPasswordResetEmail(email);
      _snack('Password reset email sent.', color: AppColors.primary);
    } catch (_) {
      _error('Could not send reset email.');
    }
  }

  void _showSuspendedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.block, color: Colors.orange, size: 22),
          SizedBox(width: 10),
          Text('Account Suspended',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: const Text(
          'Your account has been suspended.\n\n'
          'Please contact admin support at:\nadmin@safechild.com',
          style: TextStyle(fontSize: 13, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _error(String msg) => _snack(msg, color: AppColors.error);

  void _snack(String msg, {required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating));
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                // ── Logo ─────────────────────────────────────────────────────
                Center(
                  child: Column(children: [
                    Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.shield,
                          size: 44, color: AppColors.primary),
                    ),
                    const SizedBox(height: 14),
                    const Text('SafeChild',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    const Text('Parent Portal',
                        style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                  ]),
                ),

                const SizedBox(height: 40),

                // ── Email ─────────────────────────────────────────────────────
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: Icon(Icons.email_outlined)),
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),

                // ── Password ──────────────────────────────────────────────────
                TextFormField(
                  controller: _passCtrl,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  obscureText: _obscure,
                  validator: Validators.password,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                ),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _forgotPassword,
                    child: const Text('Forgot Password?',
                        style: TextStyle(color: AppColors.primary)),
                  ),
                ),

                const SizedBox(height: 8),

                // ── Login Button ──────────────────────────────────────────────
                ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : const Text('Log In'),
                ),

                const SizedBox(height: 28),
                // ── Register link ─────────────────────────────────────────────
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('New to SafeChild?',
                      style: TextStyle(color: AppColors.textSub)),
                  TextButton(
                    onPressed: () => Navigator.pushReplacement(context,
                        MaterialPageRoute(
                            builder: (_) => const RegisterScreen())),
                    child: const Text('Create Account',
                        style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }
}