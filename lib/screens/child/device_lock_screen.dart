import 'package:flutter/material.dart';
import '../../services/screen_time_service.dart';
import '../../utils/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceLockScreen extends StatefulWidget {
  final String lockReason;
  final bool isManualLock;
  
  const DeviceLockScreen({super.key, required this.lockReason, this.isManualLock = false});

  @override
  State<DeviceLockScreen> createState() => _DeviceLockScreenState();
}

class _DeviceLockScreenState extends State<DeviceLockScreen> {
  final _screenTimeService = ScreenTimeService();
  bool _isRequesting = false;

  Future<void> _requestTime(int minutes, String reason) async {
    final prefs = await SharedPreferences.getInstance();
    final deviceId = prefs.getString('device_id');
    if (deviceId == null) return;

    setState(() => _isRequesting = true);
    
    try {
      await _screenTimeService.submitRequest(deviceId, minutes, reason: reason);
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
    final reasonController = TextEditingController();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
          left: 24,
          right: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Request Extra Time',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for extension (Required)',
                hintText: 'e.g. Finishing homework...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            const Text('Select Time:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _TimeButton(15, reasonController),
                _TimeButton(30, reasonController),
                _TimeButton(60, reasonController),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _TimeButton(int minutes, TextEditingController controller) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      onPressed: () {
        final reason = controller.text.trim();
        if (reason.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enter a reason first!')),
          );
          return;
        }
        Navigator.pop(context);
        _requestTime(minutes, reason);
      },
      child: Text('$minutes min'),
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
                    widget.isManualLock ? Icons.sentiment_very_dissatisfied : Icons.lock_outline,
                    size: 100,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 30),
                  Text(
                    widget.lockReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 60),
                  if (!widget.isManualLock)
                    TextButton(
                      onPressed: _isRequesting ? null : _showRequestDialog,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                      ),
                      child: _isRequesting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                            )
                          : const Text(
                              'Request time override',
                              style: TextStyle(
                                fontSize: 14,
                                decoration: TextDecoration.underline,
                              ),
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
