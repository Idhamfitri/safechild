// lib/screens/parent/notification_alert_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Displays real-time alerts from TWO Firestore collections:
//   1. bypass_events   → written by Module 3 anti-bypass detection
//   2. incidents       → written by Module 2 content detection
//
// Uses Firestore Snapshot Listeners (MODULE3_WORKFLOW Part 3) so the list
// updates instantly when a new event is written on the child device.
//
// Dummy data is shown automatically if no real documents exist yet.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/bypass_event_model.dart';
import '../../models/incident_model.dart';
import '../../services/bypass_event_service.dart';
import '../../services/incident_service.dart';
import '../../utils/app_theme.dart';

// Unified display item merging bypass + incident
class _AlertEntry {
  final String    id;
  final String    title;
  final String    subtitle;
  final IconData  icon;
  final Color     color;
  final DateTime  timestamp;
  final bool      isRead;
  final bool      isBlocked;       // bypass: was it blocked? incident: n/a
  final double?   confidenceScore; // only for incidents
  final _AlertKind kind;

  const _AlertEntry({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.timestamp,
    required this.isRead,
    required this.isBlocked,
    this.confidenceScore,
    required this.kind,
  });
}

enum _AlertKind { bypass, incident }

class NotificationAlertScreen extends StatefulWidget {
  final String deviceId;
  final String deviceName;

  const NotificationAlertScreen({
    super.key,
    required this.deviceId,
    required this.deviceName,
  });

  @override
  State<NotificationAlertScreen> createState() =>
      _NotificationAlertScreenState();
}

class _NotificationAlertScreenState
    extends State<NotificationAlertScreen> {
  final _bypassService  = BypassEventService();
  final _incidentService = IncidentService();

  bool _showWeekly    = false;
  bool _showBypass    = true;   // filter toggles
  bool _showIncidents = true;

  // ── Mark reviewed ─────────────────────────────────────────────────────────
  Future<void> _markRead(_AlertEntry entry) async {
    if (entry.kind == _AlertKind.bypass) {
      await _bypassService.markReviewed(entry.id);
    } else {
      await _incidentService.markReviewed(entry.id);
    }
  }

  Future<void> _markAllRead(List<_AlertEntry> entries) async {
    for (final e in entries.where((e) => !e.isRead)) {
      await _markRead(e);
    }
  }

  // ── Merge & filter entries ────────────────────────────────────────────────
  List<_AlertEntry> _merge(
    List<BypassEventModel> bypasses,
    List<IncidentModel>    incidents,
  ) {
    final now    = DateTime.now();
    final cutoff = _showWeekly
        ? now.subtract(const Duration(days: 7))
        : DateTime(now.year, now.month, now.day);

    final entries = <_AlertEntry>[];

    if (_showBypass) {
      for (final b in bypasses) {
        if (b.detectedAt.isBefore(cutoff)) continue;
        entries.add(_AlertEntry(
          id:        b.bypassId,
          title:     b.eventType.displayLabel,
          subtitle:  b.eventDescription,
          icon:      b.eventType.icon,
          color:     b.eventType.color,
          timestamp: b.detectedAt,
          isRead:    b.isReviewed,
          isBlocked: b.isBlocked,
          kind:      _AlertKind.bypass,
        ));
      }
    }

    if (_showIncidents) {
      for (final i in incidents) {
        if (i.detectedAt.isBefore(cutoff)) continue;
        entries.add(_AlertEntry(
          id:              i.incidentId,
          title:           '${i.category.displayLabel} Detected',
          subtitle:        i.textSummary,
          icon:            i.category.icon,
          color:           i.category.color,
          timestamp:       i.detectedAt,
          isRead:          i.isReviewed,
          isBlocked:       false,
          confidenceScore: i.confidenceScore,
          kind:            _AlertKind.incident,
        ));
      }
    }

    entries.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BypassEventModel>>(
      stream: _bypassService.watchBypassEvents(widget.deviceId),
      builder: (_, bypassSnap) {
        return StreamBuilder<List<IncidentModel>>(
          stream: _incidentService.watchIncidents(widget.deviceId),
          builder: (_, incidentSnap) {
            // Use real data if available, dummy data if empty
            final bypasses = (bypassSnap.data?.isNotEmpty ?? false)
                ? bypassSnap.data!
                : BypassEventModel.dummies(widget.deviceId);

            final incidents = (incidentSnap.data?.isNotEmpty ?? false)
                ? incidentSnap.data!
                : IncidentModel.dummies(widget.deviceId);

            final bool usingDummy = (bypassSnap.data?.isEmpty ?? true) ||
                (incidentSnap.data?.isEmpty ?? true);

            final entries  = _merge(bypasses, incidents);
            final unread   = entries.where((e) => !e.isRead).length;

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ──────────────────────────────────────────
                  _buildHeader(entries, unread),
                  const SizedBox(height: 12),

                  // ── Filter chips ─────────────────────────────────────
                  _buildFilterRow(),
                  const SizedBox(height: 14),

                  // ── Alert list ───────────────────────────────────────
                  if (entries.isEmpty)
                    _buildEmptyState()
                  else
                    _buildAlertList(entries),

                  // ── Dummy data note ──────────────────────────────────
                  if (usingDummy) ...[
                    const SizedBox(height: 16),
                    _buildDummyNote(),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(List<_AlertEntry> entries, int unread) {
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Alert Centre',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$unread new',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ]),
          Text(
            _showWeekly ? 'This Week' : 'Today',
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSub),
          ),
        ]),
      ),

      // Toggle daily/weekly
      TextButton(
        style: TextButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: () => setState(() => _showWeekly = !_showWeekly),
        child: Text(
          _showWeekly ? "Today's Alerts" : 'Weekly Alerts',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    ]);
  }

  // ── Filter chips ──────────────────────────────────────────────────────────
  Widget _buildFilterRow() {
    return Row(children: [
      _FilterChip(
        label: 'Bypass',
        icon: Icons.gpp_bad_outlined,
        active: _showBypass,
        color: AppColors.error,
        onTap: () => setState(() => _showBypass = !_showBypass),
      ),
      const SizedBox(width: 8),
      _FilterChip(
        label: 'Content',
        icon: Icons.warning_amber_outlined,
        active: _showIncidents,
        color: const Color(0xFFE65100),
        onTap: () => setState(() => _showIncidents = !_showIncidents),
      ),
    ]);
  }

  // ── Alert list ────────────────────────────────────────────────────────────
  Widget _buildAlertList(List<_AlertEntry> entries) {
    final unread = entries.where((e) => !e.isRead).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mark all read button
        if (unread.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _markAllRead(entries),
              icon: const Icon(Icons.done_all,
                  size: 14, color: AppColors.primary),
              label: const Text('Mark all read',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.primary)),
            ),
          ),

        ...entries.map((e) => _AlertTile(
              entry: e,
              onMarkRead: () => _markRead(e),
            )),
      ],
    );
  }

  Widget _buildEmptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.notifications_none_outlined,
                size: 56,
                color: AppColors.textSub.withOpacity(0.3)),
            const SizedBox(height: 12),
            const Text('No alerts',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSub)),
            const SizedBox(height: 4),
            Text(
              _showWeekly
                  ? 'No alerts this week.'
                  : 'No alerts today. Device is safe.',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSub),
            ),
          ]),
        ),
      );

  Widget _buildDummyNote() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.statusPending.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: AppColors.statusPending.withOpacity(0.25)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.construction_outlined,
                size: 14, color: AppColors.statusPending),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Sample alerts shown. Real alerts will be written by '
                'Module 2 (Content Detection) and Module 3 (Anti-Bypass) '
                'from the child device background services.',
                style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSub,
                    height: 1.5),
              ),
            ),
          ],
        ),
      );
}

// ─── Filter chip ──────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String   label;
  final IconData icon;
  final bool     active;
  final Color    color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(
              horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.12) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? color : AppColors.divider,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: active ? color : AppColors.textSub),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: active ? color : AppColors.textSub,
                    fontWeight: active
                        ? FontWeight.w600
                        : FontWeight.normal)),
          ]),
        ),
      );
}

// ─── Alert tile ───────────────────────────────────────────────────────────────
class _AlertTile extends StatelessWidget {
  final _AlertEntry  entry;
  final VoidCallback onMarkRead;

  const _AlertTile({required this.entry, required this.onMarkRead});

  @override
  Widget build(BuildContext context) {
    final timeStr = DateFormat('h:mm a').format(entry.timestamp);
    final dateStr = _isToday(entry.timestamp)
        ? timeStr
        : '${DateFormat('d MMM').format(entry.timestamp)}, $timeStr';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: entry.isRead
            ? Colors.white
            : entry.color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: entry.isRead
              ? AppColors.divider
              : entry.color.withOpacity(0.3),
          width: entry.isRead ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Icon
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: entry.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(entry.icon, size: 20, color: entry.color),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(entry.title,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: entry.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  // Unread dot
                  if (!entry.isRead)
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                          color: entry.color, shape: BoxShape.circle),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(entry.subtitle,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSub,
                        height: 1.4),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),

                // Bottom row: time + badges
                Row(children: [
                  Icon(Icons.access_time_outlined,
                      size: 11, color: AppColors.textSub),
                  const SizedBox(width: 4),
                  Text(dateStr,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSub)),
                  const SizedBox(width: 8),

                  // Blocked badge (bypass only)
                  if (entry.kind == _AlertKind.bypass)
                    _badge(
                      entry.isBlocked ? 'Blocked' : 'Not Blocked',
                      entry.isBlocked
                          ? AppColors.statusLinked
                          : AppColors.statusPending,
                    ),

                  // Confidence badge (incident only)
                  if (entry.confidenceScore != null)
                    _badge(
                      '${(entry.confidenceScore! * 100).toInt()}% confidence',
                      entry.confidenceScore! >= 0.75
                          ? AppColors.error
                          : AppColors.statusPending,
                    ),

                  const Spacer(),

                  // Mark read button
                  if (!entry.isRead)
                    GestureDetector(
                      onTap: onMarkRead,
                      child: const Text('Mark read',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.underline)),
                    ),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 7, vertical: 2),
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600)),
      );

  bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
  }
}