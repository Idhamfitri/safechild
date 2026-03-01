// lib/screens/parent/configuration_setting_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// 6 toggle settings for one child device link.
// Core schema fields (offline_mode, notification_enabled) save to Firestore
// instantly via MonitoringSettingService.
// Extended fields also write to Firestore under the same doc (merged).
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../models/monitoring_setting_model.dart';
import '../../services/monitoring_setting_service.dart';
import '../../utils/app_theme.dart';

class ConfigurationSettingScreen extends StatefulWidget {
  final String linkId;
  const ConfigurationSettingScreen({super.key, required this.linkId});

  @override
  State<ConfigurationSettingScreen> createState() =>
      _ConfigurationSettingScreenState();
}

class _ConfigurationSettingScreenState
    extends State<ConfigurationSettingScreen> {
  final _service = MonitoringSettingService();

  Future<void> _toggle(String field, bool value) async {
    await _service.updateField(widget.linkId, field, value);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MonitoringSettingModel>(
      stream: _service.watchSettings(widget.linkId),
      builder: (ctx, snap) {
        final s = snap.data ??
            MonitoringSettingModel.defaults(widget.linkId);
        final loading =
            snap.connectionState == ConnectionState.waiting;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Section: Core Monitoring (schema fields) ────────────
              _sectionHeader('Monitoring',
                  Icons.monitor_heart_outlined, isCore: true),
              const SizedBox(height: 8),

              _ToggleCard(
                icon: Icons.pause_circle_outline,
                iconColor: const Color(0xFF1565C0),
                title: 'Offline Mode',
                subtitle: 'Pause all monitoring temporarily',
                tag: 'Core',
                value: s.offlineMode,
                onChanged: loading
                    ? null
                    : (v) => _toggle('offline_mode', v),
              ),

              _ToggleCard(
                icon: Icons.security_outlined,
                iconColor: AppColors.primary,
                title: 'Enable content monitoring',
                subtitle: 'Monitor all apps and browsing activity',
                value: s.contentMonitoringEnabled,
                onChanged: loading
                    ? null
                    : (v) => _toggle(
                        'content_monitoring_enabled', v),
              ),

              _ToggleCard(
                icon: Icons.auto_awesome_outlined,
                iconColor: const Color(0xFF6A1B9A),
                title: 'Gemini API content filtering',
                subtitle:
                    'AI-powered analysis of on-screen content (Module 2)',
                value: s.geminiContentFilterEnabled,
                onChanged: loading
                    ? null
                    : (v) => _toggle(
                        'gemini_content_filter_enabled', v),
              ),

              const SizedBox(height: 20),

              // ── Section: Notifications ──────────────────────────────
              _sectionHeader(
                  'Notifications', Icons.notifications_outlined,
                  isCore: true),
              const SizedBox(height: 8),

              _ToggleCard(
                icon: Icons.notifications_active_outlined,
                iconColor: AppColors.primary,
                title: 'Enable notifications',
                subtitle: 'Receive push alerts on your device',
                tag: 'Core',
                value: s.notificationEnabled,
                onChanged: loading
                    ? null
                    : (v) => _toggle('notification_enabled', v),
              ),

              _ToggleCard(
                icon: Icons.sms_outlined,
                iconColor: const Color(0xFF2E7D32),
                title: 'Enable SMS notification',
                subtitle: 'Receive alerts via SMS on your phone',
                value: s.smsNotificationEnabled,
                onChanged: loading
                    ? null
                    : (v) => _toggle(
                        'sms_notification_enabled', v),
              ),

              _ToggleCard(
                icon: Icons.phonelink_off_outlined,
                iconColor: const Color(0xFFC62828),
                title: 'Notify when child device is OFF',
                subtitle:
                    'Alert when heartbeat signal is lost (Module 3)',
                value: s.notifyWhenDeviceOff,
                onChanged: loading
                    ? null
                    : (v) => _toggle(
                        'notify_when_device_off', v),
              ),

              const SizedBox(height: 24),

              // ── Schema legend ────────────────────────────────────────
              _buildLegend(),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title, IconData icon,
          {bool isCore = false}) =>
      Row(children: [
        Icon(icon, size: 15, color: AppColors.primary),
        const SizedBox(width: 7),
        Text(title,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.8)),
        if (isCore) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text('Schema',
                style: TextStyle(
                    fontSize: 9,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3)),
          ),
        ],
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: AppColors.divider)),
      ]);

  Widget _buildLegend() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: AppColors.accent.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Settings info',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            _legendRow(
              color: AppColors.primary,
              label: 'Core',
              desc:
                  'Saved to monitoring_settings Firestore schema.',
            ),
            const SizedBox(height: 4),
            _legendRow(
              color: AppColors.textSub,
              label: 'Others',
              desc:
                  'Also saved to Firestore as extended fields. '
                  'Functional in Module 2/3.',
            ),
            const SizedBox(height: 6),
            const Text(
              'All settings take effect on the child device '
              'within seconds via Firestore listener.',
              style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSub,
                  height: 1.5),
            ),
          ],
        ),
      );

  Widget _legendRow(
          {required Color color,
          required String label,
          required String desc}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 10, height: 10,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSub,
                  height: 1.4),
              children: [
                TextSpan(
                    text: '$label — ',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ]);
}

// ─── Toggle card ──────────────────────────────────────────────────────────────
class _ToggleCard extends StatelessWidget {
  final IconData   icon;
  final Color      iconColor;
  final String     title;
  final String     subtitle;
  final String?    tag;
  final bool       value;
  final ValueChanged<bool>? onChanged;

  const _ToggleCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.tag,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value
                ? AppColors.primary.withOpacity(0.2)
                : AppColors.divider,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 5, offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          title: Row(children: [
            Expanded(
              child: Text(title,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: onChanged == null
                          ? AppColors.textSub
                          : AppColors.textPrimary)),
            ),
            if (tag != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tag!,
                    style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(subtitle,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSub,
                    height: 1.4)),
          ),
          trailing: Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withOpacity(0.3),
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: AppColors.divider,
          ),
        ),
      );
}