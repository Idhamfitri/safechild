import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/parent_model.dart';
import '../../services/auth_service.dart';
import '../../services/parent_service.dart';
import '../../utils/app_theme.dart';

class ParentSettingsScreen extends StatelessWidget {
  final String parentId;

  const ParentSettingsScreen({super.key, required this.parentId});

  @override
  Widget build(BuildContext context) {
    final parentService = ParentService();
    final authService   = AuthService();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Account Settings')),
      body: StreamBuilder<ParentModel?>(
        stream: parentService.watchParent(parentId),
        builder: (context, snap) {
          final parent = snap.data;
          return ListView(
            children: [
              _ProfileHeader(parent: parent),
              const SizedBox(height: 8),
              _SettingsSection(
                parent:        parent,
                authService:   authService,
                parentService: parentService,
                parentId:      parentId,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Profile header card ──────────────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final ParentModel? parent;
  const _ProfileHeader({required this.parent});

  @override
  Widget build(BuildContext context) {
    final name    = parent?.fullName ?? '—';
    final email   = parent?.email   ?? '—';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final joined  = parent != null
        ? '${parent!.dateCreated.day}/${parent!.dateCreated.month}/${parent!.dateCreated.year}'
        : '—';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: Colors.white.withValues(alpha:0.25),
            child: Text(
              initial,
              style: const TextStyle(
                  fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 14),
          Text(name,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 4),
          Text(email,
              style: const TextStyle(fontSize: 13, color: Colors.white70)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha:0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Member since $joined',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Settings tiles section ───────────────────────────────────────────────────
class _SettingsSection extends StatelessWidget {
  final ParentModel?   parent;
  final AuthService    authService;
  final ParentService  parentService;
  final String         parentId;

  const _SettingsSection({
    required this.parent,
    required this.authService,
    required this.parentService,
    required this.parentId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha:0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        children: [
          _tile(
            context,
            icon:     Icons.email_outlined,
            title:    'Change Email',
            subtitle: 'Update your login email address',
            onTap:    () => _showChangeEmailDialog(context),
          ),
          const Divider(height: 1, indent: 56),
          _tile(
            context,
            icon:     Icons.lock_outline,
            title:    'Change Password',
            subtitle: 'Update your account password',
            onTap:    () => _showChangePasswordDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData   icon,
    required String     title,
    required String     subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha:0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
      title: Text(title,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSub),
      onTap: onTap,
    );
  }

  // ── Change email dialog ────────────────────────────────────────────────────
  void _showChangeEmailDialog(BuildContext context) {
    final currentPasswordCtrl = TextEditingController();
    final newEmailCtrl        = TextEditingController();
    bool loading              = false;
    String? errorMsg;
    bool obscure              = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Change Email',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller:  currentPasswordCtrl,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => obscure = !obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller:   newEmailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'New Email',
                  border:    OutlineInputBorder(),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 10),
                _errorBox(errorMsg!),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: loading
                  ? null
                  : () async {
                      final pwd      = currentPasswordCtrl.text.trim();
                      final newEmail = newEmailCtrl.text.trim();
                      if (pwd.isEmpty || newEmail.isEmpty) {
                        setState(() => errorMsg = 'All fields are required.');
                        return;
                      }
                      setState(() { loading = true; errorMsg = null; });
                      try {
                        await authService.updateEmail(
                            currentPassword: pwd, newEmail: newEmail);
                        // Sync new email to Firestore immediately
                        await parentService.updateEmail(parentId, newEmail);
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Verification email sent. Please verify to complete the change.'),
                              backgroundColor: Color(0xFF2E7D32),
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        setState(() {
                          loading  = false;
                          errorMsg = AuthService.getErrorMessage(e);
                        });
                      } catch (e) {
                        setState(() {
                          loading  = false;
                          errorMsg = 'Failed to update. Please try again.';
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Change password dialog ─────────────────────────────────────────────────
  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordCtrl = TextEditingController();
    final newPasswordCtrl     = TextEditingController();
    final confirmPasswordCtrl = TextEditingController();
    bool loading   = false;
    String? errorMsg;
    bool obscureCurrent = true;
    bool obscureNew     = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Change Password',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller:  currentPasswordCtrl,
                obscureText: obscureCurrent,
                decoration: InputDecoration(
                  labelText: 'Current Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureCurrent ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => obscureCurrent = !obscureCurrent),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller:  newPasswordCtrl,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller:  confirmPasswordCtrl,
                obscureText: obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm New Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
              ),
              if (errorMsg != null) ...[
                const SizedBox(height: 10),
                _errorBox(errorMsg!),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: loading
                  ? null
                  : () async {
                      final current  = currentPasswordCtrl.text.trim();
                      final newPass  = newPasswordCtrl.text;
                      final confirm  = confirmPasswordCtrl.text;
                      if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
                        setState(() => errorMsg = 'All fields are required.');
                        return;
                      }
                      if (newPass != confirm) {
                        setState(() => errorMsg = 'New passwords do not match.');
                        return;
                      }
                      if (newPass.length < 6) {
                        setState(() => errorMsg = 'Password must be at least 6 characters.');
                        return;
                      }
                      setState(() { loading = true; errorMsg = null; });
                      try {
                        await authService.updatePassword(
                            currentPassword: current, newPassword: newPass);
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Password updated successfully.'),
                              backgroundColor: Color(0xFF2E7D32),
                            ),
                          );
                        }
                      } on FirebaseAuthException catch (e) {
                        setState(() {
                          loading  = false;
                          errorMsg = AuthService.getErrorMessage(e);
                        });
                      } catch (e) {
                        setState(() {
                          loading  = false;
                          errorMsg = 'Failed to update. Please try again.';
                        });
                      }
                    },
              child: loading
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha:0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.error.withValues(alpha:0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.error_outline, size: 14, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(
              child: Text(msg,
                  style: const TextStyle(fontSize: 12, color: AppColors.error))),
        ]),
      );
}
