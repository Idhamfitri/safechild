// Copyright 2024 the fasttext_flutter authors. Apache-2.0 license.

/// Flutter/Dart package for on-device fastText text classification and
/// sentence embeddings via Dart FFI.
///
/// ## Quick start — supervised classification
///
/// ```dart
/// import 'package:fasttext_flutter/fasttext_flutter.dart';
///
/// final model = await FastTextModel.loadAsset('assets/lid.176.ftz');
/// try {
///   final results = await model.predict('Hello, world!', k: 3);
///   for (final r in results) {
///     print('${r.cleanLabel}: ${(r.probability * 100).toStringAsFixed(1)}%');
///   }
/// } finally {
///   model.close();
/// }
/// ```
///
/// ## Quick start — sentence embedding + cosine similarity
///
/// ```dart
/// final model = await FastTextModel.loadAsset('assets/model.ftz');
/// try {
///   final a = await model.computeEmbedding('Flutter developer');
///   final b = await model.computeEmbedding('Mobile app developer');
///   final sim = FastTextModel.cosineSimilarity(a, b);
///   print(sim.toStringAsFixed(4)); // e.g. 0.9797
/// } finally {
///   model.close();
/// }
/// ```
library;

export 'src/fasttext_exception.dart' show FastTextException;
export 'src/fasttext_model.dart' show FastTextModel, FastTextModelType;
export 'src/prediction.dart' show FastTextPrediction;
