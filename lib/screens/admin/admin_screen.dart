// lib/screens/admin/admin_screen.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/admin_service.dart';
import '../../utils/app_theme.dart';
import '../auth/login_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Admin Dashboard (2-tab: System Status | User Accounts)
// ═════════════════════════════════════════════════════════════════════════════
class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  final _service = AdminService();
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('role');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context,
        MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Row(children: [
          Icon(Icons.admin_panel_settings, size: 20),
          SizedBox(width: 8),
          Text('Admin Dashboard',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        ]),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle:
              const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.monitor_heart_outlined, size: 18),
                text: 'System Status'),
            Tab(icon: Icon(Icons.manage_accounts_outlined, size: 18),
                text: 'User Accounts'),
          ],
        ),
        actions: [
          IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: _logout),
        ],
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _SystemStatusTab(service: _service),
          _UserAccountsTab(service: _service),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 1 — System Status Monitoring
// ═════════════════════════════════════════════════════════════════════════════
class _SystemStatusTab extends StatefulWidget {
  final AdminService service;
  const _SystemStatusTab({required this.service});
  @override
  State<_SystemStatusTab> createState() => _SystemStatusTabState();
}

class _SystemStatusTabState extends State<_SystemStatusTab> {
  Map<String, dynamic>? _stats;
  int?    _latencyMs;
  String? _geminiStatus;
  List<Map<String, dynamic>> _traffic = [];
  bool    _loading = true;
  Timer?  _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.service.getSystemStats(),
      widget.service.checkFirebaseLatency(),
      widget.service.checkGeminiApiStatus(),
      widget.service.getWeeklyTraffic(),
    ]);
    if (!mounted) return;
    setState(() {
      _stats        = results[0] as Map<String, dynamic>;
      _latencyMs    = results[1] as int;
      _geminiStatus = results[2] as String;
      _traffic      = results[3] as List<Map<String, dynamic>>;
      _loading      = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Header row ─────────────────────────────────────────────────────
          Row(children: [
            const Expanded(
              child: Text('Platform Health',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
            ),
            Text(
              'Last refresh: ${DateFormat('HH:mm:ss').format(DateTime.now())}',
              style: const TextStyle(fontSize: 10, color: AppColors.textSub),
            ),
            const SizedBox(width: 4),
            if (_loading)
              const SizedBox(
                  width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              GestureDetector(
                onTap: _load,
                child: const Icon(Icons.refresh,
                    size: 16, color: AppColors.primary),
              ),
          ]),
          const SizedBox(height: 12),

          // ── 4 Metric Cards ─────────────────────────────────────────────────
          Row(children: [
            Expanded(child: _MetricCard(
              icon:  Icons.people_outlined,
              label: 'Active Parents',
              value: _stats == null ? '—' : '${_stats!['total_parents']}',
              color: const Color(0xFF1565C0),
            )),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(
              icon:  Icons.cloud_done_outlined,
              label: 'Firebase',
              value: _latencyMs == null
                  ? '…'
                  : _latencyMs! >= 0
                      ? '${_latencyMs}ms'
                      : 'Down',
              color: _latencyMs == null
                  ? AppColors.textSub
                  : _latencyMs! >= 0
                      ? const Color(0xFF2E7D32)
                      : AppColors.error,
              subtitle: _latencyMs != null && _latencyMs! >= 0
                  ? 'Operational' : 'Unreachable',
            )),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _MetricCard(
              icon:  Icons.warning_amber_outlined,
              label: 'Alerts Today',
              value: _stats == null ? '—' : '${_stats!['alerts_today']}',
              color: (_stats?['alerts_today'] ?? 0) > 0
                  ? Colors.orange : const Color(0xFF2E7D32),
              subtitle: 'Incidents + Bypasses',
            )),
            const SizedBox(width: 10),
            Expanded(child: _MetricCard(
              icon:  Icons.auto_awesome_outlined,
              label: 'Gemini API',
              value: _geminiStatus == null
                  ? '…'
                  : _geminiStatus == 'operational'
                      ? 'Online'
                      : _geminiStatus == 'degraded'
                          ? 'Degraded' : 'Offline',
              color: _geminiStatus == 'operational'
                  ? const Color(0xFF2E7D32)
                  : _geminiStatus == 'degraded'
                      ? Colors.orange : AppColors.error,
              subtitle: 'Content Detection',
            )),
          ]),

          const SizedBox(height: 18),

          // ── 7-Day Traffic Graph ─────────────────────────────────────────────
          _AdminCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.stacked_bar_chart,
                    color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text('System Activity — Last 7 Days',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary)),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                _LegendDot(color: AppColors.primary, label: 'Incidents'),
                const SizedBox(width: 14),
                _LegendDot(color: Colors.orange, label: 'Bypass Events'),
              ]),
              const SizedBox(height: 14),
              _traffic.isEmpty
                ? const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()))
                : SizedBox(
                    height: 180,
                    child: _TrafficBarChart(traffic: _traffic),
                  ),
            ]),
          ),

          const SizedBox(height: 14),

          // ── Connection Details ──────────────────────────────────────────────
          _AdminCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.hub_outlined,
                    color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text('Connection Details',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary)),
              ]),
              const Divider(height: 18),
              _InfoRow(
                icon: Icons.storage_outlined,
                label: 'Firestore Database',
                value: _latencyMs != null && _latencyMs! >= 0
                    ? 'Connected' : 'Unreachable',
                color: _latencyMs != null && _latencyMs! >= 0
                    ? const Color(0xFF2E7D32) : AppColors.error,
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.lock_outline,
                label: 'Firebase Auth',
                value: FirebaseAuth.instance.currentUser != null
                    ? 'Active Session' : 'No Session',
                color: FirebaseAuth.instance.currentUser != null
                    ? const Color(0xFF2E7D32) : AppColors.textSub,
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.auto_awesome_outlined,
                label: 'Gemini API',
                value: _geminiStatus == null ? 'Checking…'
                    : _geminiStatus == 'operational' ? 'Operational'
                    : _geminiStatus == 'degraded'    ? 'Degraded'
                    : 'Unreachable',
                color: _geminiStatus == 'operational'
                    ? const Color(0xFF2E7D32)
                    : _geminiStatus == 'degraded'
                        ? Colors.orange : AppColors.error,
              ),
              const SizedBox(height: 8),
              _InfoRow(
                icon: Icons.link_outlined,
                label: 'Active Parent-Child Links',
                value: _stats == null ? '…' : '${_stats!['active_links']}',
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Tab 2 — User Account Management
// ═════════════════════════════════════════════════════════════════════════════
class _UserAccountsTab extends StatefulWidget {
  final AdminService service;
  const _UserAccountsTab({required this.service});
  @override
  State<_UserAccountsTab> createState() => _UserAccountsTabState();
}

class _UserAccountsTabState extends State<_UserAccountsTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // ── Search Bar ──────────────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: TextField(
          controller: _searchCtrl,
          decoration: InputDecoration(
            hintText: 'Search by name or email…',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: _query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () => _searchCtrl.clear())
                : null,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12)),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ),

      // ── List ────────────────────────────────────────────────────────────────
      Expanded(
        child: StreamBuilder<List<Map<String, dynamic>>>(
          stream: widget.service.watchParentsWithDevices(),
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snap.data ?? [];
            final filtered = _query.isEmpty
                ? all
                : all.where((p) {
                    final name  = (p['full_name'] as String? ?? '').toLowerCase();
                    final email = (p['email']     as String? ?? '').toLowerCase();
                    return name.contains(_query) || email.contains(_query);
                  }).toList();

            if (filtered.isEmpty) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people_outline,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(_query.isEmpty
                      ? 'No parent accounts found.'
                      : 'No results for "$_query"',
                      style: const TextStyle(color: AppColors.textSub)),
                ]),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              children: [
                Text('${filtered.length} account(s)',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSub,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 10),
                ...filtered.map((p) => _ParentCard(
                      parentData: p,
                      service:    widget.service,
                    )),
              ],
            );
          },
        ),
      ),
    ]);
  }
}

// ── Parent Card ───────────────────────────────────────────────────────────────
class _ParentCard extends StatelessWidget {
  final Map<String, dynamic> parentData;
  final AdminService         service;
  const _ParentCard({required this.parentData, required this.service});

  String _formatDate(dynamic ts) {
    if (ts == null) return 'Unknown';
    try {
      final dt = (ts as Timestamp).toDate();
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return '—';
    }
  }

  Future<void> _doAction(
      BuildContext ctx, String action, String parentId, String name) async {
    String title, body, btnLabel;
    Color  btnColor;

    switch (action) {
      case 'suspend':
        title    = 'Suspend Account';
        body     = 'Suspend "$name"? They will not be able to log in until reactivated.';
        btnLabel = 'Suspend';
        btnColor = Colors.orange;
        break;
      case 'activate':
        title    = 'Activate Account';
        body     = 'Reactivate "$name"? They will regain full access.';
        btnLabel = 'Activate';
        btnColor = const Color(0xFF2E7D32);
        break;
      default: // delete
        title    = 'Delete Account';
        body     = 'Permanently delete "$name"? This removes all data and linked devices. This cannot be undone.';
        btnLabel = 'Delete';
        btnColor = AppColors.error;
    }

    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(body, style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: btnColor),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(btnLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !ctx.mounted) return;

    try {
      if (action == 'suspend')  await service.suspendParent(parentId);
      if (action == 'activate') await service.activateParent(parentId);
      if (action == 'delete')   await service.deleteParentAccount(parentId);

      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('$title completed for $name.'),
        backgroundColor: btnColor,
      ));
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
        content: Text('Error: $e'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final id      = parentData['id']     as String;
    final name    = parentData['full_name'] as String? ?? 'Unknown';
    final email   = parentData['email']    as String? ?? '—';
    final status  = parentData['account_status'] as String? ?? 'active';
    final devices = parentData['device_count']   as int? ?? 0;
    final regDate = _formatDate(parentData['created_at']);

    final isSuspended = status == 'suspended';
    final statusColor = isSuspended ? Colors.orange : const Color(0xFF2E7D32);
    final statusLabel = isSuspended ? 'Suspended' : 'Active';

    return Card(
      margin:    const EdgeInsets.only(bottom: 10),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Top row: avatar + info + status badge ────────────────────────
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                      fontSize: 17),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(email,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSub)),
              ]),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: statusColor.withOpacity(0.4)),
              ),
              child: Text(statusLabel,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: statusColor)),
            ),
          ]),

          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // ── Detail row ───────────────────────────────────────────────────
          Row(children: [
            _SmallInfoChip(
                icon: Icons.calendar_today_outlined,
                label: 'Joined: $regDate'),
            const SizedBox(width: 10),
            _SmallInfoChip(
                icon: Icons.phone_android_outlined,
                label: '$devices device(s) linked'),
          ]),

          const SizedBox(height: 12),

          // ── Action buttons ────────────────────────────────────────────────
          Row(children: [
            if (isSuspended)
              Expanded(
                child: _ActionBtn(
                  label: 'Activate',
                  icon:  Icons.check_circle_outline,
                  color: const Color(0xFF2E7D32),
                  onTap: () => _doAction(context, 'activate', id, name),
                ),
              )
            else
              Expanded(
                child: _ActionBtn(
                  label: 'Suspend',
                  icon:  Icons.pause_circle_outline,
                  color: Colors.orange,
                  onTap: () => _doAction(context, 'suspend', id, name),
                ),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: _ActionBtn(
                label: 'Delete',
                icon:  Icons.delete_outline,
                color: AppColors.error,
                onTap: () => _doAction(context, 'delete', id, name),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Traffic Bar Chart
// ═════════════════════════════════════════════════════════════════════════════
class _TrafficBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> traffic;
  const _TrafficBarChart({required this.traffic});

  @override
  Widget build(BuildContext context) {
    final maxY = traffic.fold<double>(1.0, (m, d) {
      final total =
          ((d['incidents'] as int) + (d['bypass'] as int)).toDouble();
      return total > m ? total : m;
    });

    return BarChart(
      BarChartData(
        maxY: maxY * 1.3,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, gi, rod, ri) {
              final d = traffic[group.x];
              return BarTooltipItem(
                '${d['date']}\nInc: ${d['incidents']}  Byp: ${d['bypass']}',
                const TextStyle(color: Colors.white, fontSize: 10),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i >= traffic.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(traffic[i]['date'] as String,
                      style: const TextStyle(
                          fontSize: 9, color: AppColors.textSub)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 9, color: AppColors.textSub),
              ),
            ),
          ),
          topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData:   const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(traffic.length, (i) {
          final d = traffic[i];
          return BarChartGroupData(x: i, barRods: [
            BarChartRodData(
              toY:   (d['incidents'] as int).toDouble(),
              color: AppColors.primary,
              width: 10,
              borderRadius: BorderRadius.circular(3),
            ),
            BarChartRodData(
              toY:   (d['bypass'] as int).toDouble(),
              color: Colors.orange,
              width: 10,
              borderRadius: BorderRadius.circular(3),
            ),
          ]);
        }),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared Widgets
// ═════════════════════════════════════════════════════════════════════════════
class _AdminCard extends StatelessWidget {
  final Widget child;
  const _AdminCard({required this.child});
  @override
  Widget build(BuildContext context) => Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(padding: const EdgeInsets.all(16), child: child),
      );
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;
  final String?  subtitle;
  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) => Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textSub)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color)),
            if (subtitle != null)
              Text(subtitle!,
                  style: const TextStyle(
                      fontSize: 10, color: AppColors.textSub)),
          ]),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color?   color;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 15, color: AppColors.textSub),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSub)),
        ),
        Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: color ?? AppColors.textPrimary)),
      ]);
}

class _LegendDot extends StatelessWidget {
  final Color  color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) => Row(children: [
        Container(
            width: 10, height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
      ]);
}

class _SmallInfoChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  const _SmallInfoChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textSub),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSub)),
        ],
      );
}

class _ActionBtn extends StatelessWidget {
  final String   label;
  final IconData icon;
  final Color    color;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon:  Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withOpacity(0.5)),
          padding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
}