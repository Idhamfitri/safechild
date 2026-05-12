// lib/screens/parent/widgets/status_cards.dart

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/bypass_event_model.dart';
import '../../../models/heartbeat_model.dart';
import '../../../models/incident_model.dart';
import '../../../services/bypass_event_service.dart';
import '../../../services/incident_service.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/app_utils.dart';

// ── Shared Helper Methods ──────────────────────────────────────────────────

String _fmtMinutes(int m) {
  if (m == 0) return '0m';
  final h = m ~/ 60;
  final min = m % 60;
  if (h == 0) return '${min}m';
  if (min == 0) return '${h}h';
  return '${h}h ${min}m';
}

String _fmtMinutesShort(int m) {
  if (m <= 0) return '0';
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h';
}

// ── Section Title ─────────────────────────────────────────────────────────

class SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  const SectionTitle({super.key, required this.icon, required this.title});

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

// ── Detail Row ───────────────────────────────────────────────────────────

class DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const DetailRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text('$label:',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSub)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ── Info Row ────────────────────────────────────────────────────────────

class InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const InfoRow({
    super.key,
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

// ── Status Row ───────────────────────────────────────────────────────────

class StatusRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isOn;

  const StatusRow({
    super.key,
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

// ── Warning Banner ──────────────────────────────────────────────────────

class WarningBanner extends StatelessWidget {
  final String message;
  const WarningBanner({super.key, required this.message});

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

// ── Device Header Card ──────────────────────────────────────────────────

class DeviceHeaderCard extends StatelessWidget {
  final Map<String, dynamic>? deviceData;
  final HeartbeatModel hb;

  const DeviceHeaderCard({super.key, required this.deviceData, required this.hb});

  @override
  Widget build(BuildContext context) {
    final name         = deviceData?['full_name']       ?? '—';
    final deviceName   = deviceData?['device_name']     ?? '—';
    final manufacturer = deviceData?['manufacturer']    ?? '';
    final age          = deviceData?['age'];
    final androidVer   = deviceData?['android_version'] ?? '—';
    final dateCreated  = deviceData?['date_created'];
    final imageUrl     = deviceData?['image_url'] as String?;

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
                  ? const Icon(Icons.person, size: 36, color: AppColors.primary)
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
          InfoRow(
              icon:  Icons.phone_android_outlined,
              label: 'Device',
              value: manufacturer.isNotEmpty ? (manufacturer[0].toUpperCase() + manufacturer.substring(1).toLowerCase()) : '—'),
          const SizedBox(height: 8),
          InfoRow(
              icon:  Icons.smartphone_outlined,
              label: 'Device Name',
              value: deviceName),
          const SizedBox(height: 8),
          InfoRow(
              icon:  Icons.android_outlined,
              label: 'Android',
              value: 'Version $androidVer'),
          const SizedBox(height: 8),
          InfoRow(
              icon:  Icons.calendar_today_outlined,
              label: 'Registered',
              value: createdLabel),
        ]),
      ),
    );
  }
}

// ── Device Status Card ──────────────────────────────────────────────────

class DeviceStatusCard extends StatelessWidget {
  final HeartbeatModel hb;
  const DeviceStatusCard({super.key, required this.hb});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle(
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
        ]),
      ),
    );
  }
}

// ── Permission Card ─────────────────────────────────────────────────────

class PermissionCard extends StatelessWidget {
  final Map<String, dynamic>? deviceData;
  const PermissionCard({super.key, required this.deviceData});

  @override
  Widget build(BuildContext context) {
    final permMap            = deviceData?['permission_status'];
    final bool accessibility = permMap?['accessibility'] == true;
    final bool notifications = permMap?['notifications'] == true;
    final bool overlay       = permMap?['overlay']       == true;
    final bool usageAccess   = permMap?['usage_access']  == true;
    final bool deviceAdmin   = permMap?['device_admin']  == true;

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
          StatusRow(
              icon:  Icons.accessibility_new_outlined,
              label: 'Accessibility Service',
              isOn:  accessibility),
          const SizedBox(height: 10),
          StatusRow(
              icon:  Icons.notifications_outlined,
              label: 'Notifications',
              isOn:  notifications),
          const SizedBox(height: 10),
          StatusRow(
              icon:  Icons.picture_in_picture_alt_outlined,
              label: 'Display Over Apps',
              isOn:  overlay),
          const SizedBox(height: 10),
          StatusRow(
              icon:  Icons.bar_chart_outlined,
              label: 'Usage Access',
              isOn:  usageAccess),
          const SizedBox(height: 10),
          StatusRow(
              icon:  Icons.admin_panel_settings_outlined,
              label: 'Device Administrator',
              isOn:  deviceAdmin),
          if (!accessibility)
            const WarningBanner(
                message: 'Accessibility Service is OFF — ''AI content detection is not running.'),
          if (!deviceAdmin)
            const WarningBanner(
                message: 'Device Admin is OFF — ' 'app can be uninstalled by child.'),
        ]),
      ),
    );
  }
}

// ── Screen Time Section ─────────────────────────────────────────────────

class ScreenTimeSection extends StatefulWidget {
  final String deviceId;
  final TabController tabCtrl;
  final VoidCallback onManageTap;

  const ScreenTimeSection({
    super.key,
    required this.deviceId,
    required this.tabCtrl,
    required this.onManageTap,
  });

  @override
  State<ScreenTimeSection> createState() => _ScreenTimeSectionState();
}

class _ScreenTimeSectionState extends State<ScreenTimeSection> {

  Stream<List<Map<String, dynamic>>> _dailyStream(int count) {
    final now  = DateTime.now();
    final keys = List.generate(count, (i) {
      final d = now.subtract(Duration(days: count - 1 - i));
      return DateFormat('yyyy-MM-dd').format(d);
    });

    return FirebaseFirestore.instance
        .collection('screen_time')
        .doc(widget.deviceId)
        .collection('daily')
        .where(FieldPath.documentId, whereIn: keys)
        .snapshots()
        .map((snap) {
      final map = {for (var d in snap.docs) d.id: d.data()};
      return keys.map((k) => map[k] ?? {'date': k, 'total_minutes': 0, 'apps': []}).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionTitle(
                  icon: Icons.access_time_outlined, title: 'Screen Time Usage'),
              TextButton.icon(
                icon: const Icon(Icons.settings, size: 16),
                label: const Text('Manage'),
                onPressed: widget.onManageTap,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: widget.tabCtrl,
              indicator: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor:           Colors.white,
              unselectedLabelColor: AppColors.textSub,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              dividerColor: Colors.transparent,
              tabs: const [Tab(text: 'Daily'), Tab(text: 'Weekly')],
            ),
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: widget.tabCtrl,
            builder: (_, __) {
              if (widget.tabCtrl.index == 0) {
                return DailyChart(stream: _dailyStream(1));
              } else {
                return WeeklyChart(stream: _dailyStream(7));
              }
            },
          ),
        ]),
      ),
    );
  }
}

// ── Daily Chart ──────────────────────────────────────────────────────────

class DailyChart extends StatelessWidget {
  final Stream<List<Map<String, dynamic>>> stream;
  const DailyChart({super.key, required this.stream});

  Color _getBarColor(int minutes) {
    if (minutes <= 15) return const Color(0xFF2E7D32); // Green
    if (minutes <= 45) return Colors.orange;          // Orange
    return const Color(0xFFC62828);                   // Red
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        final today = snap.data?.isNotEmpty == true ? snap.data!.first : null;
        final totalMin = (today?['total_minutes'] as num?)?.toInt() ?? 0;
        final hourly   = (today?['hourly_totals'] as List<dynamic>? ?? List.filled(24, 0)).cast<int>();

        if (totalMin == 0) return _emptyChart('No usage data for today');

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Today\'s total: ${_fmtMinutes(totalMin)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
          const SizedBox(height: 24),
          SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: 60,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final hour = group.x.toInt();
                      final period = hour < 12 ? 'AM' : 'PM';
                      final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
                      return BarTooltipItem(
                        '$displayHour $period\n${rod.toY.toInt()} min',
                        const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (value, _) {
                        final hour = value.toInt();
                        String label = '';
                        if (hour == 0) label = '12AM';
                        else if (hour == 6) label = '6AM';
                        else if (hour == 12) label = '12PM';
                        else if (hour == 18) label = '6PM';
                        
                        if (label.isEmpty) return const SizedBox.shrink();
                        
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: AppColors.textSub)),
                        );
                      },
                      reservedSize: 24,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 15,
                      reservedSize: 28,
                      getTitlesWidget: (value, _) => Text(
                        value.toInt().toString(),
                        style: const TextStyle(fontSize: 9, color: AppColors.textSub),
                      ),
                    ),
                  ),
                  topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 15,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withOpacity(0.1),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(24, (i) {
                  final mins = hourly[i].toDouble().clamp(0.0, 60.0);
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: mins,
                        color: _getBarColor(mins.toInt()),
                        width: 8,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        backDrawRodData: BackgroundBarChartRodData(
                          show: true,
                          toY: 60,
                          color: Colors.grey.withOpacity(0.05),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _LegendItem(color: const Color(0xFF2E7D32), label: 'Low'),
              const SizedBox(width: 16),
              _LegendItem(color: Colors.orange, label: 'Med'),
              const SizedBox(width: 16),
              _LegendItem(color: const Color(0xFFC62828), label: 'High'),
            ],
          ),
        ]);
      },
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
    ]);
  }
}

// ── Weekly Chart ─────────────────────────────────────────────────────────

class WeeklyChart extends StatelessWidget {
  final Stream<List<Map<String, dynamic>>> stream;
  const WeeklyChart({super.key, required this.stream});

  static const _dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: stream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
        }
        
        final days = (snap.data ?? []).reversed.toList();
        final totalMin = days.fold<int>(0, (s, d) => s + ((d['total_minutes'] as num?)?.toInt() ?? 0));
        final maxDay   = days.fold<double>(1.0, (m, d) {
          final v = ((d['total_minutes'] as num?)?.toDouble() ?? 0);
          return v > m ? v : m;
        });

        if (totalMin == 0) return _emptyChart('No usage data for last 7 days');

        final spots = <FlSpot>[];
        for (int i = 0; i < days.length; i++) {
          final mins = ((days[i]['total_minutes'] as num?)?.toDouble() ?? 0);
          spots.add(FlSpot(i.toDouble(), mins));
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Weekly total: ${_fmtMinutes(totalMin)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                minX: 0, maxX: (days.length - 1).toDouble().clamp(1, 7),
                minY: 0, maxY: maxDay * 1.2,
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        final d = days[spot.x.toInt()];
                        final key  = d['date'] as String? ?? '';
                        return LineTooltipItem(
                          '$key\n${_fmtMinutes(spot.y.toInt())}',
                          const TextStyle(color: Colors.white, fontSize: 11),
                        );
                      }).toList();
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, _) {
                        final i = value.toInt();
                        if (i >= days.length || i < 0) return const SizedBox.shrink();
                        String label = '';
                        try {
                          final dt = DateTime.parse(days[i]['date'] as String);
                          label = _dayLabels[dt.weekday - 1];
                        } catch (_) {}
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
                        );
                      },
                      reservedSize: 28,
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      getTitlesWidget: (value, _) => Text(
                        _fmtMinutesShort(value.toInt()),
                        style: const TextStyle(fontSize: 9, color: AppColors.textSub),
                      ),
                    ),
                  ),
                  topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primary.withOpacity(0.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ]);
      },
    );
  }
}

// ── Recent Apps Section ─────────────────────────────────────────────────

class RecentAppsSection extends StatelessWidget {
  final String deviceId;
  const RecentAppsSection({super.key, required this.deviceId});

  Stream<List<Map<String, dynamic>>> _appsStream() {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return FirebaseFirestore.instance
        .collection('screen_time')
        .doc(deviceId)
        .collection('daily')
        .doc(today)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return <Map<String, dynamic>>[];
      final apps = (doc.data()?['apps'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
      final sorted = [...apps]..sort((a, b) =>
          (b['usage_minutes'] as num).compareTo(a['usage_minutes'] as num));
      return sorted.take(8).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionTitle(icon: Icons.apps_outlined, title: 'Recently Used Apps'),
          const SizedBox(height: 12),
          StreamBuilder<List<Map<String, dynamic>>>(
            stream: _appsStream(),
            builder: (_, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: Padding(padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator()));
              }
              final apps = snap.data ?? [];
              if (apps.isEmpty) {
                return Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.phone_android_outlined, size: 36, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    const Text('No app usage data today',
                        style: TextStyle(fontSize: 13, color: AppColors.textSub)),
                  ]),
                );
              }
              final maxMin = (apps.first['usage_minutes'] as num?)?.toDouble() ?? 1.0;
              return Column(
                children: apps.map((app) {
                  final name    = app['app_name'] as String? ??
                      AppUtils.getFriendlyAppName(app['package_name'] as String? ?? 'Unknown');
                  final iconB64 = app['icon_base64'] as String? ?? '';
                  final mins    = (app['usage_minutes'] as num?)?.toInt() ?? 0;
                  final fraction = maxMin > 0 ? (mins / maxMin) : 0.0;
                  
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(children: [
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: iconB64.isNotEmpty
                            ? Image.memory(
                                base64Decode(iconB64),
                                width: 34, height: 34, fit: BoxFit.cover,
                                errorBuilder: (_,__,___) => Center(
                                  child: Text(
                                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 15),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary, fontSize: 15),
                                ),
                              ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: Text(name,
                                  style: const TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Text(_fmtMinutes(mins),
                                style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                          ]),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: fraction,
                              backgroundColor: Colors.grey.shade200,
                              color: AppColors.primary,
                              minHeight: 6,
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  );
                }).toList(),
              );
            },
          ),
        ]),
      ),
    );
  }
}

// ── Alert Tile Widgets ───────────────────────────────────────────────────

class AlertsIncidentTile extends StatelessWidget {
  final IncidentModel incident;
  final IncidentService service;

  const AlertsIncidentTile({
    super.key,
    required this.incident,
    required this.service,
  });

  void _showDetailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(incident.category.icon,
              color: incident.category.color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(incident.category.displayLabel,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: incident.category.color)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detected text:',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSub)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: incident.category.color.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: incident.category.color.withOpacity(0.25)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.format_quote,
                      size: 14,
                      color: incident.category.color.withOpacity(0.6)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      incident.description.isNotEmpty
                          ? incident.description
                          : '(no raw text captured)',
                      style: TextStyle(
                          fontSize: 13,
                          color: incident.category.color,
                          fontStyle: FontStyle.italic,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            DetailRow(label: 'Source',
                value: AppUtils.getFriendlyAppName(incident.source)),
            DetailRow(
                label: 'Confidence',
                value: '${incident.confidenceLabel} '
                    '(${(incident.confidenceScore * 100).toInt()}%)'),
            DetailRow(
                label: 'Detected',
                value: DateFormat('dd MMM yyyy, HH:mm')
                    .format(incident.detectedAt)),
            DetailRow(
                label: 'Alert sent',
                value: incident.isAlertSend ? 'Yes' : 'No'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _resolve(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Resolve Incident',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        content: const Text(
            'Mark this incident as reviewed and remove it from the list?',
            style: TextStyle(color: AppColors.textSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await service.markReviewed(incident.incidentId);
      await service.deleteIncident(incident.incidentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: incident.category.color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(incident.category.icon,
              color: incident.category.color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(incident.textSummary,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 3),
            Row(children: [
              Text(
                DateFormat('dd MMM, HH:mm').format(incident.detectedAt),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSub),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: incident.category.color.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(incident.confidenceLabel,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: incident.category.color)),
              ),
              if (incident.isAlertSend) ...[
                const SizedBox(width: 6),
                const Icon(Icons.notifications_active,
                    color: Color(0xFFC62828), size: 12),
              ],
            ]),
          ]),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert,
              color: AppColors.textSub, size: 20),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          onSelected: (value) {
            if (value == 'detail') _showDetailDialog(context);
            if (value == 'resolve') _resolve(context);
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'detail',
              child: Row(children: [
                Icon(Icons.info_outline,
                    size: 16, color: incident.category.color),
                const SizedBox(width: 10),
                const Text('View Detail',
                    style: TextStyle(fontSize: 13)),
              ]),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'resolve',
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: Color(0xFF2E7D32)),
                const SizedBox(width: 10),
                const Text('Resolve',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFF2E7D32))),
              ]),
            ),
          ],
        ),
      ]),
    );
  }
}

class AlertsBypassTile extends StatelessWidget {
  final BypassEventModel event;
  final BypassEventService service;

  const AlertsBypassTile({
    super.key,
    required this.event,
    required this.service,
  });

  Future<void> _resolve(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text('Resolve Bypass Attempt',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        content: const Text(
            'Mark this bypass attempt as reviewed and remove it?',
            style: TextStyle(color: AppColors.textSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await service.markReviewed(event.bypassId);
      await service.deleteBypassEvent(event.bypassId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: event.eventType.color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(event.eventType.icon,
              color: event.eventType.color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(event.eventType.displayLabel,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 3),
            Row(children: [
              Text(
                DateFormat('dd MMM, HH:mm').format(event.detectedAt),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.textSub),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: event.isBlocked
                      ? const Color(0xFF2E7D32).withOpacity(0.10)
                      : const Color(0xFFC62828).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  event.isBlocked ? 'Blocked' : 'Not Blocked',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: event.isBlocked
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFFC62828)),
                ),
              ),
            ]),
          ]),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert,
              color: AppColors.textSub, size: 20),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          onSelected: (value) {
            if (value == 'resolve') _resolve(context);
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'resolve',
              child: Row(children: [
                const Icon(Icons.check_circle_outline,
                    size: 16, color: Color(0xFF2E7D32)),
                const SizedBox(width: 10),
                const Text('Resolve',
                    style: TextStyle(
                        fontSize: 13, color: Color(0xFF2E7D32))),
              ]),
            ),
          ],
        ),
      ]),
    );
  }
}

// ── Overview Tiles ────────────────────────────────────────────────────────

class IncidentTile extends StatelessWidget {
  final IncidentModel incident;
  const IncidentTile({super.key, required this.incident});

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

class BypassTile extends StatelessWidget {
  final BypassEventModel event;
  const BypassTile({super.key, required this.event});

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
            color: event.eventType.color.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(event.eventType.icon,
              color: event.eventType.color, size: 20),
        ),
        title: Text(event.eventType.displayLabel,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        subtitle: Text(
          DateFormat('dd MMM, HH:mm').format(event.detectedAt),
          style: const TextStyle(fontSize: 11, color: AppColors.textSub),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: event.isBlocked
                ? const Color(0xFF2E7D32).withOpacity(0.10)
                : const Color(0xFFC62828).withOpacity(0.10),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            event.isBlocked ? 'Blocked' : 'Not Blocked',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: event.isBlocked
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFC62828)),
          ),
        ),
      ),
    );
  }
}

// ── Empty Card Helper ───────────────────────────────────────────────────

Widget buildEmptyCard({
  required IconData icon,
  required String message,
  required String sub,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.divider),
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 40, color: const Color(0xFF2E7D32)),
      const SizedBox(height: 10),
      Text(message,
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary)),
      const SizedBox(height: 4),
      Text(sub,
          style: const TextStyle(
              fontSize: 12, color: AppColors.textSub)),
    ]),
  );
}

Widget _emptyChart(String message) => SizedBox(
  height: 120,
  child: Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.bar_chart_outlined, size: 40, color: Colors.grey.shade300),
      const SizedBox(height: 8),
      Text(message, style: const TextStyle(fontSize: 13, color: AppColors.textSub)),
    ]),
  ),
);
