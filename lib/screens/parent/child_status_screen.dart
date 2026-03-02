// lib/screens/parent/child_status_screen.dart
// UPDATED:
//   - Removed ALL dummy data — shows real Firestore streams only
//   - Added battery level display
//   - Real-time permission status (accessibility_active from heartbeat)
//   - Real-time incidents from Firestore (no dummy list)

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/heartbeat_model.dart';
import '../../models/incident_model.dart';
import '../../services/heartbeat_service.dart';
import '../../services/incident_service.dart';
import '../../utils/app_theme.dart';

class ChildStatusScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;

  const ChildStatusScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  @override
  State<ChildStatusScreen> createState() => _ChildStatusScreenState();
}

class _ChildStatusScreenState extends State<ChildStatusScreen> {
  final _heartbeatService = HeartbeatService();
  final _incidentService  = IncidentService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.deviceName),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: StreamBuilder<HeartbeatModel>(
        stream: _heartbeatService.watchLatestHeartbeat(widget.deviceId),
        builder: (context, hbSnap) {
          final hb = hbSnap.data ?? HeartbeatModel.dummy(widget.deviceId);
          final loading = !hbSnap.hasData;

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Device Status Card ────────────────────────────────────
                _StatusCard(hb: hb, loading: loading),
                const SizedBox(height: 16),

                // ── Permission Status Card ────────────────────────────────
                _PermissionCard(hb: hb, loading: loading),
                const SizedBox(height: 16),

                // ── Recent Incidents ──────────────────────────────────────
                _RecentIncidentsSection(
                  deviceId: widget.deviceId,
                  service:  _incidentService,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Device Status Card ─────────────────────────────────────────────────────
class _StatusCard extends StatelessWidget {
  final HeartbeatModel hb;
  final bool loading;

  const _StatusCard({required this.hb, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.monitor_heart_outlined,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Device Status',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 16),

          // Online/Offline status
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: loading
                    ? Colors.grey.shade200
                    : hb.statusColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: loading
                  ? const Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : Icon(hb.statusIcon, color: hb.statusColor, size: 22),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                loading ? 'Loading...' : hb.statusLabel,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: loading ? AppColors.textSub : hb.statusColor),
              ),
              Text(
                loading ? '—' : 'Last seen: ${hb.lastSeenLabel}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSub),
              ),
            ]),
          ]),

          const Divider(height: 28),

          // Battery row
          Row(children: [
            Icon(
              loading ? Icons.battery_unknown : hb.batteryIcon,
              color: loading ? AppColors.textSub : hb.batteryColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              loading
                  ? 'Battery: —'
                  : hb.batteryLevel != null
                      ? 'Battery: ${hb.batteryLevel}%'
                      : 'Battery: unavailable',
              style: TextStyle(
                  fontSize: 14,
                  color: loading ? AppColors.textSub : hb.batteryColor,
                  fontWeight: FontWeight.w500),
            ),
            if (!loading && hb.batteryLevel != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: hb.batteryLevel! / 100,
                    backgroundColor: Colors.grey.shade200,
                    color: hb.batteryColor,
                    minHeight: 8,
                  ),
                ),
              ),
            ],
          ]),

          const SizedBox(height: 12),

          // SafeChild running status
          _StatusRow(
            icon:  Icons.shield_outlined,
            label: 'SafeChild Service',
            value: loading ? null : hb.safecheckRunning,
          ),
        ]),
      ),
    );
  }
}

// ── Permission Status Card ─────────────────────────────────────────────────
class _PermissionCard extends StatelessWidget {
  final HeartbeatModel hb;
  final bool loading;

  const _PermissionCard({required this.hb, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.security_outlined,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Permission Status',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.textPrimary)),
            const Spacer(),
            if (!loading)
              Text(
                'Updated ${hb.lastSeenLabel}',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSub),
              ),
          ]),
          const SizedBox(height: 16),

          // Accessibility — tracked in real time via heartbeat
          _StatusRow(
            icon:  Icons.accessibility_new_outlined,
            label: 'Accessibility Service',
            value: loading ? null : hb.accessibilityActive,
          ),
          const SizedBox(height: 10),

          // Device Admin — will be active once Module 4 is implemented
          _StatusRow(
            icon:  Icons.admin_panel_settings_outlined,
            label: 'Device Admin',
            value: loading ? null : hb.deviceAdminActive,
            subtitle: hb.deviceAdminActive ? null : 'Enabled in Module 4',
          ),

          if (!loading && (!hb.accessibilityActive || !hb.deviceAdminActive))
            ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFCC02)),
              ),
              child: const Row(children: [
                Icon(Icons.warning_amber, color: Color(0xFFE65100), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'One or more permissions are off. '
                    'Protection may be reduced.',
                    style: TextStyle(
                        fontSize: 12, color: Color(0xFFE65100)),
                  ),
                ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── Recent Incidents Section ───────────────────────────────────────────────
class _RecentIncidentsSection extends StatelessWidget {
  final String         deviceId;
  final IncidentService service;

  const _RecentIncidentsSection({
    required this.deviceId,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Recent Incidents',
          style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.textPrimary)),
      const SizedBox(height: 12),

      StreamBuilder<List<IncidentModel>>(
        stream: service.watchIncidents(deviceId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final incidents = snap.data ?? [];

          if (incidents.isEmpty) {
            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_outline,
                        size: 48, color: Color(0xFF2E7D32)),
                    SizedBox(height: 12),
                    Text('No incidents detected',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 4),
                    Text('All content looks safe so far.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSub)),
                  ]),
                ),
              ),
            );
          }

          // Show latest 10
          final shown = incidents.take(10).toList();
          return Column(
            children: shown
                .map((i) => _IncidentTile(incident: i))
                .toList(),
          );
        },
      ),
    ]);
  }
}

// ── Single incident row ────────────────────────────────────────────────────
class _IncidentTile extends StatelessWidget {
  final IncidentModel incident;
  const _IncidentTile({required this.incident});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: incident.category.color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(incident.category.icon,
              color: incident.category.color, size: 20),
        ),
        title: Text(
          incident.textSummary,
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        subtitle: Text(
          '${incident.confidenceLabel} confidence · '
          '${DateFormat('dd MMM, HH:mm').format(incident.detectedAt)}',
          style: const TextStyle(fontSize: 11, color: AppColors.textSub),
        ),
        trailing: incident.isAlertSend
            ? const Icon(Icons.notifications_active,
                color: Color(0xFFC62828), size: 18)
            : null,
      ),
    );
  }
}

// ── Reusable permission/status row ────────────────────────────────────────
class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool?    value;    // null = loading
  final String?  subtitle;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final isOn    = value == true;
    final color   = value == null
        ? AppColors.textSub
        : isOn
            ? const Color(0xFF2E7D32)
            : const Color(0xFFC62828);

    return Row(children: [
      Icon(icon, color: AppColors.textSub, size: 18),
      const SizedBox(width: 10),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary)),
          if (subtitle != null)
            Text(subtitle!,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSub)),
        ]),
      ),
      if (value == null)
        const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2))
      else
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isOn ? Icons.check_circle : Icons.cancel,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 4),
          Text(
            isOn ? 'ON' : 'OFF',
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.bold),
          ),
        ]),
    ]);
  }
}