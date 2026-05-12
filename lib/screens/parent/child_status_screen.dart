// lib/screens/parent/child_status_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/bypass_event_model.dart';
import '../../models/heartbeat_model.dart';
import '../../models/incident_model.dart';
import '../../services/bypass_event_service.dart';
import '../../services/heartbeat_service.dart';
import '../../services/incident_service.dart';
import '../../utils/app_theme.dart';
import 'screen_time_mgmt_screen.dart';
import 'configuration_setting_screen.dart';
import 'widgets/status_cards.dart';

class ChildStatusScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;
  final String linkId;

  const ChildStatusScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
    required this.linkId,
  });

  @override
  State<ChildStatusScreen> createState() => _ChildStatusScreenState();
}

class _ChildStatusScreenState extends State<ChildStatusScreen>
    with SingleTickerProviderStateMixin {
  final _heartbeatService = HeartbeatService();
  final _incidentService  = IncidentService();
  final _bypassService    = BypassEventService();
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
            icon:       Icon(Icons.dashboard_outlined),
            activeIcon: Icon(Icons.dashboard),
            label:      'Dashboard',
          ),
          BottomNavigationBarItem(
            icon:       Icon(Icons.lock_clock_outlined),
            activeIcon: Icon(Icons.lock_clock),
            label:      'Lock',
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
          ScreenTimeMgmtScreen(deviceId: widget.deviceId, deviceName: widget.deviceName),
          _buildAlertsTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }

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
                DeviceHeaderCard(deviceData: deviceData, hb: hb),
                const SizedBox(height: 14),
                DeviceStatusCard(hb: hb),
                const SizedBox(height: 14),
                PermissionCard(deviceData: deviceData),
                const SizedBox(height: 14),
                ScreenTimeSection(
                  deviceId: widget.deviceId,
                  tabCtrl:  _screenTimeTab,
                  onManageTap: () => setState(() => _currentTab = 1),
                ),
                const SizedBox(height: 14),
                RecentAppsSection(deviceId: widget.deviceId),
                const SizedBox(height: 14),
                _IncidentsOverviewSection(
                  deviceId: widget.deviceId,
                  service:  _incidentService,
                  onViewAll: () => setState(() => _currentTab = 2),
                ),
                const SizedBox(height: 14),
                _BypassOverviewSection(
                  deviceId: widget.deviceId,
                  service:  _bypassService,
                  onViewAll: () => setState(() => _currentTab = 2),
                ),
                const SizedBox(height: 24),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAlertsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Content Incidents',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          StreamBuilder<List<IncidentModel>>(
            stream: _incidentService.watchIncidents(widget.deviceId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
              }
              final incidents = (snap.data ?? []).where((i) => !i.isReviewed).toList();
              if (incidents.isEmpty) {
                return buildEmptyCard(
                  icon: Icons.check_circle_outline,
                  message: 'No unresolved incidents',
                  sub: 'All content incidents have been reviewed.',
                );
              }
              return _AlertListContainer(
                itemCount: incidents.length,
                itemBuilder: (context, index) => AlertsIncidentTile(
                  incident: incidents[index],
                  service:  _incidentService,
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          const Text('Bypass Attempts',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          StreamBuilder<List<BypassEventModel>>(
            stream: _bypassService.watchBypassEvents(widget.deviceId),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
              }
              final events = (snap.data ?? []).where((b) => !b.isReviewed).toList();
              if (events.isEmpty) {
                return buildEmptyCard(
                  icon: Icons.verified_user_outlined,
                  message: 'No bypass attempts',
                  sub: 'No suspicious activity detected.',
                );
              }
              return _AlertListContainer(
                itemCount: events.length,
                itemBuilder: (context, index) => AlertsBypassTile(
                  event:   events[index],
                  service: _bypassService,
                ),
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ConfigurationSettingScreen(linkId: widget.linkId);
  }
}

class _IncidentsOverviewSection extends StatelessWidget {
  final String          deviceId;
  final IncidentService service;
  final VoidCallback    onViewAll;

  const _IncidentsOverviewSection({
    required this.deviceId,
    required this.service,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text('Recent Incidents',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textPrimary)),
        ),
        const Spacer(),
        TextButton(
          onPressed: onViewAll,
          child: const Text('View All',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 8),
      StreamBuilder<List<IncidentModel>>(
        stream: service.watchIncidents(deviceId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
          }
          final incidents = snap.data ?? [];
          if (incidents.isEmpty) {
            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_outline, size: 44, color: Color(0xFF2E7D32)),
                    SizedBox(height: 10),
                    Text('No incidents detected', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    SizedBox(height: 4),
                    Text('All content looks safe.', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                  ]),
                ),
              ),
            );
          }
          return Column(
            children: incidents.take(3).map((i) => IncidentTile(incident: i)).toList(),
          );
        },
      ),
    ]);
  }
}

class _BypassOverviewSection extends StatelessWidget {
  final String           deviceId;
  final BypassEventService service;
  final VoidCallback     onViewAll;

  const _BypassOverviewSection({
    required this.deviceId,
    required this.service,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text('Bypass Attempts',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textPrimary)),
        ),
        const Spacer(),
        TextButton(
          onPressed: onViewAll,
          child: const Text('View All',
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 8),
      StreamBuilder<List<BypassEventModel>>(
        stream: service.watchBypassEvents(deviceId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
          }
          final events = snap.data ?? [];
          if (events.isEmpty) {
            return Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.verified_user_outlined, size: 44, color: Color(0xFF2E7D32)),
                    SizedBox(height: 10),
                    Text('No bypass attempts', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    SizedBox(height: 4),
                    Text('No suspicious activity detected.', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                  ]),
                ),
              ),
            );
          }
          return Column(
            children: events.take(3).map((e) => BypassTile(event: e)).toList(),
          );
        },
      ),
    ]);
  }
}

class _AlertListContainer extends StatelessWidget {
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  const _AlertListContainer({required this.itemCount, required this.itemBuilder});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 380),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: ListView.separated(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: itemCount,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}