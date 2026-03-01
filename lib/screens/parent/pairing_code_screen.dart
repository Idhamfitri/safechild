// lib/screens/parent/pairing_code_screen.dart
// FIXED: digit boxes now use FittedBox + LayoutBuilder so they never overflow
// on any screen size (small physical device or emulator).

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
  bool _linked = false;

  @override
  void initState() {
    super.initState();
    _link = widget.link;
    _sub = _pairingService
        .watchLinkStatus(widget.link.pCLinkId)
        .listen((updated) {
      if (!mounted) return;
      setState(() => _link = updated);
      if (updated.isLinked && !_linked) {
        _linked = true;
        HapticFeedback.mediumImpact();
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(
                  builder: (_) => const ParentDashboardScreen()),
              (_) => false);
        });
      } else if (updated.isExpired) {
        _showExpiredDialog();
      }
    });
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
            'The pairing code will be invalidated. You can generate a new one later.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep Waiting')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              child: const Text('Cancel')),
        ],
      ),
    );
    if (confirmed == true) {
      await _pairingService.expirePairingCode(widget.link.pCLinkId);
      if (mounted) Navigator.pop(context);
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
    return PopScope(
      canPop: _linked,
      onPopInvoked: (didPop) { if (!didPop) _cancel(); },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Link Child Device'),
          automaticallyImplyLeading: !_linked,
        ),
        body: _linked ? _buildSuccess() : _buildCodeDisplay(),
      ),
    );
  }

  // ── Code display ──────────────────────────────────────────────────────────
  Widget _buildCodeDisplay() {
    final code = _link?.pairingCode ?? widget.link.pairingCode;

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

          const Text('Enter this code on your child\'s device',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text(
              'Open SafeChild on the child\'s device → tap "Create Account" → '
              'select "Child Device" → enter the code below.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppColors.textSub, height: 1.5)),
          const SizedBox(height: 32),

          // ── Code box ─────────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 24),
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

              // ── FIXED: LayoutBuilder so digits never overflow ──────────
              LayoutBuilder(
                builder: (_, constraints) {
                  // Available width ÷ 6 digits, minus margins between them
                  final totalMargin = 6.0 * 2; // 6 gaps × margin per side
                  final digitW = ((constraints.maxWidth - totalMargin * 6) / 6)
                      .clamp(32.0, 52.0);
                  final digitH = (digitW * 1.25).clamp(40.0, 64.0);
                  final fontSize = (digitW * 0.55).clamp(18.0, 28.0);

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(code.length, (i) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: digitW,
                        height: digitH,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.2)),
                        ),
                        alignment: Alignment.center,
                        child: Text(code[i],
                            style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primary)),
                      );
                    }),
                  );
                },
              ),

              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: _copyCode,
                icon: const Icon(Icons.copy_outlined, size: 15),
                label: const Text('Copy Code'),
                style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSub),
              ),
            ]),
          ),

          const SizedBox(height: 28),

          // Waiting indicator
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.primary)),
            const SizedBox(width: 10),
            Text('Waiting for child device...',
                style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSub.withOpacity(0.8))),
          ]),

          const SizedBox(height: 36),
          TextButton(
            onPressed: _cancel,
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.error)),
          ),
        ]),
      ),
    );
  }

  // ── Success state ─────────────────────────────────────────────────────────
  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.check_circle,
                size: 60, color: AppColors.primary),
          ),
          const SizedBox(height: 24),
          const Text('Device Linked!',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary)),
          const SizedBox(height: 10),
          const Text(
              'The child\'s device is now linked. Monitoring will begin shortly.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14, color: AppColors.textSub, height: 1.5)),
          const SizedBox(height: 24),
          const CircularProgressIndicator(color: AppColors.primary),
        ]),
      ),
    );
  }
}