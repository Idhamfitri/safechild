// lib/services/content_detection_service.dart
//
// Decision logic:
//   local prob < 0.20              -> SAFE  (no Gemini call)
//   local prob > 0.70              -> TOXIC (no Gemini call, log directly)
//   0.20 <= local prob <= 0.70     -> UNCERTAIN -> escalate to Gemini
//
// Model: assets/model_data.json (TF-IDF + Logistic Regression, 50k features)
// Gemini: gemini-2.5-flash-lite via firebase_ai
//
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/accessibility_event.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_utils.dart';

// ---------------------------------------------------------------------------
// Pure-Dart TF-IDF + Logistic Regression classifier
// ---------------------------------------------------------------------------

class _LRClassifier {
  final Map<String, int> vocab;
  final List<double> idf;
  final List<double> weights;
  final double intercept;

  _LRClassifier({
    required this.vocab,
    required this.idf,
    required this.weights,
    required this.intercept,
  });

  List<String> _ngrams(String text) {
    final words = text
        .toLowerCase()
        .split(RegExp(r'\W+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final out = <String>[];
    for (int i = 0; i < words.length; i++) {
      out.add(words[i]);
      if (i + 1 < words.length) {
        out.add('${words[i]} ${words[i + 1]}');
      }
    }
    return out;
  }

  // Returns sigmoid probability of the text being toxic (0.0–1.0).
  double score(String text) {
    final tokens = _ngrams(text);
    if (tokens.isEmpty) return 0.0;

    final counts = <int, int>{};
    for (final t in tokens) {
      final idx = vocab[t];
      if (idx != null) {
        counts[idx] = (counts[idx] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return 0.0;

    final tfidf = <int, double>{};
    for (final e in counts.entries) {
      tfidf[e.key] = e.value * idf[e.key];
    }

    var norm = 0.0;
    for (final v in tfidf.values) {
      norm += v * v;
    }
    if (norm == 0.0) return 0.0;
    final scale = 1.0 / sqrt(norm);

    var logit = intercept;
    for (final e in tfidf.entries) {
      logit += e.value * scale * weights[e.key];
    }

    return 1.0 / (1.0 + exp(-logit));
  }
}

_LRClassifier _parseModel(String jsonStr) {
  final data = jsonDecode(jsonStr) as Map<String, dynamic>;
  final rawVocab = data['vocabulary'] as Map<String, dynamic>;
  final vocab = rawVocab.map((k, v) => MapEntry(k, (v as num).toInt()));
  final idf = (data['idf'] as List).map((v) => (v as num).toDouble()).toList();
  final weights = (data['weights'] as List).map((v) => (v as num).toDouble()).toList();
  return _LRClassifier(
    vocab: vocab,
    idf: idf,
    weights: weights,
    intercept: (data['intercept'] as num).toDouble(),
  );
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class ContentDetectionService {
  final _db = FirebaseFirestore.instance;

  // Gemini model
  final _geminiModel = FirebaseAI.googleAI()
      .generativeModel(model: 'gemini-2.5-flash-lite');

  static StreamSubscription? _accessibilitySubscription;
  String? _deviceId;
  String? _childName;

  // Local classifier
  _LRClassifier? _classifier;

  // Confidence thresholds
  static const double _safeThreshold  = 0.20;
  static const double _toxicThreshold = 0.70;

  // Optimization state
  final Map<String, DateTime> _lastProcessed = {};
  static const _debounceDuration = Duration(seconds: 5);

  String? _lastTextProcessed;
  DateTime? _lastTextTime;

  final Map<String, DateTime> _lastHarmfulTime = {};
  static const _harmfulCooldown = Duration(seconds: 30);

  static const _monitoredPackages = {
    'com.whatsapp',
    'com.android.chrome',
    'com.instagram.android',
    'com.ss.android.ugc.trill',
    'org.telegram.messenger',
    'com.google.android.youtube',
    'com.facebook.katana',
    'com.facebook.orca',
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

  final List<AccessibilityEvent> _eventList = [];
  bool _isProcessing = false;

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  Future<void> start() async {
    if (_accessibilitySubscription != null) return;

    final isEnabled =
        await FlutterAccessibilityService.isAccessibilityPermissionEnabled();
    if (isEnabled != true) {
      debugPrint('SAFECHILD: Accessibility not granted. Aborting.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    if (_deviceId == null || _deviceId!.isEmpty) {
      debugPrint('SAFECHILD: device_id not found. Cannot start.');
      return;
    }

    try {
      final doc = await _db.collection('child_devices').doc(_deviceId).get();
      _childName = doc.data()?['full_name'] as String?;
    } catch (_) {}

    await _loadModel();
    await Future.delayed(const Duration(seconds: 2));

    _accessibilitySubscription =
        FlutterAccessibilityService.accessStream.listen(
      _onAccessibilityEvent,
      onError: (e) => debugPrint('SAFECHILD: stream error -- $e'),
    );

    debugPrint('SAFECHILD: started for $_deviceId '
        '(classifier=${_classifier != null ? "ready" : "FAILED"})');
  }

  Future<void> stop() async {
    try {
      await _accessibilitySubscription?.cancel();
    } catch (e) {
      debugPrint('SAFECHILD: stop error -- $e');
    } finally {
      _accessibilitySubscription = null;
      _eventList.clear();
      _classifier = null;
      debugPrint('SAFECHILD: service stopped.');
    }
  }

  // -------------------------------------------------------------------------
  // Model loading
  // -------------------------------------------------------------------------

  Future<void> _loadModel() async {
    debugPrint('SAFECHILD: loading model_data.json...');
    try {
      final jsonStr = await rootBundle.loadString('assets/model_data.json');
      _classifier = await compute(_parseModel, jsonStr);
      debugPrint('SAFECHILD: classifier ready '
          '(vocab=${_classifier!.vocab.length})');
    } catch (e, st) {
      _classifier = null;
      debugPrint('SAFECHILD: MODEL LOAD FAILED: $e\n$st');
    }
  }

  // -------------------------------------------------------------------------
  // Event queue
  // -------------------------------------------------------------------------

  void _onAccessibilityEvent(AccessibilityEvent event) {
    _eventList.add(event);
    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    while (_eventList.isNotEmpty) {
      final event = _eventList.removeAt(0);
      await Future.delayed(Duration.zero);
      await _handleQueuedEvent(event);
    }
    _isProcessing = false;
  }

  // -------------------------------------------------------------------------
  // Event handler
  // -------------------------------------------------------------------------

  Future<void> _handleQueuedEvent(AccessibilityEvent event) async {
    final sourceApp = event.packageName ?? 'unknown';
    if (!_monitoredPackages.any((pkg) => sourceApp.contains(pkg))) return;

    final rawText = await Future(() => _extractTextFromEvent(event));
    if (rawText == null || rawText.isEmpty) return;
    if (_isUIText(rawText)) return;

    final now = DateTime.now();
    if (_lastTextProcessed == rawText &&
        _lastTextTime != null &&
        now.difference(_lastTextTime!) < const Duration(seconds: 3)) {
      return;
    }
    final lastTime = _lastProcessed[sourceApp];
    if (lastTime != null && now.difference(lastTime) < _debounceDuration) {
      return;
    }

    _lastProcessed[sourceApp] = now;
    _lastTextProcessed = rawText;
    _lastTextTime = now;

    debugPrint('SAFECHILD: event from $sourceApp -> "$rawText"');
    await _processText(rawText, sourceApp);
  }

  // -------------------------------------------------------------------------
  // Text extraction
  // -------------------------------------------------------------------------

  String? _extractTextFromEvent(AccessibilityEvent event) {
    String? rawText;
    if (event.text != null &&
        event.text != 'null' &&
        event.text!.trim().isNotEmpty) {
      rawText = _cleanText(event.text!);
    }
    if ((rawText == null || rawText.isEmpty) && event.subNodes != null) {
      final subTexts = event.subNodes!
          .where((n) => n.text != null && n.text != 'null')
          .map((n) => _cleanText(n.text!))
          .where((t) => t.isNotEmpty && !_isUIText(t))
          .join(' ');
      if (subTexts.isNotEmpty) rawText = subTexts;
    }
    return rawText;
  }

  bool _isUIText(String text) {
    final lower = text.toLowerCase().trim();
    return lower.length < 2 || _uiPatterns.any((p) => lower == p);
  }

  String _cleanText(String raw) {
    final mTextMatches = RegExp(r'mText:\s*([^,}]+)')
        .allMatches(raw)
        .map((m) => m.group(1)?.trim() ?? '')
        .where((t) => t.isNotEmpty)
        .toList();
    if (mTextMatches.isNotEmpty) return mTextMatches.join(' ');
    return raw
        .replaceAll(RegExp(r'\[.*?\]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // -------------------------------------------------------------------------
  // Hybrid classification pipeline
  // -------------------------------------------------------------------------

  Future<void> _processText(String rawText, String sourceApp) async {
    final cleaned = _preprocess(rawText);
    if (cleaned == null || _shouldIgnoreMessage(cleaned)) return;

    if (_classifier == null) {
      debugPrint('SAFECHILD: classifier not ready -- skipping');
      return;
    }

    final localProb = _classifier!.score(cleaned);

    debugPrint('SAFECHILD: local prob=${localProb.toStringAsFixed(3)} '
        'for "$cleaned"');

    if (localProb < _safeThreshold) {
      debugPrint('SAFECHILD: SAFE (below $_safeThreshold) -- skipped');
      return;
    }

    if (localProb > _toxicThreshold) {
      debugPrint('SAFECHILD: TOXIC (above $_toxicThreshold) -- logging');
      _handleHarmful(localProb, 'local_lr', sourceApp, cleaned);
      return;
    }

    // Uncertain zone — send to Gemini
    debugPrint('SAFECHILD: UNCERTAIN (${localProb.toStringAsFixed(3)}) '
        '-- send to Gemini');
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

  // -------------------------------------------------------------------------
  // Gemini escalation 
  // -------------------------------------------------------------------------

  Future<void> _classifyWithGemini(String text, String sourceApp) async {
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.contains(ConnectivityResult.none)) {
      debugPrint('SAFECHILD: no connectivity -- Gemini skipped');
      return;
    }

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

      final response =
          await _geminiModel.generateContent([Content.text(prompt)]);
      final result = response.text;

      debugPrint('SAFECHILD: Gemini response = $result');

      if (result != null) {
        _parseGeminiResponse(result, sourceApp, rawText: text);
      }
    } catch (e) {
      debugPrint('SAFECHILD: Gemini error -- $e');
    }
  }

  void _parseGeminiResponse(
    String jsonText,
    String sourceApp, {
    required String rawText,
  }) {
    try {
      final cleaned =
          jsonText.replaceAll('```json', '').replaceAll('```', '').trim();
      final map = jsonDecode(cleaned) as Map<String, dynamic>;

      final category   = map['category'] as String? ?? 'safe';
      final confidence = (map['confidence'] as num?)?.toDouble() ?? 0.0;
      final snippet    = map['snippet'] as String? ?? '';

      debugPrint('SAFECHILD: Gemini -> category=$category '
          'confidence=$confidence snippet="$snippet"');

      if (category == 'toxic' && confidence >= 0.65) {
        _handleHarmful(
          confidence,
          'gemini',
          sourceApp,
          snippet.isNotEmpty ? snippet : rawText,
        );
      } else {
        debugPrint('SAFECHILD: Gemini says safe or low confidence -- skipped');
      }
    } catch (e) {
      debugPrint('SAFECHILD: Gemini parse error -- $e');
    }
  }

  // -------------------------------------------------------------------------
  // Incident handling
  // -------------------------------------------------------------------------

  void _handleHarmful(
      double prob, String detector, String app, String content) {
    final lastHarmful = _lastHarmfulTime[app];
    if (lastHarmful != null &&
        DateTime.now().difference(lastHarmful) < _harmfulCooldown) {
      return;
    }
    _lastHarmfulTime[app] = DateTime.now();
    _logIncident(
      summary: '[${_childName ?? 'Child'}] Toxic content in ${AppUtils.getFriendlyAppName(app)}',
      description: content,
      source: app,
      confidence: prob,
      category: 'toxic',
      alert: prob >= 0.80,
      detector: detector,
    );
  }

  Future<void> _logIncident({
    required String summary,
    required String source,
    required String description,
    required double confidence,
    required String category,
    required bool alert,
    required String detector,
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
        'detector': 'hybrid_$detector',
      });
      debugPrint('SAFECHILD: Incident logged (via $detector)');
    } catch (e) {
      debugPrint('SAFECHILD: Firestore error -- $e');
    }
  }
}
