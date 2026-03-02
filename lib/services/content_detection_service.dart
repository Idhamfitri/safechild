// lib/services/content_detection_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// MODULE 2 — AI Content Detection and Filtering
//
// Flow:
//   flutter_accessibility_service stream fires on screen change
//     → preprocess (skip if < 3 words)
//     → check connectivity
//     → ONLINE: classify with Gemini 2.5 Flash
//     → confidence ≥ 0.5  → log to Firestore (silent)
//     → confidence ≥ 0.75 → log + is_alert_send = true
//                           → Cloud Function sends FCM to parent automatically
//
// OFFLINE fallback will be added in a later step once Gemini flow is verified.
//
// Raw text is NEVER stored — only text_summary written to Firestore.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/accessibility_event.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContentDetectionService {
  
  static const _geminiApiKey = 'AIzaSyAuviBWDGe_5J87oRb97K2k5ETk9ZHKZ6g';

  // ── Gemini model — gemini-2.5-flash as per Module 2 spec ─────────────────
  late final GenerativeModel _geminiModel;

  final _db = FirebaseFirestore.instance;

  StreamSubscription? _accessibilitySubscription;
  String?             _deviceId;

  // Debounce: track last processed time per source app
  // Prevents hammering Gemini with rapid repeated events from the same app
  final Map<String, DateTime> _lastProcessed = {};
  static const _debounceDuration = Duration(seconds: 5);

  // ── Initialise ────────────────────────────────────────────────────────────
  ContentDetectionService() {
    _geminiModel = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _geminiApiKey,
    );
  }

  // ── Start listening ───────────────────────────────────────────────────────
  Future<void> start() async {
    // Load device_id from SharedPreferences (stored during pairing)
    final prefs = await SharedPreferences.getInstance();
    _deviceId   = prefs.getString('device_id');

    if (_deviceId == null || _deviceId!.isEmpty) {
      // Not paired — don't start detection
      return;
    }

    // Check accessibility is enabled before listening
    final enabled =
        await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (!enabled) {
      // Accessibility not granted — cannot capture text
      // Permission setup screen handles this case
      return;
    }

    // Start stream from flutter_accessibility_service
    _accessibilitySubscription =
        FlutterAccessibilityService.accessStream.listen(_onAccessibilityEvent);
  }

  // ── Stop listening ────────────────────────────────────────────────────────
  Future<void> stop() async {
    await _accessibilitySubscription?.cancel();
    _accessibilitySubscription = null;
  }

  // ── Handle accessibility event ────────────────────────────────────────────
  void _onAccessibilityEvent(AccessibilityEvent event) {
    final rawText   = event.text;
    final sourceApp = event.packageName ?? 'unknown';

    if (rawText == null || rawText.isEmpty) return;

    // Debounce — skip if we processed this app very recently
    final lastTime = _lastProcessed[sourceApp];
    if (lastTime != null &&
        DateTime.now().difference(lastTime) < _debounceDuration) {
      return;
    }
    _lastProcessed[sourceApp] = DateTime.now();

    // Process async without blocking the stream
    _processText(rawText, sourceApp);
  }

  // ── Process captured text ─────────────────────────────────────────────────
  Future<void> _processText(String rawText, String sourceApp) async {
    // STEP 1 — Pre-processing: skip if less than 3 words
    final cleaned = _preprocess(rawText);
    if (cleaned == null) return;

    // STEP 2 — Check internet
    final connectivityResult = await Connectivity().checkConnectivity();
    final isOnline = connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi);

    if (isOnline) {
      // STEP 3 — Classify with Gemini
      await _classifyWithGemini(cleaned, sourceApp);
    }
    // Offline backup: to be added after Gemini flow is verified
  }

  // ── Pre-processing — only skip if < 3 words ───────────────────────────────
  String? _preprocess(String raw) {
    final cleaned = raw.trim().toLowerCase();
    final words   = cleaned.split(RegExp(r'\s+'));
    if (words.length < 3) return null;
    return cleaned;
  }

  // ── Gemini 2.5 Flash classification ──────────────────────────────────────
  Future<void> _classifyWithGemini(String text, String sourceApp) async {
    try {
      final prompt = '''
Classify this text from a child\'s device.
It may be Malay, English or mixed slang.
Reply ONLY in this exact JSON format with no extra text:
{"category":"safe/toxic/threatening","confidence":0.0}
Text: "$text"
''';

      final response =
          await _geminiModel.generateContent([Content.text(prompt)]);
      final result = response.text;

      if (result != null && result.isNotEmpty) {
        _parseAndHandle(result, sourceApp);
      }
    } catch (e) {
      // Gemini failed — offline backup will go here later
      // For now: silently skip
    }
  }

  // ── Parse Gemini JSON response ────────────────────────────────────────────
  void _parseAndHandle(String jsonText, String sourceApp) {
    try {
      // Strip markdown fences Gemini sometimes adds
      final cleaned = jsonText
          .trim()
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final result     = jsonDecode(cleaned) as Map<String, dynamic>;
      final category   = (result['category'] as String?) ?? 'safe';
      final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;

      _handleResult(category, confidence, sourceApp, 'gemini');
    } catch (_) {
      // Parse failed — skip
    }
  }

  // ── Handle result — apply confidence thresholds ───────────────────────────
  void _handleResult(
      String category, double confidence, String sourceApp, String model) {
    // confidence < 0.5 → safe, do nothing
    if (confidence < 0.5 || category == 'safe') return;

    // Build summary — raw text is discarded here, never stored
    final summary   = _buildSummary(category, sourceApp);
    final sendAlert = confidence >= 0.75;

    _logIncident(
      summary:    summary,
      source:     sourceApp,
      confidence: confidence,
      category:   category,
      model:      model,
      alert:      sendAlert,
    );
  }

  // ── Build human-readable summary (no raw text) ────────────────────────────
  String _buildSummary(String category, String sourceApp) {
    final appName = _friendlyAppName(sourceApp);
    final type    = category == 'threatening' ? 'Threatening' : 'Toxic';
    return '$type content detected in $appName';
  }

  String _friendlyAppName(String packageName) {
    if (packageName.contains('whatsapp'))  return 'WhatsApp';
    if (packageName.contains('chrome'))    return 'Chrome';
    if (packageName.contains('instagram')) return 'Instagram';
    if (packageName.contains('tiktok'))    return 'TikTok';
    if (packageName.contains('telegram'))  return 'Telegram';
    if (packageName.contains('youtube'))   return 'YouTube';
    if (packageName.contains('facebook'))  return 'Facebook';
    if (packageName.contains('twitter') ||
        packageName.contains('x.com'))     return 'X / Twitter';
    // Return last segment of package name as fallback
    final parts = packageName.split('.');
    return parts.isNotEmpty
        ? parts.last[0].toUpperCase() + parts.last.substring(1)
        : packageName;
  }

  // ── Log incident to Firestore ─────────────────────────────────────────────
  // Raw text is already gone at this point — only summary is stored.
  Future<void> _logIncident({
    required String  summary,
    required String  source,
    required double  confidence,
    required String  category,
    required String  model,
    required bool    alert,
  }) async {
    if (_deviceId == null) return;

    await _db.collection('incidents').add({
      'device_id':        _deviceId,
      'text_summary':     summary,      // NOT raw text — privacy safe
      'source':           source,
      'confidence_score': confidence,
      'category':         category,
      'detection_model':  model,
      'detected_at':      FieldValue.serverTimestamp(),
      'is_reviewed':      false,
      'is_alert_send':    alert,
    });

    // Raw text is gone — never persisted anywhere
  }
}