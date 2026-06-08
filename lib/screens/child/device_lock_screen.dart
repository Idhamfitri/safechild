import 'package:flutter/material.dart';
import 'package:device_policy_manager/device_policy_manager.dart';
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

class _DeviceLockScreenState extends State<DeviceLockScreen>
    with WidgetsBindingObserver {
  final _screenTimeService = ScreenTimeService();
  bool _isRequesting = false;
  // Prevents lockNow() from firing when the request dialog/keyboard is open.
  // On some MIUI devices the keyboard briefly triggers AppLifecycleState.paused.
  bool _requestDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Skip lock when dialog is open — keyboard show/hide on some MIUI devices
    // briefly fires paused, which would cause repeated screen blinks.
    if (state == AppLifecycleState.paused && !_requestDialogOpen) {
      DevicePolicyManager.lockNow();
    }
  }

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
    int selectedMinutes = 15;
    _requestDialogOpen = true;

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 160),
      // Plain fade — no scale/spring bounce that causes a brief layout overflow
      transitionBuilder: (ctx, anim, _, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut), child: child),
      pageBuilder: (ctx, anim1, anim2) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // Re-reads keyboard height every rebuild so the card shifts up cleanly
          final keyboardInset = MediaQuery.viewInsetsOf(dialogContext).bottom;
          return Dialog(
            // Upper-centre — leaves room below so the keyboard never pushes it off-screen
            alignment: const Alignment(0, -0.45),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: EdgeInsets.fromLTRB(24, 24, 24, keyboardInset + 16),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Title row ──
                  const Text(
                    'Request Extra Time',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // ── Reason field (single line, compact) ──
                  TextField(
                    controller: reasonController,
                    decoration: const InputDecoration(
                      labelText: 'Reason',
                      hintText: 'e.g. Finishing homework…',
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    maxLines: 1,
                    textInputAction: TextInputAction.done,
                  ),
                  const SizedBox(height: 14),

                  // ── Duration row ──
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Duration',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(
                        '$selectedMinutes min',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary),
                      ),
                    ],
                  ),
                  Slider(
                    value: selectedMinutes.toDouble(),
                    min: 1,
                    max: 60,
                    divisions: 59,
                    activeColor: AppColors.primary,
                    label: '$selectedMinutes min',
                    onChanged: (v) =>
                        setDialogState(() => selectedMinutes = v.round()),
                  ),

                  // ── Buttons ──
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel',
                            style: TextStyle(color: Colors.grey)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () {
                          final reason = reasonController.text.trim();
                          if (reason.isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(
                                  content: Text('Please enter a reason first!')),
                            );
                            return;
                          }
                          Navigator.of(dialogContext).pop();
                          _requestTime(selectedMinutes, reason);
                        },
                        child: const Text('Send Request'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() {
      if (mounted) _requestDialogOpen = false;
    });
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
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isRequesting ? null : _showRequestDialog,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppColors.primary,
                          disabledBackgroundColor: Colors.white38,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: _isRequesting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.primary),
                              )
                            : const Icon(Icons.access_time_rounded),
                        label: Text(
                          _isRequesting ? 'Sending Request...' : 'Request Extra Time',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
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
