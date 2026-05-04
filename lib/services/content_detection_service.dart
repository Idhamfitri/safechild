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
  // Use gemini-1.5-flash for the best balance of speed and cost
  final _geminiModel = FirebaseAI.googleAI()
      .generativeModel(model: 'gemini-2.5-flash-lite'); 
  
  final _db = FirebaseFirestore.instance;
  static StreamSubscription? _accessibilitySubscription;
  String? _deviceId;

  // ── Optimization State ────────────────────────────────────────────────
  final Map<String, DateTime> _lastProcessed = {};
  static const _debounceDuration = Duration(seconds: 5);
  
  String? _lastTextProcessed; 
  DateTime? _lastTextTime;

  final Map<String, DateTime> _lastHarmfulTime = {};
  static const _harmfulCooldown = Duration(seconds: 30);

  // ── Monitoring Config ─────────────────────────────────────────────────
  static const _monitoredPackages = {
    'com.whatsapp',
    'com.android.chrome',
    'com.instagram.android',
    'com.ss.android.ugc.trill', // TikTok
    'org.telegram.messenger',
    'com.google.android.youtube',
    'com.facebook.katana',
    'com.facebook.orca', // Messenger
    'com.twitter.android',
    'x.com',
    'com.snapchat.android',
    'com.discord',
    'com.reddit.frontpage',
  };

  static const _uiPatterns = [
    'send', 'cancel', 'ok', 'back', 'next', 'reply', 'like', 'share', 
    'follow', 'block', 'settings', 'menu', 'home', 'search', 'loading', 
    'refresh', 'tap to load', 'type a message', 'write a comment',
    'battery', 'wifi', 'bluetooth', 'yesterday', 'today', 'just now',
    'seen', 'delivered', 'online',
  ];

  // Local "Red Flag" keywords (Malay + English)
  static const _localTriggers = [
    'babi', 'pukimak', 'anjing', 'bodoh', 'sial', 'pantat', 'kepala bapak',
    'stupid', 'idiot', 'kill yourself', 'hate you', 'f*ck', 'retard', 'die'
  ];

  // ─────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_accessibilitySubscription != null) return;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');

    if (_deviceId == null || _deviceId!.isEmpty) {
      debugPrint('SAFECHILD: device_id not found. Cannot start logging.');
      return;
    }

    await Future.delayed(const Duration(seconds: 2));

    _accessibilitySubscription = FlutterAccessibilityService.accessStream.listen(
      _onAccessibilityEvent,
      onError: (e) => debugPrint('SAFECHILD: stream error — $e'),
    );
    debugPrint('SAFECHILD: service started for $_deviceId ✓');
  }

  Future<void> stop() async {
    await _accessibilitySubscription?.cancel();
    _accessibilitySubscription = null;
    debugPrint('SAFECHILD: service stopped.');
  }

  // ─────────────────────────────────────────────────────────────────────
  // Event Handler
  // ─────────────────────────────────────────────────────────────────────

  void _onAccessibilityEvent(AccessibilityEvent event) {
    final sourceApp = event.packageName ?? 'unknown';

    // 1. App Whitelist
    if (!_monitoredPackages.any((pkg) => sourceApp.contains(pkg))) return;

    // 2. Extract and Clean Text
    String? rawText;
    if (event.text != null && event.text != 'null' && event.text!.trim().isNotEmpty) {
      rawText = _cleanText(event.text!);
    }

    // Fallback to subNodes (common in list views/chats)
    if ((rawText == null || rawText.isEmpty) && event.subNodes != null) {
      final subTexts = event.subNodes!
          .where((n) => n.text != null && n.text != 'null')
          .map((n) => _cleanText(n.text!))
          .where((t) => t.isNotEmpty && !_isUIText(t))
          .join(' ');
      if (subTexts.isNotEmpty) rawText = subTexts;
    }

    if (rawText == null || rawText.isEmpty) return;

    // 3. UI Label Filter (Skip "Send", "Cancel", etc.)
    if (_isUIText(rawText)) return;

    // 4. Deduplication (Skip identical events from scrolling)
    if (_lastTextProcessed == rawText &&
        _lastTextTime != null &&
        DateTime.now().difference(_lastTextTime!) < const Duration(seconds: 3)) {
      return;
    }

    // 5. App Debounce
    final lastTime = _lastProcessed[sourceApp];
    if (lastTime != null && DateTime.now().difference(lastTime) < _debounceDuration) {
      return;
    }

    // Update tracking state
    _lastProcessed[sourceApp] = DateTime.now();
    _lastTextProcessed = rawText;
    _lastTextTime = DateTime.now();

    debugPrint('SAFECHILD: event from $sourceApp → "$rawText"');

    _processText(rawText, sourceApp);
  }

  bool _isUIText(String text) {
    final lower = text.toLowerCase().trim();
    // Filter out patterns and very short strings (noise)
    return _uiPatterns.any((p) => lower == p || lower.length < 2);
  }

  String _cleanText(String raw) {
    // Robust extraction from Android node dumps
    final mTextMatches = RegExp(r'mText:\s*([^,}]+)')
        .allMatches(raw)
        .map((m) => m.group(1)?.trim() ?? '')
        .where((t) => t.isNotEmpty)
        .toList();

    if (mTextMatches.isNotEmpty) return mTextMatches.join(' ');

    // Clean brackets and extra whitespace
    return raw.replaceAll(RegExp(r'\[.*?\]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ─────────────────────────────────────────────────────────────────────
  // Pipeline
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _processText(String rawText, String sourceApp) async {
    final cleaned = _preprocess(rawText);
    if (cleaned == null || _shouldIgnoreMessage(cleaned)) return;

    debugPrint('SAFECHILD: processing "$cleaned" from $sourceApp');

    // 6. Local Keyword Pre-Filter
    bool hasLocalTrigger = _localTriggers.any((word) => cleaned.contains(word));
    
    // Efficiency rule: Only AI-check if it has keywords OR is long enough to be a sentence
    if (!hasLocalTrigger && cleaned.split(' ').length < 4) {
      return; 
    }

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) return;

    await _classifyWithGemini(cleaned, sourceApp);
  }

  String? _preprocess(String raw) {
    final cleaned = raw.trim().toLowerCase();
    final words = cleaned.split(RegExp(r'\s+'));
    if (words.length < 2) return null;
    return words.length > 100 ? words.take(60).join(' ') : cleaned;
  }

  bool _shouldIgnoreMessage(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('http') || lower.contains('.com')) return true;
    if (RegExp(r'\.(pdf|apk|jpg|png|mp4)$').hasMatch(lower)) return true;
    return false;
  }

  // ─────────────────────────────────────────────────────────────────────
  // AI Classification
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _classifyWithGemini(String text, String sourceApp) async {
    debugPrint('SAFECHILD: calling Gemini for "$text"');
    try {
      final prompt = '''
Analyze text from a child's phone for toxicity or cyberbullying.
Languages: English, Malay, or Manglish slang (e.g. "ko bodoh", "pukimak").

Categories:
- "safe": Normal talk.
- "toxic": Insults, swearing, threats, or sexual content.

Return ONLY JSON:
{"category":"safe/toxic","confidence":0.0,"snippet":"only the offensive part"}

Text: "$text"
''';

      final response = await _geminiModel.generateContent([Content.text(prompt)]);
      final result = response.text;

      debugPrint('SAFECHILD: gemini response = $result');

      if (result != null) {
        _parseAndHandle(result, sourceApp, rawText: text);
      } else {
        debugPrint('SAFECHILD: gemini returned empty response');
      }
    } catch (e) {
      debugPrint('SAFECHILD: Gemini error — $e');
    }
  }

  void _parseAndHandle(String jsonText, String sourceApp, {required String rawText}) {
    try {
      final cleanedJson = jsonText.replaceAll('```json', '').replaceAll('```', '').trim();
      final map = jsonDecode(cleanedJson) as Map<String, dynamic>;
      
      final category = map['category'] ?? 'safe';
      final confidence = (map['confidence'] as num?)?.toDouble() ?? 0.0;
      final snippet = map['snippet'] ?? '';

      debugPrint('SAFECHILD: category=$category confidence=$confidence snippet="$snippet"');

      if (category == 'toxic' && confidence >= 0.65) {
        _handleHarmful(category, confidence, sourceApp, snippet.toString().isNotEmpty ? snippet : rawText);
      } else {
        debugPrint('SAFECHILD: safe or low confidence — not logged');
      }
    } catch (e) {
      debugPrint('SAFECHILD: Parse error — $e');
    }
  }

  void _handleHarmful(String category, double conf, String app, String content) {
    final lastHarmful = _lastHarmfulTime[app];
    if (lastHarmful != null && DateTime.now().difference(lastHarmful) < _harmfulCooldown) {
      return;
    }

    _lastHarmfulTime[app] = DateTime.now();
    
    _logIncident(
      summary: 'Toxic content in ${_friendlyAppName(app)}',
      description: content,
      source: app,
      confidence: conf,
      category: category,
      alert: conf >= 0.80,
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────

  String _friendlyAppName(String pkg) {
    if (pkg.contains('whatsapp'))  return 'WhatsApp';
    if (pkg.contains('chrome'))    return 'Chrome';
    if (pkg.contains('instagram')) return 'Instagram';
    if (pkg.contains('trill') || pkg.contains('tiktok')) return 'TikTok';
    if (pkg.contains('telegram'))  return 'Telegram';
    if (pkg.contains('youtube'))   return 'YouTube';
    if (pkg.contains('facebook')) {
      if (pkg.contains('orca')) return 'Messenger';
      return 'Facebook';
    }
    if (pkg.contains('twitter') || pkg.contains('x.com')) return 'X / Twitter';
    if (pkg.contains('snapchat'))  return 'Snapchat';
    if (pkg.contains('discord'))   return 'Discord';
    if (pkg.contains('reddit'))    return 'Reddit';
    
    final parts = pkg.split('.');
    return parts.isNotEmpty
        ? parts.last[0].toUpperCase() + parts.last.substring(1)
        : pkg;
  }

  Future<void> _logIncident({
    required String summary,
    required String source,
    required String description,
    required double confidence,
    required String category,
    required bool alert,
  }) async {
    if (_deviceId == null) return;
    try {
      await _db.collection('incidents').add({
        'device_id': _deviceId,
        'text_summary': summary,
        'description': description,
        'source': source,
        'confidence_score': confidence,
        'category': category,
        'detected_at': FieldValue.serverTimestamp(),
        'is_alert_send': alert,
        'is_reviewed': false,
      });
      debugPrint('SAFECHILD: Incident logged to Firestore ✓');
    } catch (e) {
      debugPrint('SAFECHILD: Firestore error — $e');
    }
  }
}