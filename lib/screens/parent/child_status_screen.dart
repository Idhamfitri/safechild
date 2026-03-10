// lib/screens/parent/child_status_screen.dart
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

class _ChildStatusScreenState extends State<ChildStatusScreen>
    with SingleTickerProviderStateMixin {
  final _heartbeatService = HeartbeatService();
  final _incidentService  = IncidentService();
  late  TabController _screenTimeTab;

  int _currentTab = 0;

  @override
  void initState() {
    super.initState();
    _screenTimeTab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _screenTimeTab.dispose();
    super.dispose();
  }

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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (i) => setState(() => _currentTab = i),
        selectedItemColor:   AppColors.primary,
        unselectedItemColor: AppColors.textSub,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon:       Icon(Icons.monitor_heart_outlined),
            activeIcon: Icon(Icons.monitor_heart),
            label:      'Overview',
          ),
          BottomNavigationBarItem(
            icon:       Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label:      'Alerts',
          ),
          BottomNavigationBarItem(
            icon:       Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label:      'Settings',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentTab,
        children: [
          _buildOverviewTab(),
          _buildAlertsTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

  // ── Tab 0 — Overview ──────────────────────────────────────────────────────
  Widget _buildOverviewTab() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('child_devices')
          .doc(widget.deviceId)
          .snapshots(),
      builder: (context, deviceSnap) {
        final deviceData = deviceSnap.data?.data();
        return StreamBuilder<HeartbeatModel>(
          stream: _heartbeatService.watchHeartbeat(widget.deviceId),
          builder: (context, hbSnap) {
            final hb = hbSnap.data ?? HeartbeatModel.empty(widget.deviceId);
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _DeviceHeaderCard(deviceData: deviceData, hb: hb),
                const SizedBox(height: 14),
                _DeviceStatusCard(hb: hb),
                const SizedBox(height: 14),
                _PermissionCard(deviceData: deviceData),
                const SizedBox(height: 14),
                _ScreenTimeSection(
                  deviceId: widget.deviceId,
                  tabCtrl:  _screenTimeTab,
                ),
                const SizedBox(height: 14),
                _RecentAppsSection(deviceId: widget.deviceId),
                const SizedBox(height: 14),
                _IncidentsSection(
                  deviceId: widget.deviceId,
                  service:  _incidentService,
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        );
      },
    );
  }

  // ── Tab 1 — Alerts (empty placeholder) ────────────────────────────────────
  Widget _buildAlertsTab() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.notifications_outlined, size: 64, color: Color(0xFFBDBDBD)),
        SizedBox(height: 16),
        Text('Alerts',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        SizedBox(height: 8),
        Text('Incident alerts for this device will appear here.',
            style: TextStyle(fontSize: 13, color: AppColors.textSub)),
      ]),
    );
  }

  // ── Tab 2 — Settings (empty placeholder) ──────────────────────────────────
  Widget _buildSettingsTab() {
    return const Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.settings_outlined, size: 64, color: Color(0xFFBDBDBD)),
        SizedBox(height: 16),
        Text('Device Settings',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        SizedBox(height: 8),
        Text('Per-device configuration will appear here.',
            style: TextStyle(fontSize: 13, color: AppColors.textSub)),
      ]),
    );
  }
}

// ── Device Header Card ─────────────────────────────────────────────────────
class _DeviceHeaderCard extends StatelessWidget {
  final Map<String, dynamic>? deviceData;
  final HeartbeatModel        hb;

  const _DeviceHeaderCard({required this.deviceData, required this.hb});

  @override
  Widget build(BuildContext context) {
    final name         = deviceData?['full_name']       ?? '—';
    final deviceName   = deviceData?['device_name']     ?? '—';
    final deviceModel  = deviceData?['device_model']    ?? '—';
    final manufacturer = deviceData?['manufacturer']    ?? '';
    final age          = deviceData?['age'];
    final androidVer   = deviceData?['android_version'] ?? '—';
    final dateCreated  = deviceData?['date_created'];
    final imageUrl     = deviceData?['image_url'] as String?;
    // android_sdk — removed from display
    // registration_token (FCM) — not displayed for security

    String createdLabel = '—';
    if (dateCreated != null) {
      createdLabel = DateFormat('dd MMM yyyy')
          .format((dateCreated as Timestamp).toDate());
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Avatar + name + status
          Row(children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.12),
                image: imageUrl != null
                    ? DecorationImage(
                        image: NetworkImage(imageUrl),
                        fit: BoxFit.cover)
                    : null,
              ),
              child: imageUrl == null
                  ? Icon(Icons.person, size: 36, color: AppColors.primary)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                if (age != null)
                  Text('Age $age',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSub)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: hb.statusColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.circle, size: 8, color: hb.statusColor),
                    const SizedBox(width: 5),
                    Text(hb.statusLabel,
                        style: TextStyle(
                            fontSize: 11,
                            color: hb.statusColor,
                            fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
          ]),

          const Divider(height: 24),

          _InfoRow(
              icon:  Icons.phone_android_outlined,
              label: 'Device',
              value: '$manufacturer $deviceModel'),
          const SizedBox(height: 8),
          _InfoRow(
              icon:  Icons.smartphone_outlined,
              label: 'Device Name',
              value: deviceName),
          const SizedBox(height: 8),
          _InfoRow(
              icon:  Icons.android_outlined,
              label: 'Android',
              value: 'Version $androidVer'),
          const SizedBox(height: 8),
          _InfoRow(
              icon:  Icons.calendar_today_outlined,
              label: 'Registered',
              value: createdLabel),
        ]),
      ),
    );
  }
}

// ── Device Status Card ─────────────────────────────────────────────────────
class _DeviceStatusCard extends StatelessWidget {
  final HeartbeatModel hb;
  const _DeviceStatusCard({required this.hb});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              icon: Icons.monitor_heart_outlined, title: 'Device Status'),
          const SizedBox(height: 16),

          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: hb.statusColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(hb.statusIcon, color: hb.statusColor, size: 20),
            ),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hb.statusLabel,
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: hb.statusColor)),
              Text('Last sync: ${hb.lastSeenLabel}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSub)),
            ]),
          ]),

          const Divider(height: 24),

          // Battery
          Row(children: [
            Icon(hb.batteryIcon, color: hb.batteryColor, size: 20),
            const SizedBox(width: 8),
            Text(
              hb.batteryLevel != null
                  ? 'Battery: ${hb.batteryLevel}%'
                  : 'Battery: —',
              style: TextStyle(
                  fontSize: 14,
                  color: hb.batteryColor,
                  fontWeight: FontWeight.w500),
            ),
            if (hb.batteryLevel != null) ...[
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

          _StatusRow(
              icon:  Icons.shield_outlined,
              label: 'SafeChild Running',
              isOn:  hb.safechidRunning),
        ]),
      ),
    );
  }
}

// ── Permission Status Card ─────────────────────────────────────────────────
class _PermissionCard extends StatelessWidget {
  final Map<String, dynamic>? deviceData;
  const _PermissionCard({required this.deviceData});

  @override
  Widget build(BuildContext context) {
    final permMap            = deviceData?['permission_status'];
    final bool accessibility = permMap?['accessibility'] == true;
    final bool notifications = permMap?['notifications'] == true;
    final bool overlay       = permMap?['overlay']       == true;
    final bool usageAccess   = permMap?['usage_access']  == true;

    // ── Device Admin — commented out until Module 4 ───────────────────────
    // final bool deviceAdmin = permMap?['device_admin'] == true;

    final lastUpdated = permMap?['last_updated'];
    String updatedLabel = '';
    if (lastUpdated != null) {
      final dt   = (lastUpdated as Timestamp).toDate();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60)      updatedLabel = 'just now';
      else if (diff.inMinutes < 60) updatedLabel = '${diff.inMinutes}m ago';
      else if (diff.inHours   < 24) updatedLabel = '${diff.inHours}h ago';
      else                          updatedLabel = '${diff.inDays}d ago';
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.security_outlined,
                color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            const Text('Permission Status',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.textPrimary)),
            const Spacer(),
            if (updatedLabel.isNotEmpty)
              Text('Updated $updatedLabel',
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSub)),
          ]),
          const SizedBox(height: 16),

          _StatusRow(
              icon:  Icons.accessibility_new_outlined,
              label: 'Accessibility Service',
              isOn:  accessibility),
          const SizedBox(height: 10),
          _StatusRow(
              icon:  Icons.notifications_outlined,
              label: 'Notifications',
              isOn:  notifications),
          const SizedBox(height: 10),
          _StatusRow(
              icon:  Icons.picture_in_picture_alt_outlined,
              label: 'Display Over Apps',
              isOn:  overlay),
          const SizedBox(height: 10),
          _StatusRow(
              icon:  Icons.bar_chart_outlined,
              label: 'Usage Access',
              isOn:  usageAccess),

          // ── Device Admin — commented out until Module 4 ─────────────────
          // const SizedBox(height: 10),
          // _StatusRow(
          //   icon:  Icons.admin_panel_settings_outlined,
          //   label: 'Device Admin',
          //   isOn:  deviceAdmin,
          // ),

          if (!accessibility)
            _WarningBanner(
                message: 'Accessibility Service is OFF — '
                    'AI content detection is not running.'),
        ]),
      ),
    );
  }
}

// ── Screen Time Section ────────────────────────────────────────────────────
class _ScreenTimeSection extends StatelessWidget {
  final String        deviceId;
  final TabController tabCtrl;

  const _ScreenTimeSection({
    required this.deviceId,
    required this.tabCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              icon: Icons.access_time_outlined, title: 'Screen Time Usage'),
          const SizedBox(height: 12),

          Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: tabCtrl,
              indicator: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor:            Colors.white,
              unselectedLabelColor:  AppColors.textSub,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              dividerColor: Colors.transparent,
              tabs: const [Tab(text: 'Daily'), Tab(text: 'Weekly')],
            ),
          ),
          const SizedBox(height: 16),

          SizedBox(
            height: 120,
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.bar_chart_outlined,
                    size: 40, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                const Text('Screen time data not yet available',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.textSub)),
                const Text('Will be enabled in Module 3',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.textSub)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Recently Used Apps Section ─────────────────────────────────────────────
class _RecentAppsSection extends StatelessWidget {
  final String deviceId;
  const _RecentAppsSection({required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SectionTitle(
              icon: Icons.apps_outlined, title: 'Recently Used Apps'),
          const SizedBox(height: 16),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.phone_android_outlined,
                  size: 40, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              const Text('App usage data not yet available',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSub)),
              const Text('Will be enabled in Module 3',
                  style: TextStyle(
                      fontSize: 11, color: AppColors.textSub)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ── Recent Incidents Section ───────────────────────────────────────────────
class _IncidentsSection extends StatelessWidget {
  final String          deviceId;
  final IncidentService service;

  const _IncidentsSection({
    required this.deviceId,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 12),
        child: Text('Recent Incidents',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: AppColors.textPrimary)),
      ),
      StreamBuilder<List<IncidentModel>>(
        stream: service.watchIncidents(deviceId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator()));
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
                        size: 44, color: Color(0xFF2E7D32)),
                    SizedBox(height: 10),
                    Text('No incidents detected',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 4),
                    Text('All content looks safe.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSub)),
                  ]),
                ),
              ),
            );
          }

          return Column(
            children: incidents
                .take(10)
                .map((i) => _IncidentTile(incident: i))
                .toList(),
          );
        },
      ),
    ]);
  }
}

// ── Incident Tile ──────────────────────────────────────────────────────────
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
        title: Text(incident.textSummary,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        subtitle: Text(
          '${incident.confidenceLabel} · '
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

// ── Shared Widgets ─────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String   title;
  const _SectionTitle({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, color: AppColors.primary, size: 18),
      const SizedBox(width: 8),
      Text(title,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: AppColors.textPrimary)),
    ]);
  }
}

class _StatusRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final bool     isOn;

  const _StatusRow({
    required this.icon,
    required this.label,
    required this.isOn,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOn ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    return Row(children: [
      Icon(icon, color: AppColors.textSub, size: 18),
      const SizedBox(width: 10),
      Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textPrimary))),
      Icon(isOn ? Icons.check_circle : Icons.cancel, color: color, size: 18),
      const SizedBox(width: 4),
      Text(isOn ? 'ON' : 'OFF',
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.bold)),
    ]);
  }
}

class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFCC02)),
      ),
      child: Row(children: [
        const Icon(Icons.warning_amber, color: Color(0xFFE65100), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFFE65100))),
        ),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: AppColors.textSub),
      const SizedBox(width: 8),
      Text('$label: ',
          style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}