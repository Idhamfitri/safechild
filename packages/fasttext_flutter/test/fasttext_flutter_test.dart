// Copyright 2024 the fasttext_flutter authors. Apache-2.0 license.

import 'dart:io';
import 'dart:typed_data';

import 'package:fasttext_flutter/fasttext_flutter.dart';
import 'package:test/test.dart';

/// To run inference tests, set FT_MODEL_PATH to a local .ftz file:
///   Windows: $env:FT_MODEL_PATH="C:\path\to\model.ftz"; dart test
///   Linux/macOS: FT_MODEL_PATH=/path/to/model.ftz dart test
void main() {
  final modelPath = Platform.environment['FT_MODEL_PATH'];
  final hasModel = modelPath != null && File(modelPath).existsSync();

  // ---------------------------------------------------------------------------
  // FastTextException
  // ---------------------------------------------------------------------------
  group('FastTextException', () {
    test('toString includes class name and message', () {
      const e = FastTextException('test error');
      expect(e.toString(), contains('FastTextException'));
      expect(e.toString(), contains('test error'));
    });
  });

  // ---------------------------------------------------------------------------
  // FastTextPrediction
  // ---------------------------------------------------------------------------
  group('FastTextPrediction', () {
    test('cleanLabel strips __label__ prefix', () {
      const p = FastTextPrediction(label: '__label__en', probability: 0.99);
      expect(p.cleanLabel, equals('en'));
    });

    test('cleanLabel is unchanged when prefix absent', () {
      const p = FastTextPrediction(label: 'my_label', probability: 0.5);
      expect(p.cleanLabel, equals('my_label'));
    });

    test('equality', () {
      const a = FastTextPrediction(label: '__label__en', probability: 0.99);
      const b = FastTextPrediction(label: '__label__en', probability: 0.99);
      expect(a, equals(b));
    });

    test('toString includes label and probability', () {
      const p = FastTextPrediction(label: '__label__fr', probability: 0.8);
      expect(p.toString(), contains('__label__fr'));
      expect(p.toString(), contains('0.8'));
    });
  });

  // ---------------------------------------------------------------------------
  // FastTextModel.cosineSimilarity
  // ---------------------------------------------------------------------------
  group('FastTextModel.cosineSimilarity', () {
    test('identical vectors give 1.0', () {
      final v = [1.0, 2.0, 3.0];
      expect(FastTextModel.cosineSimilarity(v, v), closeTo(1.0, 1e-6));
    });

    test('orthogonal vectors give 0.0', () {
      expect(
        FastTextModel.cosineSimilarity([1.0, 0.0], [0.0, 1.0]),
        closeTo(0.0, 1e-6),
      );
    });

    test('opposite vectors give -1.0', () {
      expect(
        FastTextModel.cosineSimilarity([1.0, 0.0], [-1.0, 0.0]),
        closeTo(-1.0, 1e-6),
      );
    });

    test('zero vector returns 0.0 without throwing', () {
      expect(
        FastTextModel.cosineSimilarity([0.0, 0.0], [1.0, 2.0]),
        equals(0.0),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // FastTextModel — error handling
  // ---------------------------------------------------------------------------
  group('FastTextModel — error cases', () {
    test('load throws FastTextException for non-existent path', () {
      expect(
        () => FastTextModel.load('/nonexistent/path/model.ftz'),
        throwsA(isA<FastTextException>()),
      );
    });

    test('predict throws FastTextException on closed model', () async {
      if (!hasModel) return;
      final model = await FastTextModel.load(modelPath);
      model.close();
      expect(
        () async => await model.predict('hello'),
        throwsA(isA<FastTextException>()),
      );
    });

    test('computeEmbedding throws FastTextException on closed model', () async {
      if (!hasModel) return;
      final model = await FastTextModel.load(modelPath);
      model.close();
      expect(
        () async => await model.computeEmbedding('hello'),
        throwsA(isA<FastTextException>()),
      );
    });

    test('close() is idempotent (safe to call twice)', () async {
      if (!hasModel) return;
      final model = await FastTextModel.load(modelPath);
      model.close();
      expect(() => model.close(), returnsNormally);
    });
  });

  // ---------------------------------------------------------------------------
  // FastTextModel — inference (requires FT_MODEL_PATH)
  // ---------------------------------------------------------------------------
  group('FastTextModel — inference', () {
    late FastTextModel model;

    setUpAll(() async {
      if (!hasModel) return;
      model = await FastTextModel.load(modelPath);
    });

    tearDownAll(() {
      if (hasModel) model.close();
    });

    test('dimension > 0', () {
      if (!hasModel) return;
      expect(model.dimension, greaterThan(0));
    });

    test('modelType is not unknown', () {
      if (!hasModel) return;
      expect(model.modelType, isNot(FastTextModelType.unknown));
    });

    test('computeEmbedding returns Float32List with length == dimension',
        () async {
      if (!hasModel) return;
      final vec = await model.computeEmbedding('Hello world');
      expect(vec, isA<Float32List>());
      expect(vec.length, equals(model.dimension));
    });

    test('computeEmbedding returns non-zero vector', () async {
      if (!hasModel) return;
      final vec = await model.computeEmbedding('Hello world');
      final norm = vec.fold<double>(0.0, (s, v) => s + v * v);
      expect(norm, greaterThan(0.0));
    });

    test('cosineSimilarity of similar texts is high', () async {
      if (!hasModel) return;
      final a = await model.computeEmbedding('Flutter developer');
      final b = await model.computeEmbedding('Mobile app developer');
      expect(FastTextModel.cosineSimilarity(a, b), greaterThan(0.8));
    });

    // supervised-only tests
    test('predict(k=1) returns 1 result for supervised model', () async {
      if (!hasModel || !model.isSupervised) return;
      final results = await model.predict('Hello world', k: 1);
      expect(results.length, equals(1));
    });

    test('predict(k=5) returns at most 5 results', () async {
      if (!hasModel || !model.isSupervised) return;
      final results = await model.predict('Hello world', k: 5);
      expect(results.length, inInclusiveRange(1, 5));
    });

    test('predict labels start with __label__', () async {
      if (!hasModel || !model.isSupervised) return;
      final results = await model.predict('Hello world', k: 3);
      for (final r in results) {
        expect(r.label, startsWith('__label__'));
      }
    });

    test('predict probabilities are in [0, 1]', () async {
      if (!hasModel || !model.isSupervised) return;
      final results = await model.predict('Hello world', k: 3);
      for (final r in results) {
        expect(r.probability, inInclusiveRange(0.0, 1.0));
      }
    });

    test('predict throws for unsupervised model', () {
      if (!hasModel || model.isSupervised) return;
      expect(
        () async => await model.predict('hello'),
        throwsA(isA<FastTextException>()),
      );
    });
  });
}
