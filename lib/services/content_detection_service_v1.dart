import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fasttext_flutter/fasttext_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';
import 'package:flutter_accessibility_service/accessibility_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same pipeline as [ContentDetectionService], but toxic/safe scoring uses the
/// on-device `assets/safechild_fasttext.ftz` model (no Gemini, no network for
/// classification).
class ContentDetectionServiceV1 {
  final _db = FirebaseFirestore.instance;
  static StreamSubscription? _accessibilitySubscription;
  String? _deviceId;

  FastTextModel? _model;

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

  static const _modelAsset = 'assets/safechild_fasttext.ftz';

  /// Labels treated as non-toxic (after [FastTextPrediction.cleanLabel]).
  static const _safeLabels = {
    'safe',
    'neutral',
    'ok',
    'pos',
    'positive',
    '0',
    'non_toxic',
    'nontoxic',
    'not_toxic',
    'notoxic',
  };

  // ─────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────

  Future<void> start() async {
    if (_accessibilitySubscription != null) return;

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');

    if (_deviceId == null || _deviceId!.isEmpty) {
      debugPrint('SAFECHILD v1: device_id not found. Cannot start logging.');
      return;
    }

    await _ensureModelLoaded();

    await Future.delayed(const Duration(seconds: 2));

    _accessibilitySubscription = FlutterAccessibilityService.accessStream.listen(
      _onAccessibilityEvent,
      onError: (e) => debugPrint('SAFECHILD v1: stream error — $e'),
    );
    debugPrint('SAFECHILD v1: service started for $_deviceId ✓');
  }

  Future<void> _ensureModelLoaded() async {
    if (_model != null) return;
    try {
      _model = await FastTextModel.loadAsset(_modelAsset);
      debugPrint(
        'SAFECHILD v1: FastText loaded (${_model!.modelType}, '
        'supervised=${_model!.isSupervised})',
      );
    } on FastTextException catch (e) {
      debugPrint('SAFECHILD v1: FastText load failed — ${e.message}');
      _model = null;
    } catch (e) {
      debugPrint('SAFECHILD v1: FastText load error — $e');
      _model = null;
    }
  }

  Future<void> stop() async {
    try {
      if (_accessibilitySubscription != null) {
        await _accessibilitySubscription?.cancel();
      }
    } catch (e) {
      debugPrint('SAFECHILD v1: Warning - Accessibility stream de-activation error: $e');
    } finally {
      _accessibilitySubscription = null;
      _model?.close();
      _model = null;
      debugPrint('SAFECHILD v1: service stopped.');
    }
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

    debugPrint('SAFECHILD v1: event from $sourceApp → "$rawText"');

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

    debugPrint('SAFECHILD v1: processing "$cleaned" from $sourceApp');

    // 6. Local Keyword Pre-Filter
    final hasLocalTrigger = _localTriggers.any((word) => cleaned.contains(word));

    // Same efficiency rule as cloud version: only ML-check if keywords OR long enough
    if (!hasLocalTrigger && cleaned.split(' ').length < 4) {
      return;
    }

    await _ensureModelLoaded();
    if (_model == null || !_model!.isSupervised) {
      if (_model != null && !_model!.isSupervised) {
        debugPrint('SAFECHILD v1: model is not supervised — predict() unavailable');
      }
      return;
    }

    await _classifyWithFastText(cleaned, sourceApp);
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
  // FastText classification
  // ─────────────────────────────────────────────────────────────────────

  Future<void> _classifyWithFastText(String text, String sourceApp) async {
    final model = _model;
    if (model == null) return;

    debugPrint('SAFECHILD v1: FastText predict for "$text"');
    try {
      final results = await model.predict(text, k: 3);
      if (results.isEmpty) {
        debugPrint('SAFECHILD v1: FastText returned no predictions');
        return;
      }

      final top = results.first;
      debugPrint(
        'SAFECHILD v1: top label="${top.label}" clean="${top.cleanLabel}" '
        'p=${top.probability.toStringAsFixed(4)}',
      );

      final toxic = _resolveToxicFromPredictions(results);
      if (toxic == null) {
        debugPrint('SAFECHILD v1: no toxic label above threshold — not logged');
        return;
      }

      final category = toxic.$1;
      final confidence = toxic.$2;
      final snippet = toxic.$3;

      if (category == 'toxic' && confidence >= 0.65) {
        _handleHarmful(category, confidence, sourceApp, snippet.isNotEmpty ? snippet : text);
      } else {
        debugPrint('SAFECHILD v1: safe or low confidence — not logged');
      }
    } on FastTextException catch (e) {
      debugPrint('SAFECHILD v1: FastText predict error — ${e.message}');
    } catch (e) {
      debugPrint('SAFECHILD v1: FastText error — $e');
    }
  }

  /// Returns `(category, confidence, snippet)` when toxic wins, else null.
  (String, double, String)? _resolveToxicFromPredictions(List<FastTextPrediction> results) {
    const threshold = 0.65;

    for (final r in results) {
      final label = r.cleanLabel.toLowerCase().trim();
      if (_safeLabels.contains(label)) {
        continue;
      }
      if (_labelIndicatesToxic(label) && r.probability >= threshold) {
        return ('toxic', r.probability, r.cleanLabel);
      }
    }

    return null;
  }

  bool _labelIndicatesToxic(String cleanLabel) {
    final l = cleanLabel;
    if (l.contains('non-toxic') || l.contains('nontoxic') || l.contains('not_toxic')) {
      return false;
    }
    if (l == 'toxic' ||
        l == 'harmful' ||
        l == 'hate' ||
        l == 'bully' ||
        l == 'cyberbully' ||
        l == 'offensive' ||
        l == 'negative' ||
        l == 'unsafe' ||
        l == '1') {
      return true;
    }
    if (l.contains('toxic') || l.contains('bully') || l.contains('harmful')) {
      return true;
    }
    return false;
  }

  void _handleHarmful(String category, double conf, String app, String content) {
    final lastHarmful = _lastHarmfulTime[app];
    if (lastHarmful != null && DateTime.now().difference(lastHarmful) < _harmfulCooldown) {
      return;
    }

    _lastHarmfulTime[app] = DateTime.now();

    _logIncident(
      summary: 'Toxic content (FastText) in ${_friendlyAppName(app)}',
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
    if (pkg.contains('whatsapp')) return 'WhatsApp';
    if (pkg.contains('chrome')) return 'Chrome';
    if (pkg.contains('instagram')) return 'Instagram';
    if (pkg.contains('trill') || pkg.contains('tiktok')) return 'TikTok';
    if (pkg.contains('telegram')) return 'Telegram';
    if (pkg.contains('youtube')) return 'YouTube';
    if (pkg.contains('facebook')) {
      if (pkg.contains('orca')) return 'Messenger';
      return 'Facebook';
    }
    if (pkg.contains('twitter') || pkg.contains('x.com')) return 'X / Twitter';
    if (pkg.contains('snapchat')) return 'Snapchat';
    if (pkg.contains('discord')) return 'Discord';
    if (pkg.contains('reddit')) return 'Reddit';

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
        'detector': 'fasttext_v1',
        'detected_at': FieldValue.serverTimestamp(),
        'is_alert_send': alert,
        'is_reviewed': false,
      });
      debugPrint('SAFECHILD v1: Incident logged to Firestore ✓');
    } catch (e) {
      debugPrint('SAFECHILD v1: Firestore error — $e');
    }
  }
}
