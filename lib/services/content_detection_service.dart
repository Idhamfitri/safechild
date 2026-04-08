import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/accessibility_event.dart';
import 'package:shared_preferences/shared_preferences.dart';


class ContentDetectionService {
  
  final _geminiModel = FirebaseAI.googleAI().generativeModel(model: 'gemini-2.5-flash-lite');
  final _db = FirebaseFirestore.instance;
  StreamSubscription? _accessibilitySubscription;
  String?             _deviceId;
  final Map<String, DateTime> _lastProcessed = {};
  static const _debounceDuration = Duration(seconds: 5);


  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId   = prefs.getString('device_id');

    if (_deviceId == null || _deviceId!.isEmpty) {
      debugPrint('SAFECHILD: start() aborted — device_id not found');
      return;
    }
    debugPrint('SAFECHILD: start() — device_id = $_deviceId');

    // Soft check — log only, do NOT return on false (unreliable on Xiaomi)
    try {
      final enabled =
          await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
      debugPrint('SAFECHILD: accessibility permission check = $enabled');
    } catch (e) {
      debugPrint('SAFECHILD: permission check failed — $e — proceeding anyway');
    }

    // Delay gives accessibility service time to fully initialise
    await Future.delayed(const Duration(seconds: 3));

    try {
      _accessibilitySubscription =
          FlutterAccessibilityService.accessStream.listen(
        _onAccessibilityEvent,
        onError: (e) => debugPrint('SAFECHILD: stream error — $e'),
        onDone:  ()  => debugPrint('SAFECHILD: stream closed'),
      );
      debugPrint('SAFECHILD: accessibility stream subscription started ✓');
    } catch (e) {
      debugPrint('SAFECHILD: failed to subscribe to accessStream — $e');
    }
  }

  Future<void> stop() async {
    await _accessibilitySubscription?.cancel();
    _accessibilitySubscription = null;
    debugPrint('SAFECHILD: detection stopped');
  }



// Packages to ignore 
static const _ignoredPackages = {
  'com.android.systemui',
  'com.android.launcher3',
  'com.miui.home',
  'com.miui.systemui',
  'com.safechild.safechild',
  'com.android.settings',
  'com.miui.securitycenter',
  'com.miui.permcenter',
  'com.google.android.packageinstaller',
  'com.android.packageinstaller',
};

void _onAccessibilityEvent(AccessibilityEvent event) {
  final sourceApp = event.packageName ?? 'unknown';

  // Skip system packages 
  if (_ignoredPackages.any((pkg) => sourceApp.contains(pkg))) return;

  String? rawText;

  final mainText = event.text;
  if (mainText != null &&
      mainText != 'null' &&
      mainText.trim().isNotEmpty) {
    rawText = _cleanText(mainText);
  }

  // Fallback — subNodes
  if (rawText == null && event.subNodes != null) {
    final subTexts = event.subNodes!
        .where((n) =>
            n.text != null &&
            n.text != 'null' &&
            n.text!.trim().isNotEmpty)
        .map((n) => _cleanText(n.text!))
        .where((t) => t.isNotEmpty)
        .join(' ');
    if (subTexts.isNotEmpty) rawText = subTexts;
  }

  debugPrint('SAFECHILD: event from $sourceApp → "${rawText ?? "(empty)"}"');

  if (rawText == null) return;

  final lastTime = _lastProcessed[sourceApp];
  if (lastTime != null &&
      DateTime.now().difference(lastTime) < _debounceDuration) {
    debugPrint('SAFECHILD: debounced $sourceApp — skipping');
    return;
  }
  _lastProcessed[sourceApp] = DateTime.now();

  _processText(rawText, sourceApp);
}

String _cleanText(String raw) {
  // Extract mText values from Android span format
  // e.g. {mText: hello world} → "hello world"
  final mTextMatches = RegExp(r'mText:\s*([^}]+)')
      .allMatches(raw)
      .map((m) => m.group(1)?.trim() ?? '')
      .where((t) => t.isNotEmpty)
      .toList();

  if (mTextMatches.isNotEmpty) {
    return mTextMatches.join(' ');
  }

  // No span format — return cleaned raw text
  return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
}

  Future<void> _processText(String rawText, String sourceApp) async {
    final cleaned = _preprocess(rawText);
    if (cleaned == null) {
      debugPrint('SAFECHILD: skipped — less than 3 words');
      return;
    }
    debugPrint('SAFECHILD: processing "$cleaned" from $sourceApp');

    final connectivityResult = await Connectivity().checkConnectivity();
    final isOnline =
        connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi);

    debugPrint('SAFECHILD: online = $isOnline');

    if (isOnline) {
      await _classifyWithGemini(cleaned, sourceApp);
    } else {
      debugPrint('SAFECHILD: offline — skipping');
    }
  }

  String? _preprocess(String raw) {
    final cleaned = raw.trim().toLowerCase();
    final words   = cleaned.split(RegExp(r'\s+'));
    if (words.length < 3) return null;
    return cleaned;
  }

  Future<void> _classifyWithGemini(String text, String sourceApp) async {
    debugPrint('SAFECHILD: calling Gemini for "$text"');
    try {
      final prompt = '''
Classify this text from a child's device.
It may be Malay, English or mixed slang.
Reply ONLY in this exact JSON format with no extra text:
{"category":"safe/toxic/threatening","confidence":0.0}
Text: "$text"
''';

      final response = await _geminiModel.generateContent(
          [Content.text(prompt)]);
      final result = response.text;

      debugPrint('SAFECHILD: gemini response = $result');

      if (result != null && result.isNotEmpty) {
        _parseAndHandle(result, sourceApp, rawText: text);
      } else {
        debugPrint('SAFECHILD: gemini returned empty response');
      }
    } catch (e) {
      debugPrint('SAFECHILD: gemini error — $e');
    }
  }

  void _parseAndHandle(String jsonText, String sourceApp, {required String rawText}) {
    try {
      final cleaned = jsonText
          .trim()
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final result     = jsonDecode(cleaned) as Map<String, dynamic>;
      final category   = (result['category'] as String?) ?? 'safe';
      final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;

      debugPrint('SAFECHILD: category=$category confidence=$confidence');

      _handleResult(category, confidence, sourceApp, 'gemini', rawText: rawText);
    } catch (e) {
      debugPrint('SAFECHILD: JSON parse error — $e — raw: $jsonText');
    }
  }

  void _handleResult(
      String category, double confidence, String sourceApp, String model,
      {required String rawText}) {
    if (confidence < 0.5 || category == 'safe') {
      debugPrint('SAFECHILD: safe or low confidence — not logged');
      return;
    }

    final summary   = _buildSummary(category, sourceApp);
    final sendAlert = confidence >= 0.75;

    debugPrint(
        'SAFECHILD: logging incident — summary="$summary" alert=$sendAlert');

    _logIncident(
      summary:    summary,
      description: rawText,
      source:     sourceApp,
      confidence: confidence,
      category:   category,
      model:      model,
      alert:      sendAlert,
    );
  }

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
        packageName.contains('x.com')) {
      return 'X / Twitter';
    }
    final parts = packageName.split('.');
    return parts.isNotEmpty
        ? parts.last[0].toUpperCase() + parts.last.substring(1)
        : packageName;
  }

  Future<void> _logIncident({
    required String summary,
    required String source,
    required String description,
    required double confidence,
    required String category,
    required String model,
    required bool   alert,
  }) async {
    if (_deviceId == null) return;

    try {
      await _db.collection('incidents').add({
        'device_id':        _deviceId,
        'text_summary':     summary,
        'description':      description,
        'source':           source,
        'confidence_score': confidence,
        'category':         category,
        'detection_model':  model,
        'detected_at':      FieldValue.serverTimestamp(),
        'is_reviewed':      false,
        'is_alert_send':    alert,
      });
      debugPrint('SAFECHILD: incident written to Firestore ✓');
    } catch (e) {
      debugPrint('SAFECHILD: Firestore write failed — $e');
    }
  }
}