// lib/screens/child/child_active_screen.dart
// Shown after the child device has successfully paired.
// In production (Module 4), this screen is hidden / the app runs silently.
// For now it confirms monitoring is active.

import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';

class ChildActiveScreen extends StatelessWidget {
  const ChildActiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Shield icon
              Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield,
                    size: 62, color: AppColors.primary),
              ),
              const SizedBox(height: 28),

              const Text('SafeChild is Active',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary)),
              const SizedBox(height: 12),
              const Text(
                'This device is being monitored.\n'
                'SafeChild runs silently in the background to keep you safe.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSub,
                    height: 1.6),
              ),
              const SizedBox(height: 40),

              // Status chip
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.2)),
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.circle, size: 10, color: AppColors.statusLinked),
                  SizedBox(width: 8),
                  Text('Monitoring Active',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ]),
              ),

              const SizedBox(height: 16),
              const Text(
                'Background services will be enabled in Module 4.',
                style: TextStyle(fontSize: 11, color: AppColors.textSub),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}