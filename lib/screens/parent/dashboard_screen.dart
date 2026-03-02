// lib/screens/parent/dashboard_screen.dart
// UPDATED: Child cards show real-time mini status strip (online, battery,
// last active) via StreamBuilder on HeartbeatService.

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/parent_child_link_model.dart';
import '../../models/child_device_model.dart';
import '../../models/parent_model.dart';
import '../../models/heartbeat_model.dart';
import '../../services/pairing_service.dart';
import '../../services/parent_service.dart';
import '../../services/auth_service.dart';
import '../../services/heartbeat_service.dart';
import '../../utils/app_theme.dart';
import '../auth/login_screen.dart';
import 'add_child_screen.dart';
import 'child_status_screen.dart';

class ParentDashboardScreen extends StatefulWidget {
  const ParentDashboardScreen({super.key});

  @override
  State<ParentDashboardScreen> createState() => _ParentDashboardScreenState();
}

class _ParentDashboardScreenState extends State<ParentDashboardScreen> {
  final _pairingService   = PairingService();
  final _parentService    = ParentService();
  final _authService      = AuthService();
  final _heartbeatService = HeartbeatService();

  String get _parentId => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    // Module 2: save FCM token so Cloud Function can send incident alerts
    _parentService.saveFcmToken(_parentId);
  }

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
        Navigator.pushAndRemoveUntil(context,
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
    if (confirmed == true) await _pairingService.unlinkDevice(link.pCLinkId);
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
        _GreetingHeader(parentId: _parentId, service: _parentService),
        Expanded(
          child: StreamBuilder<List<ParentChildLinkModel>>(
            stream: _pairingService.watchLinkedDevices(_parentId),
            builder: (ctx, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary));
              }
              if (snap.hasError) {
                return Center(
                    child: Text('Error: ${snap.error}',
                        style:
                            const TextStyle(color: AppColors.error)));
              }
              final links = snap.data ?? [];
              if (links.isEmpty) return const _EmptyState();

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                itemCount: links.length,
                itemBuilder: (_, i) => _ChildCard(
                  link:             links[i],
                  pairingService:   _pairingService,
                  heartbeatService: _heartbeatService,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            ChildStatusScreen(link: links[i])),
                  ),
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
  const _GreetingHeader(
      {required this.parentId, required this.service});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ParentModel?>(
      stream: service.watchParent(parentId),
      builder: (_, snap) {
        final name =
            snap.data?.fullName.split(' ').first ?? 'Parent';
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(28)),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hello, $name 👋',
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(height: 4),
                const Text(
                    'Monitor your children\'s devices below.',
                    style: TextStyle(
                        fontSize: 13, color: Colors.white70)),
              ]),
        );
      },
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.phone_android_outlined,
            size: 72,
            color: AppColors.textSub.withOpacity(0.3)),
        const SizedBox(height: 16),
        const Text('No devices linked yet',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textSub)),
        const SizedBox(height: 6),
        const Text('Tap "Add Child" to link a device.',
            style: TextStyle(
                fontSize: 13, color: AppColors.textSub)),
      ]),
    );
  }
}

// ─── Child device card ────────────────────────────────────────────────────────
class _ChildCard extends StatelessWidget {
  final ParentChildLinkModel link;
  final PairingService       pairingService;
  final HeartbeatService     heartbeatService;
  final VoidCallback         onTap;
  final VoidCallback         onUnlink;

  const _ChildCard({
    required this.link,
    required this.pairingService,
    required this.heartbeatService,
    required this.onTap,
    required this.onUnlink,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ChildDeviceModel?>(
      future: pairingService.getChildDevice(link.deviceId ?? ''),
      builder: (_, devSnap) {
        final device     = devSnap.data;
        final childName  = device?.fullName  ?? '—';
        final childAge   = device?.age;
        final deviceName = device?.deviceName ?? '—';
        final isPaired   = device?.isPaired   ?? false;

        return Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top row: avatar + info + menu ──────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ChildAvatar(
                          imageUrl: device?.image, name: childName),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(childName,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            if (childAge != null)
                              Text('Age $childAge',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSub)),
                            const SizedBox(height: 4),
                            Text(deviceName,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSub),
                                overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            _StatusBadge(
                                isPaired: isPaired,
                                status: link.pairingStatus),
                          ],
                        ),
                      ),
                      Column(children: [
                        PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'unlink') onUnlink();
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'unlink',
                              child: Row(children: [
                                Icon(Icons.link_off,
                                    color: AppColors.error,
                                    size: 18),
                                SizedBox(width: 8),
                                Text('Unlink Device',
                                    style: TextStyle(
                                        color: AppColors.error)),
                              ]),
                            ),
                          ],
                        ),
                        const Icon(Icons.chevron_right,
                            color: AppColors.textSub, size: 18),
                      ]),
                    ],
                  ),

                  // ── Real-time mini status strip ───────────────────
                  if (link.isLinked && link.deviceId != null) ...[
                    const SizedBox(height: 10),
                    const Divider(color: AppColors.divider, height: 1),
                    const SizedBox(height: 10),
                    _MiniStatusStrip(
                      deviceId:         link.deviceId!,
                      heartbeatService: heartbeatService,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Mini real-time status strip ─────────────────────────────────────────────
class _MiniStatusStrip extends StatelessWidget {
  final String           deviceId;
  final HeartbeatService heartbeatService;

  const _MiniStatusStrip({
    required this.deviceId,
    required this.heartbeatService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<HeartbeatModel>(
      stream: heartbeatService.watchLatestHeartbeat(deviceId),
      builder: (_, snap) {
        final hb = snap.data ?? HeartbeatModel.dummy(deviceId);

        return Row(children: [
          // GREEN / YELLOW / RED status from heartbeat timing
          _chip(
            icon: hb.statusIcon,
            iconColor: hb.statusColor,
            label: hb.statusLabel,
            bgColor: hb.statusColor.withOpacity(0.1),
          ),
          const SizedBox(width: 6),

          // Last heartbeat timestamp
          _chip(
            icon: Icons.access_time_outlined,
            iconColor: AppColors.textSub,
            label: hb.lastSeenText,
            bgColor: AppColors.divider.withOpacity(0.5),
          ),
          const SizedBox(width: 6),

          // Device admin / protection state
          _chip(
            icon: hb.deviceAdminActive
                ? Icons.admin_panel_settings
                : Icons.admin_panel_settings_outlined,
            iconColor: hb.deviceAdminActive
                ? AppColors.statusLinked
                : AppColors.error,
            label: hb.deviceAdminActive ? 'Protected' : 'Unprotected',
            bgColor: hb.deviceAdminActive
                ? AppColors.statusLinked.withOpacity(0.08)
                : AppColors.error.withOpacity(0.08),
          ),
        ]);
      },
    );
  }

  Widget _chip({
    required IconData icon,
    required Color    iconColor,
    required String   label,
    required Color    bgColor,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: iconColor),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: iconColor,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

// ─── Child avatar ─────────────────────────────────────────────────────────────
class _ChildAvatar extends StatelessWidget {
  final String? imageUrl;
  final String  name;
  const _ChildAvatar(
      {required this.imageUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: AppColors.primary.withOpacity(0.12),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: imageUrl!,
            width: 56, height: 56,
            fit: BoxFit.cover,
            placeholder: (_, __) => const CircularProgressIndicator(
                strokeWidth: 2, color: AppColors.primary),
            errorWidget: (_, __, ___) => _initials(),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 28,
      backgroundColor: AppColors.primary.withOpacity(0.12),
      child: _initials(),
    );
  }

  Widget _initials() => Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: const TextStyle(
            fontSize: 22,
            color: AppColors.primary,
            fontWeight: FontWeight.bold),
      );
}

// ─── Status badge ─────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final bool          isPaired;
  final PairingStatus status;
  const _StatusBadge(
      {required this.isPaired, required this.status});

  @override
  Widget build(BuildContext context) {
    late Color    color;
    late String   label;
    late IconData icon;

    if (status == PairingStatus.linked && isPaired) {
      color = AppColors.statusLinked;
      label = 'Active';
      icon  = Icons.check_circle_outline;
    } else if (status == PairingStatus.pending) {
      color = AppColors.statusPending;
      label = 'Pending Link';
      icon  = Icons.hourglass_empty;
    } else {
      color = AppColors.statusExpired;
      label = 'Inactive';
      icon  = Icons.cancel_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
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