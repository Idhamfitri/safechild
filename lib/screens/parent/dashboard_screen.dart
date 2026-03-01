// lib/screens/parent/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/parent_child_link_model.dart';
import '../../models/child_device_model.dart';
import '../../models/parent_model.dart';
import '../../services/pairing_service.dart';
import '../../services/parent_service.dart';
import '../../services/auth_service.dart';
import '../../utils/app_theme.dart';
import '../auth/login_screen.dart';
import 'add_child_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final _pairingService = PairingService();
  final _parentService  = ParentService();
  final _authService    = AuthService();

  String get _parentId => FirebaseAuth.instance.currentUser!.uid;

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Log Out')),
        ],
      ),
    );
    if (confirmed == true) {
      await _authService.logout();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('role');
      if (mounted) {
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false);
      }
    }
  }

  Future<void> _unlinkDevice(ParentChildLinkModel link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove Device'),
        content: const Text(
            'Unlink this child\'s device? Monitoring will stop immediately.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed == true) {
      await _pairingService.unlinkDevice(link.pCLinkId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('SafeChild'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
              icon: const Icon(Icons.logout_outlined),
              tooltip: 'Log Out',
              onPressed: _logout),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AddChildScreen())),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Child'),
      ),
      body: Column(children: [
        // ── Greeting header ─────────────────────────────────────────────────
        _GreetingHeader(parentId: _parentId, service: _parentService),

        // ── Device list ─────────────────────────────────────────────────────
        Expanded(
          child: StreamBuilder<List<ParentChildLinkModel>>(
            stream: _pairingService.watchLinkedDevices(_parentId),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary));
              }
              if (snap.hasError) {
                return Center(
                    child: Text('Error: ${snap.error}',
                        style: const TextStyle(color: AppColors.error)));
              }
              final links = snap.data ?? [];
              if (links.isEmpty) return _EmptyState();

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: links.length,
                itemBuilder: (_, i) => _ChildCard(
                  link: links[i],
                  pairingService: _pairingService,
                  onUnlink: () => _unlinkDevice(links[i]),
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

// ─── Greeting header ──────────────────────────────────────────────────────────
class _GreetingHeader extends StatelessWidget {
  final String parentId;
  final ParentService service;
  const _GreetingHeader({required this.parentId, required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ParentModel?>(
      stream: service.watchParent(parentId),
      builder: (_, snap) {
        final name = snap.data?.fullName.split(' ').first ?? 'Parent';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius:
                BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hello, $name 👋',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            const SizedBox(height: 4),
            const Text('Monitor your children\'s devices below.',
                style: TextStyle(fontSize: 13, color: Colors.white70)),
          ]),
        );
      },
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.phone_android_outlined,
            size: 72, color: AppColors.textSub.withOpacity(0.35)),
        const SizedBox(height: 16),
        const Text('No devices linked yet',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSub)),
        const SizedBox(height: 6),
        const Text('Tap "Add Child" to link a device.',
            style: TextStyle(fontSize: 13, color: AppColors.textSub)),
      ]),
    );
  }
}

// ─── Child device card ────────────────────────────────────────────────────────
class _ChildCard extends StatelessWidget {
  final ParentChildLinkModel link;
  final PairingService pairingService;
  final VoidCallback onUnlink;

  const _ChildCard(
      {required this.link,
      required this.pairingService,
      required this.onUnlink});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChildDeviceModel?>(
      future: pairingService.getChildDevice(link.deviceId ?? ''),
      builder: (_, snap) {
        final device     = snap.data;
        final childName  = device?.fullName ?? '—';
        final childAge   = device?.age;
        final deviceName = device?.deviceName ?? '—';
        final model      = device?.deviceModel;
        final isPaired   = device?.isPaired ?? false;

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Avatar
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary.withOpacity(0.12),
                backgroundImage:
                    device?.image != null ? NetworkImage(device!.image!) : null,
                child: device?.image == null
                    ? Text(
                        childName.isNotEmpty
                            ? childName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                            fontSize: 22,
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold))
                    : null,
              ),
              const SizedBox(width: 14),

              // Details
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(childName,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  if (childAge != null) ...[
                    const SizedBox(height: 2),
                    Text('Age $childAge',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSub)),
                  ],
                  const SizedBox(height: 8),
                  _row(Icons.phone_android_outlined, deviceName),
                  if (model != null) _row(Icons.devices_outlined, model),
                  const SizedBox(height: 8),
                  _StatusBadge(isPaired: isPaired, status: link.pairingStatus),
                ]),
              ),

              // Menu
              PopupMenuButton<String>(
                onSelected: (v) { if (v == 'unlink') onUnlink(); },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'unlink',
                    child: Row(children: [
                      Icon(Icons.link_off, color: AppColors.error, size: 18),
                      SizedBox(width: 8),
                      Text('Unlink Device',
                          style: TextStyle(color: AppColors.error)),
                    ]),
                  ),
                ],
              ),
            ]),
          ),
        );
      },
    );
  }

  Widget _row(IconData icon, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(children: [
          Icon(icon, size: 13, color: AppColors.textSub),
          const SizedBox(width: 6),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                overflow: TextOverflow.ellipsis),
          ),
        ]),
      );
}

// ─── Status badge ─────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final bool isPaired;
  final PairingStatus status;
  const _StatusBadge({required this.isPaired, required this.status});

  @override
  Widget build(BuildContext context) {
    late Color color;
    late String label;
    late IconData icon;

    if (status == PairingStatus.linked && isPaired) {
      color = AppColors.statusLinked; label = 'Active'; icon = Icons.check_circle_outline;
    } else if (status == PairingStatus.pending) {
      color = AppColors.statusPending; label = 'Pending Link'; icon = Icons.hourglass_empty;
    } else {
      color = AppColors.statusExpired; label = 'Inactive'; icon = Icons.cancel_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}