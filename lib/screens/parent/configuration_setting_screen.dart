// lib/screens/parent/configuration_setting_screen.dart
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
              _sectionHeader('Monitoring'),
              const SizedBox(height: 8),

              _ToggleCard(
                title: 'Offline Mode',
                subtitle: 'Pause all monitoring temporarily',
                value: s.offlineMode,
                onChanged: loading
                    ? null
                    : (v) => _toggle('offline_mode', v),
              ),

              _ToggleCard(
                title: 'Content Filtering',
                subtitle: 'Monitor all apps and browsing activity',
                value: s.contentMonitoringEnabled,
                onChanged: loading
                    ? null
                    : (v) => _toggle(
                        'content_monitoring_enabled', v),
              ),

              _ToggleCard(
                title: 'AI Filtering',
                subtitle: 'AI-powered analysis of on-screen content',
                value: s.geminiContentFilterEnabled,
                onChanged: loading
                    ? null
                    : (v) => _toggle(
                        'gemini_content_filter_enabled', v),
              ),
              
              _ToggleCard(
                title: 'Bypass Detection',
                subtitle: 'Alert when child tries to bypass SafeChild',
                value: s.bypassDetectionEnabled,
                onChanged: loading
                    ? null
                    : (v) => _toggle('bypass_detection_enabled', v),
              ),

              const SizedBox(height: 20),

              _sectionHeader('Notifications'),
              const SizedBox(height: 8),

              _ToggleCard(
                title: 'Enable notifications',
                subtitle: 'Receive push alerts on your device',
                value: s.notificationEnabled,
                onChanged: loading
                    ? null
                    : (v) => _toggle('notification_enabled', v),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionHeader(String title) =>
      Row(children: [
        const SizedBox(width: 4),
        Text(title,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.8)),
        const SizedBox(width: 8),
        const Expanded(child: Divider(color: AppColors.divider)),
      ]);
}

class _ToggleCard extends StatelessWidget {
  final String     title;
  final String     subtitle;
  final bool       value;
  final ValueChanged<bool>? onChanged;

  const _ToggleCard({
    required this.title,
    required this.subtitle,
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
              const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          title: Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: onChanged == null
                      ? AppColors.textSub
                      : AppColors.textPrimary)),
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