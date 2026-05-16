// lib/services/content_detection_service_v2.dart
// V2: Pure-Dart TF-IDF + Logistic Regression — no native library, fully offline.
// Model loaded from assets/model_data.json.
//
// Inference pipeline (matches sklearn TfidfVectorizer defaults):
//   1. Tokenise -> unigrams + bigrams
//   2. Raw term count * IDF  -> sparse TF-IDF vector
//   3. L2-normalise
//   4. dot(vector, weights) + intercept -> logit
//   5. sigmoid(logit) >= threshold  -> toxic
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/accessibility_event.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_utils.dart';

// ---------------------------------------------------------------------------
// Pure-Dart classifier
// ---------------------------------------------------------------------------

class _LRClassifier {
  final Map<String, int> vocab;
  final List<double> idf;
  final List<double> weights;
  final double intercept;
  final double threshold;

  _LRClassifier({
    required this.vocab,
    required this.idf,
    required this.weights,
    required this.intercept,
    required this.threshold,
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

// Top-level function required by compute()
_LRClassifier _parseModel(String jsonStr) {
  final data = jsonDecode(jsonStr) as Map<String, dynamic>;
  final meta = data['meta'] as Map<String, dynamic>;
  final rawVocab = data['vocabulary'] as Map<String, dynamic>;
  final vocab = rawVocab.map((k, v) => MapEntry(k, (v as num).toInt()));
  final idf = (data['idf'] as List).map((v) => (v as num).toDouble()).toList();
  final weights = (data['weights'] as List).map((v) => (v as num).toDouble()).toList();
  return _LRClassifier(
    vocab: vocab,
    idf: idf,
    weights: weights,
    intercept: (data['intercept'] as num).toDouble(),
    threshold: (meta['threshold'] as num).toDouble(),
  );
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class ContentDetectionServiceV2 {
  final _db = FirebaseFirestore.instance;
  static StreamSubscription? _accessibilitySubscription;
  String? _deviceId;

  _LRClassifier? _classifier;

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
      debugPrint('SAFECHILD_V2: Accessibility not granted. Aborting.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    if (_deviceId == null || _deviceId!.isEmpty) {
      debugPrint('SAFECHILD_V2: device_id not found. Cannot start.');
      return;
    }

    await _loadModel();
    await Future.delayed(const Duration(seconds: 2));

    _accessibilitySubscription =
        FlutterAccessibilityService.accessStream.listen(
      _onAccessibilityEvent,
      onError: (e) => debugPrint('SAFECHILD_V2: stream error -- $e'),
    );

    debugPrint('SAFECHILD_V2: started for $_deviceId '
        '(classifier=${_classifier != null ? "ready" : "FAILED"})');
  }

  Future<void> stop() async {
    try {
      await _accessibilitySubscription?.cancel();
    } catch (e) {
      debugPrint('SAFECHILD_V2: stop error -- $e');
    } finally {
      _accessibilitySubscription = null;
      _eventList.clear();
      _classifier = null;
      debugPrint('SAFECHILD_V2: service stopped.');
    }
  }

  // -------------------------------------------------------------------------
  // Model loading
  // -------------------------------------------------------------------------

  Future<void> _loadModel() async {
    debugPrint('SAFECHILD_V2: loading model_data.json...');
    try {
      final jsonStr = await rootBundle.loadString('assets/model_data.json');
      _classifier = await compute(_parseModel, jsonStr);
      debugPrint('SAFECHILD_V2: classifier ready '
          '(vocab=${_classifier!.vocab.length}, '
          'threshold=${_classifier!.threshold})');
    } catch (e, st) {
      _classifier = null;
      debugPrint('SAFECHILD_V2: MODEL LOAD FAILED: $e');
      debugPrint('$st');
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

    debugPrint('SAFECHILD_V2: event from $sourceApp -> "$rawText"');
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
  // Classification
  // -------------------------------------------------------------------------

  Future<void> _processText(String rawText, String sourceApp) async {
    final cleaned = _preprocess(rawText);
    if (cleaned == null || _shouldIgnoreMessage(cleaned)) return;

    if (_classifier == null) {
      debugPrint('SAFECHILD_V2: classifier not ready -- skipping');
      return;
    }

    final prob = _classifier!.score(cleaned);
    final toxic = prob >= _classifier!.threshold;

    debugPrint('SAFECHILD_V2: LR prob=${prob.toStringAsFixed(3)} '
        'toxic=$toxic "$cleaned"');

    if (toxic) {
      _handleHarmful(prob, sourceApp, cleaned);
    }
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
  // Incident handling
  // -------------------------------------------------------------------------

  void _handleHarmful(double prob, String app, String content) {
    final lastHarmful = _lastHarmfulTime[app];
    if (lastHarmful != null &&
        DateTime.now().difference(lastHarmful) < _harmfulCooldown) {
      return;
    }
    _lastHarmfulTime[app] = DateTime.now();
    _logIncident(
      summary: 'Toxic content in ${AppUtils.getFriendlyAppName(app)}',
      description: content,
      source: app,
      confidence: prob,
      category: 'toxic',
      alert: prob >= 0.80,
    );
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
        'detector': 'lr_dart_v2',
      });
      debugPrint('SAFECHILD_V2: Incident logged');
    } catch (e) {
      debugPrint('SAFECHILD_V2: Firestore error -- $e');
    }
  }
}
