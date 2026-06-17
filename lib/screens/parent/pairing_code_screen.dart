// lib/screens/parent/pairing_code_screen.dart
// until the child completes full setup (setup_phase == active).

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/parent_child_link_model.dart';
import '../../services/pairing_service.dart';
import '../../utils/app_theme.dart';
import 'dashboard_screen.dart';

class PairingCodeScreen extends StatefulWidget {
  final ParentChildLinkModel link;
  const PairingCodeScreen({super.key, required this.link});

  @override
  State<PairingCodeScreen> createState() => _PairingCodeScreenState();
}

class _PairingCodeScreenState extends State<PairingCodeScreen> {
  final _pairingService = PairingService();
  late StreamSubscription<ParentChildLinkModel> _sub;

  ParentChildLinkModel? _link;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _link = widget.link;
    _sub = _pairingService
        .watchLinkStatus(widget.link.pCLinkId)
        .listen(_onLinkUpdate);
  }

  void _onLinkUpdate(ParentChildLinkModel updated) {
    if (!mounted) return;
    setState(() => _link = updated);

    if (updated.isExpired && !_navigating) _showExpiredDialog();

    // Wait for child to complete permission setup before navigating
    if (updated.isLinked && updated.setupPhase == 'active' && !_navigating) {
      _navigating = true;
      HapticFeedback.mediumImpact();
      Future.delayed(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
          (_) => false,
        );
      });
    }
  }

  void _showExpiredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Code Expired'),
        content: const Text(
            'The pairing code has expired. Please go back and generate a new one.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Generate New Code'),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Pairing?'),
        content: const Text(
            'The pairing code will be cancelled. This device will be removed.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Waiting')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, Cancel')),
        ],
      ),
    );
    if (confirmed == true) {
      // Expire the code AND remove the link so card disappears from dashboard
      await _pairingService.expirePairingCode(widget.link.pCLinkId);
      await _pairingService.unlinkDevice(widget.link.pCLinkId);
      if (!mounted) return;
      // Clear entire stack back to parent dashboard
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const ParentDashboardScreen()),
        (_) => false,
      );
    }
  }

  void _copyCode() {
    final code = _link?.pairingCode ?? widget.link.pairingCode;
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Code copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2)));
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final link  = _link ?? widget.link;
    final isPending = link.isPending;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) { if (!didPop) _cancel(); },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Link Child Device'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _cancel,
          ),
        ),
        body: isPending
            ? _buildCodeDisplay(link.pairingCode)
            : _buildLinking(),
      ),
    );
  }

  // ── Show pairing code — before child enters it ────────────────────────────
  Widget _buildCodeDisplay(String code) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.phone_android,
                size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text("Enter this code on your child's device",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text(
              'Open SafeChild → "Create Account" → "Child Device" → enter the code below.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSub, height: 1.5)),
          const SizedBox(height: 32),

          // Code box
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 6)),
              ],
            ),
            child: Column(children: [
              const Text('PAIRING CODE',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 2,
                      color: AppColors.textSub,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),

              // Responsive digit boxes
              LayoutBuilder(builder: (_, c) {
                final dw = ((c.maxWidth - 48) / 6).clamp(32.0, 52.0);
                final dh = (dw * 1.25).clamp(40.0, 64.0);
                final fs = (dw * 0.55).clamp(18.0, 28.0);
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(code.length, (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: dw, height: dh,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.2)),
                    ),
                    alignment: Alignment.center,
                    child: Text(code[i],
                        style: TextStyle(
                            fontSize: fs,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary)),
                  )),
                );
              }),

              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _copyCode,
                icon: const Icon(Icons.copy_outlined, size: 15),
                label: const Text('Copy Code'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSub),
              ),
            ]),
          ),

          const SizedBox(height: 32),
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.error)),
          ),
        ]),
      ),
    );
  }

  // ── Simple linking spinner — shown after child enters code ────────────────
  Widget _buildLinking() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 3),
          const SizedBox(height: 28),
          const Text('Setting up permissions...',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Text(
              'The child device is granting required permissions.\nPlease wait — this may take a moment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSub,
                  height: 1.5)),
          const SizedBox(height: 40),
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.error)),
          ),
        ]),
      ),
    );
  }
}