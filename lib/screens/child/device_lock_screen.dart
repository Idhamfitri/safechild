import 'package:flutter/material.dart';
import '../../services/screen_time_service.dart';
import '../../utils/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceLockScreen extends StatefulWidget {
  final String lockReason;
  final String? lockedBy;
  
  const DeviceLockScreen({super.key, required this.lockReason, this.lockedBy});

  @override
  State<DeviceLockScreen> createState() => _DeviceLockScreenState();
}

class _DeviceLockScreenState extends State<DeviceLockScreen> {
  final _screenTimeService = ScreenTimeService();
  bool _isRequesting = false;

  Future<void> _requestTime(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');
    if (deviceId == null) return;

    setState(() => _isRequesting = true);
    
    try {
      await _screenTimeService.submitRequest(deviceId, minutes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Requested $minutes minutes. Pending parent approval.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to request time. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  void _showRequestDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Request Extra Time',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.timer_outlined, color: AppColors.primary),
              title: const Text('15 Minutes'),
              onTap: () {
                Navigator.pop(context);
                _requestTime(15);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined, color: AppColors.primary),
              title: const Text('30 Minutes'),
              onTap: () {
                Navigator.pop(context);
                _requestTime(30);
              },
            ),
            ListTile(
              leading: const Icon(Icons.timer_outlined, color: AppColors.primary),
              title: const Text('1 Hour'),
              onTap: () {
                Navigator.pop(context);
                _requestTime(60);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold that handles the Android Back Button interception natively ideally.
    return PopScope(
      canPop: false, // Prevent going back
      child: Scaffold(
        backgroundColor: AppColors.primary,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.lockedBy == 'parent' ? Icons.sentiment_very_dissatisfied : Icons.lock_outline,
                    size: 100,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 30),
                  Text(
                    widget.lockedBy == 'parent' ? 'Locked by Parent' : 'Device Locked',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.lockedBy == 'parent' 
                      ? 'Device has been locked by parent.' 
                      : widget.lockReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 60),
                  if (widget.lockedBy != 'parent')
                    ElevatedButton(
                      onPressed: _isRequesting ? null : _showRequestDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _isRequesting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Request Extra Time',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
