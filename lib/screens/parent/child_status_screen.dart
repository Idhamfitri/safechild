// lib/screens/parent/child_status_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Bottom-nav shell screen with 3 tabs:
//   Tab 0 — Status   : live heartbeat + screen time + recent apps
//   Tab 1 — Settings : ConfigurationSettingScreen
//   Tab 2 — Alerts   : NotificationAlertScreen (bypass + incidents)
//
// Header: child avatar, name, age, device.
// Notification bell badge: total unreviewed bypass + incident count.
// Status uses GREEN/YELLOW/RED from HeartbeatModel.dashboardStatus.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../models/parent_child_link_model.dart';
import '../../models/child_device_model.dart';
import '../../models/heartbeat_model.dart';
import '../../services/pairing_service.dart';
import '../../services/heartbeat_service.dart';
import '../../services/bypass_event_service.dart';
import '../../services/incident_service.dart';
import '../../utils/app_theme.dart';
import 'configuration_setting_screen.dart';
import 'notification_alert_screen.dart';

class ChildStatusScreen extends StatefulWidget {
  final ParentChildLinkModel link;
  const ChildStatusScreen({super.key, required this.link});

  @override
  State<ChildStatusScreen> createState() => _ChildStatusScreenState();
}

class _ChildStatusScreenState extends State<ChildStatusScreen>
    with SingleTickerProviderStateMixin {
  final _pairingService   = PairingService();
  final _heartbeatService = HeartbeatService();
  final _bypassService    = BypassEventService();
  final _incidentService  = IncidentService();

  ChildDeviceModel? _device;
  int _tabIndex = 0;
  late TabController _chartTabCtrl;
  int _chartTab = 0;

  @override
  void initState() {
    super.initState();
    _chartTabCtrl = TabController(length: 3, vsync: this)
      ..addListener(() {
        if (!_chartTabCtrl.indexIsChanging) {
          setState(() => _chartTab = _chartTabCtrl.index);
        }
      });
    _loadDevice();
  }

  Future<void> _loadDevice() async {
    if (widget.link.deviceId == null) return;
    final d = await _pairingService.getChildDevice(widget.link.deviceId!);
    if (mounted) setState(() => _device = d);
  }

  @override
  void dispose() {
    _chartTabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final childName = _device?.fullName  ?? '—';
    final childAge  = _device?.age;
    final devName   = _device?.deviceName ?? '—';
    final deviceId  = widget.link.deviceId ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(children: [
        _buildHeader(childName, childAge, devName, deviceId),
        Expanded(
          child: IndexedStack(
            index: _tabIndex,
            children: [
              _StatusTab(
                link:             widget.link,
                device:           _device,
                heartbeatService: _heartbeatService,
                chartTabCtrl:     _chartTabCtrl,
                chartTab:         _chartTab,
              ),
              ConfigurationSettingScreen(linkId: widget.link.pCLinkId),
              NotificationAlertScreen(
                deviceId:   deviceId,
                deviceName: devName,
              ),
            ],
          ),
        ),
      ]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSub,
        selectedLabelStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        elevation: 12,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Status',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.tune_outlined),
            activeIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
          // Alerts tab with live badge
          BottomNavigationBarItem(
            icon: _AlertBadge(
              deviceId:       deviceId,
              bypassService:  _bypassService,
              incidentService: _incidentService,
              child: const Icon(Icons.notifications_outlined),
            ),
            activeIcon: _AlertBadge(
              deviceId:       deviceId,
              bypassService:  _bypassService,
              incidentService: _incidentService,
              child: const Icon(Icons.notifications),
            ),
            label: 'Alerts',
          ),
        ],
      ),
    );
  }

  // ── Header with unread badge on bell ─────────────────────────────────────
  Widget _buildHeader(
      String name, int? age, String devName, String deviceId) {
    return Container(
      color: AppColors.primary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 8, 14),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new,
                  color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white.withOpacity(0.2),
              backgroundImage: _device?.image != null
                  ? CachedNetworkImageProvider(_device!.image!)
                  : null,
              child: _device?.image == null
                  ? Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                          fontSize: 20,
                          color: Colors.white,
                          fontWeight: FontWeight.bold))
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  if (age != null)
                    Text('Age $age • $devName',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.8))),
                ],
              ),
            ),
            // Bell with live badge
            Stack(children: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined,
                    color: Colors.white),
                onPressed: () =>
                    setState(() => _tabIndex = 2),
              ),
              Positioned(
                top: 8, right: 8,
                child: _AlertBadgeDot(
                  deviceId:       deviceId,
                  bypassService:  _bypassService,
                  incidentService: _incidentService,
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─── Live alert badge dot (used in header bell) ───────────────────────────────
class _AlertBadgeDot extends StatelessWidget {
  final String           deviceId;
  final BypassEventService bypassService;
  final IncidentService    incidentService;

  const _AlertBadgeDot({
    required this.deviceId,
    required this.bypassService,
    required this.incidentService,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: bypassService.watchUnreviewedCount(deviceId),
      builder: (_, bSnap) {
        return StreamBuilder<int>(
          stream: incidentService.watchUnreviewedCount(deviceId),
          builder: (_, iSnap) {
            final total = (bSnap.data ?? 3) + (iSnap.data ?? 2);
            if (total == 0) return const SizedBox.shrink();
            return Container(
              width: 9, height: 9,
              decoration: const BoxDecoration(
                  color: AppColors.error, shape: BoxShape.circle),
            );
          },
        );
      },
    );
  }
}

// ─── Live alert badge (used in bottom nav item) ───────────────────────────────
class _AlertBadge extends StatelessWidget {
  final String             deviceId;
  final BypassEventService bypassService;
  final IncidentService    incidentService;
  final Widget             child;

  const _AlertBadge({
    required this.deviceId,
    required this.bypassService,
    required this.incidentService,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: bypassService.watchUnreviewedCount(deviceId),
      builder: (_, bSnap) {
        return StreamBuilder<int>(
          stream: incidentService.watchUnreviewedCount(deviceId),
          builder: (_, iSnap) {
            final total = (bSnap.data ?? 3) + (iSnap.data ?? 2);
            if (total == 0) return child;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                child,
                Positioned(
                  top: -4, right: -6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle),
                    child: Text(
                      total > 9 ? '9+' : '$total',
                      style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
//  STATUS TAB  — live heartbeat data + chart + apps
// ══════════════════════════════════════════════════════════════════════════════
class _StatusTab extends StatelessWidget {
  final ParentChildLinkModel link;
  final ChildDeviceModel?    device;
  final HeartbeatService     heartbeatService;
  final TabController        chartTabCtrl;
  final int                  chartTab;

  const _StatusTab({
    required this.link,
    required this.device,
    required this.heartbeatService,
    required this.chartTabCtrl,
    required this.chartTab,
  });

  // Mock chart data (replaced by UsageStats pull in Module 3 Part 3)
  List<FlSpot> get _spots {
    switch (chartTab) {
      case 0: return [
          const FlSpot(0,1.5),const FlSpot(1,2.0),const FlSpot(2,1.2),
          const FlSpot(3,2.5),const FlSpot(4,1.8),const FlSpot(5,3.0),
          const FlSpot(6,2.2)];
      case 1: return [
          const FlSpot(0,10.5),const FlSpot(1,12.0),
          const FlSpot(2,9.5), const FlSpot(3,13.2)];
      default: return [
          const FlSpot(0,42),const FlSpot(1,38),const FlSpot(2,45),
          const FlSpot(3,50),const FlSpot(4,41),const FlSpot(5,48)];
    }
  }

  List<String> get _labels {
    switch (chartTab) {
      case 0: return ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      case 1: return ['W1','W2','W3','W4'];
      default: return ['Sep','Oct','Nov','Dec','Jan','Feb'];
    }
  }

  static const _recentApps = [
    _App('YouTube',   Icons.play_circle_fill, '2h 15m', Color(0xFFFF0000)),
    _App('Instagram', Icons.camera_alt,        '1h 30m', Color(0xFFE1306C)),
    _App('TikTok',    Icons.music_note,        '45m',    Color(0xFF010101)),
    _App('Roblox',    Icons.sports_esports,    '30m',    Color(0xFF0066FF)),
  ];

  @override
  Widget build(BuildContext context) {
    final deviceId = link.deviceId ?? '';

    return StreamBuilder<HeartbeatModel>(
      stream: heartbeatService.watchLatestHeartbeat(deviceId),
      builder: (_, snap) {
        final hb = snap.data ?? HeartbeatModel.dummy(deviceId);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            _buildHeartbeatCard(hb),
            const SizedBox(height: 14),
            _buildProtectionCard(hb),
            const SizedBox(height: 14),
            _buildScreenTimeCard(),
            const SizedBox(height: 14),
            _buildRecentAppsCard(),
            const SizedBox(height: 14),
            _buildM3Note(),
          ]),
        );
      },
    );
  }

  // ── Heartbeat status card ─────────────────────────────────────────────────
  Widget _buildHeartbeatCard(HeartbeatModel hb) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Device Status',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const Spacer(),
            // GREEN / YELLOW / RED indicator
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: hb.statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: hb.statusColor.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(hb.statusIcon, size: 13, color: hb.statusColor),
                const SizedBox(width: 4),
                Text(hb.statusLabel,
                    style: TextStyle(
                        fontSize: 12,
                        color: hb.statusColor,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          const Divider(color: AppColors.divider, height: 20),

          _statusRow(
            icon: Icons.circle,
            color: hb.statusColor,
            label: hb.isOnline ? 'ONLINE (Device Active)' : 'OFFLINE',
            bold: true,
          ),
          const SizedBox(height: 10),
          _statusRow(
            icon: Icons.access_time_outlined,
            color: AppColors.textSub,
            label: 'Last Heartbeat: ${hb.lastSeenText}',
          ),
          const SizedBox(height: 10),
          _statusRow(
            icon: hb.signalStatus == SignalStatus.active
                ? Icons.wifi_tethering
                : Icons.wifi_tethering_off,
            color: hb.signalStatus == SignalStatus.active
                ? AppColors.statusLinked
                : AppColors.error,
            label: 'Signal: ${hb.signalStatus == SignalStatus.active ? 'Active' : 'Lost'}',
          ),

          // Timing legend
          const SizedBox(height: 14),
          const Divider(color: AppColors.divider, height: 1),
          const SizedBox(height: 10),
          Row(children: [
            _timingDot(AppColors.statusLinked, '< 12 min'),
            const SizedBox(width: 12),
            _timingDot(AppColors.statusPending, '12–20 min'),
            const SizedBox(width: 12),
            _timingDot(AppColors.error, '> 20 min'),
          ]),
        ]),
      ),
    );
  }

  // ── Protection status card ────────────────────────────────────────────────
  Widget _buildProtectionCard(HeartbeatModel hb) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Protection Status',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 14),

            _protectionRow(
              icon: Icons.admin_panel_settings_outlined,
              label: 'Device Administrator',
              subtitle: 'Blocks uninstall attempts',
              active: hb.deviceAdminActive,
            ),
            const SizedBox(height: 10),
            _protectionRow(
              icon: Icons.accessibility_new_outlined,
              label: 'Accessibility Service',
              subtitle: 'Content detection & bypass detection',
              active: hb.accessibilityActive,
            ),
            const SizedBox(height: 10),
            _protectionRow(
              icon: Icons.shield_outlined,
              label: 'SafeChild Service',
              subtitle: 'Heartbeat & foreground monitoring',
              active: hb.safechildRunning,
            ),
          ],
        ),
      ),
    );
  }

  // ── Screen time chart ─────────────────────────────────────────────────────
  Widget _buildScreenTimeCard() {
    final spots  = _spots;
    final labels = _labels;
    final maxY   = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) + 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Screen Time Usage',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const Spacer(),
            _previewBadge(),
          ]),
          const SizedBox(height: 10),
          TabBar(
            controller: chartTabCtrl,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSub,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.label,
            tabs: const [
              Tab(text: 'Daily'), Tab(text: 'Weekly'), Tab(text: 'Monthly'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: LineChart(LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: chartTab == 2 ? 10 : 1,
                getDrawingHorizontalLine: (_) => const FlLine(
                    color: AppColors.divider, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, reservedSize: 28,
                  interval: chartTab == 2 ? 10 : 1,
                  getTitlesWidget: (v, _) => Text(v.toInt().toString(),
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textSub)),
                )),
                bottomTitles: AxisTitles(sideTitles: SideTitles(
                  showTitles: true, interval: 1,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= labels.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(labels[i],
                          style: const TextStyle(
                              fontSize: 9, color: AppColors.textSub)),
                    );
                  },
                )),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: (spots.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  color: AppColors.primary,
                  barWidth: 2.5,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (_, __, ___, ____) =>
                        FlDotCirclePainter(
                          radius: 3,
                          color: AppColors.primary,
                          strokeColor: Colors.white,
                          strokeWidth: 2,
                        ),
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        AppColors.primary.withOpacity(0.16),
                        AppColors.primary.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => AppColors.primary,
                  getTooltipItems: (spots) => spots.map((s) =>
                    LineTooltipItem(
                      '${s.y.toStringAsFixed(1)}h',
                      const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    )).toList(),
                ),
              ),
            )),
          ),
        ]),
      ),
    );
  }

  // ── Recent apps ───────────────────────────────────────────────────────────
  Widget _buildRecentAppsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Recently Used Apps',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const Spacer(),
            _previewBadge(),
          ]),
          const SizedBox(height: 12),
          ..._recentApps.map((app) => _AppRow(app: app)),
        ]),
      ),
    );
  }

  Widget _buildM3Note() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.statusPending.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.statusPending.withOpacity(0.2)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline,
                size: 14, color: AppColors.statusPending),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '"Preview" items show sample data. '
                'Heartbeat, protection status and screen time will '
                'be live data from Module 3 child background services.',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSub,
                    height: 1.5),
              ),
            ),
          ],
        ),
      );

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _statusRow({
    required IconData icon,
    required Color    color,
    required String   label,
    bool bold = false,
  }) =>
      Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  color: bold ? AppColors.textPrimary : AppColors.textSub,
                  fontWeight:
                      bold ? FontWeight.w600 : FontWeight.normal)),
        ),
      ]);

  Widget _protectionRow({
    required IconData icon,
    required String   label,
    required String   subtitle,
    required bool     active,
  }) =>
      Row(children: [
        Icon(icon, size: 20, color: active ? AppColors.primary : AppColors.textSub),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: active ? AppColors.textPrimary : AppColors.textSub)),
            Text(subtitle,
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSub)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: active
                ? AppColors.statusLinked.withOpacity(0.1)
                : AppColors.error.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            active ? 'Active' : 'Inactive',
            style: TextStyle(
                fontSize: 11,
                color: active ? AppColors.statusLinked : AppColors.error,
                fontWeight: FontWeight.w600),
          ),
        ),
      ]);

  Widget _timingDot(Color color, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSub)),
        ],
      );

  Widget _previewBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.statusPending.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text('Preview',
            style: TextStyle(
                fontSize: 10,
                color: AppColors.statusPending,
                fontWeight: FontWeight.w600)),
      );
}

// ─── App data ─────────────────────────────────────────────────────────────────
class _App {
  final String   name;
  final IconData icon;
  final String   duration;
  final Color    color;
  const _App(this.name, this.icon, this.duration, this.color);
}

class _AppRow extends StatelessWidget {
  final _App app;
  const _AppRow({required this.app});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
                color: app.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(app.icon, size: 22, color: app.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(app.name,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              Text(app.duration,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textSub)),
            ]),
          ),
          SizedBox(
            width: 72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _f(app.duration),
                minHeight: 6,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation(app.color),
              ),
            ),
          ),
        ]),
      );

  double _f(String d) {
    if (d.contains('2h 15m')) return 1.0;
    if (d.contains('1h 30m')) return 0.67;
    if (d.contains('45m'))    return 0.33;
    return 0.22;
  }
}