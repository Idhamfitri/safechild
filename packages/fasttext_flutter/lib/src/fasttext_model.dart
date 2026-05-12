// Copyright 2024 the fasttext_flutter authors. Apache-2.0 license.

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'fasttext_exception.dart';
import 'fasttext_flutter_bindings_generated.dart';
import 'prediction.dart';

/// The internal model architecture of a loaded fastText model.
///
/// - [cbow] and [skipgram] are **unsupervised** word-vector models: they
///   support [FastTextModel.computeEmbedding] but NOT [FastTextModel.predict].
/// - [supervised] models support both [FastTextModel.predict] and
///   [FastTextModel.computeEmbedding].
enum FastTextModelType {
  /// Continuous Bag-of-Words — unsupervised word embedding model.
  cbow,

  /// Skip-gram — unsupervised word embedding model.
  skipgram,

  /// Supervised text classification model.
  supervised,

  /// Model type could not be determined.
  unknown;

  static FastTextModelType _fromCode(int code) => switch (code) {
        1 => FastTextModelType.cbow,
        2 => FastTextModelType.skipgram,
        3 => FastTextModelType.supervised,
        _ => FastTextModelType.unknown,
      };
}

/// A loaded fastText model.
///
/// Use [FastTextModel.load] or [FastTextModel.loadAsset] to create instances.
/// All inference methods run in a background [Isolate] so the UI thread is
/// never blocked.
///
/// Always call [close] when the model is no longer needed.
///
/// ## Supervised classification
///
/// ```dart
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
/// ## Unsupervised embedding + similarity
///
/// ```dart
/// final model = await FastTextModel.loadAsset('assets/model.ftz');
/// try {
///   final devVec  = await model.computeEmbedding('Flutter developer');
///   final appVec  = await model.computeEmbedding('Mobile app developer');
///   final sim = FastTextModel.cosineSimilarity(devVec, appVec);
///   print('Similarity: ${sim.toStringAsFixed(4)}'); // e.g. 0.9797
/// } finally {
///   model.close();
/// }
/// ```
class FastTextModel implements Finalizable {
  final Pointer<FastTextHandle> _handle;
  bool _closed = false;

  static final _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<FastTextHandle>)>>(
            ft_destroy)
        .cast<NativeFinalizerFunction>(),
  );

  FastTextModel._(this._handle) {
    _finalizer.attach(this, _handle.cast(), detach: this);
  }

  // ---------------------------------------------------------------------------
  // Factories
  // ---------------------------------------------------------------------------

  /// Loads a fastText model (`.bin` or `.ftz`) from an absolute file-system
  /// [path].
  ///
  /// Throws [FastTextException] if the model cannot be loaded.
  static Future<FastTextModel> load(String path) async {
    // Heavy native work runs in a background isolate.
    // We return the raw pointer address (int) because Pointer / Finalizable
    // objects cannot be sent across isolate boundaries.
    final addr = await Isolate.run(() => _loadInIsolate(path));
    return FastTextModel._(Pointer<FastTextHandle>.fromAddress(addr));
  }

  /// Loads a fastText model from a Flutter asset key, e.g.
  /// `'assets/model.ftz'`.
  ///
  /// The asset bytes are extracted to the app's temporary directory once so
  /// the native layer can read a real file path.
  ///
  /// Throws [FastTextException] if the model cannot be loaded.
  static Future<FastTextModel> loadAsset(String assetKey) async {
    final data = await rootBundle.load(assetKey);
    final bytes = data.buffer.asUint8List();
    final tmpDir = await getTemporaryDirectory();
    final file = File('${tmpDir.path}/${assetKey.split('/').last}');
    await file.writeAsBytes(bytes, flush: true);
    return load(file.path);
  }

  /// Runs in a background isolate — returns the raw native pointer address.
  static int _loadInIsolate(String path) {
    final handle = ft_create();
    if (handle == nullptr) {
      throw const FastTextException('Failed to allocate native model handle.');
    }
    const errLen = 512;
    final pathPtr = path.toNativeUtf8().cast<Char>();
    final errPtr = calloc<Char>(errLen);
    try {
      final rc = ft_load_model(handle, pathPtr, errPtr, errLen);
      if (rc != 0) {
        final msg = errPtr.cast<Utf8>().toDartString();
        ft_destroy(handle);
        throw FastTextException('Failed to load model: $msg');
      }
    } finally {
      calloc.free(pathPtr);
      calloc.free(errPtr);
    }
    return handle.address;
  }

  // ---------------------------------------------------------------------------
  // Model properties
  // ---------------------------------------------------------------------------

  /// Embedding dimension of the model (e.g. 10, 100, 300).
  int get dimension {
    _checkOpen();
    final d = ft_get_dimension(_handle);
    if (d < 0) throw const FastTextException('Model not loaded.');
    return d;
  }

  /// Number of output labels for supervised models; 0 for unsupervised.
  int get labelCount {
    _checkOpen();
    final n = ft_get_label_count(_handle);
    if (n < 0) throw const FastTextException('Model not loaded.');
    return n;
  }

  /// The internal model architecture ([FastTextModelType.cbow],
  /// [FastTextModelType.skipgram], or [FastTextModelType.supervised]).
  ///
  /// Check this before calling [predict] — it is only valid for
  /// [FastTextModelType.supervised] models.
  FastTextModelType get modelType {
    _checkOpen();
    return FastTextModelType._fromCode(ft_get_model_type(_handle));
  }

  /// Convenience shorthand for `modelType == FastTextModelType.supervised`.
  bool get isSupervised => modelType == FastTextModelType.supervised;

  // ---------------------------------------------------------------------------
  // Inference
  // ---------------------------------------------------------------------------

  /// Classifies [text] and returns the top-[k] predictions as a list of
  /// [FastTextPrediction] objects, ordered by descending probability.
  ///
  /// [k] is the maximum number of results (default: 1).
  /// [threshold] excludes results below this probability (default: 0.0).
  ///
  /// **Supervised models only.** Calling this on an unsupervised (cbow /
  /// skipgram) model throws a [FastTextException] with a clear message.
  /// Use [computeEmbedding] for unsupervised models.
  ///
  /// Runs in a background isolate — safe to `await` from the UI.
  ///
  /// Throws [FastTextException] on native errors.
  Future<List<FastTextPrediction>> predict(
    String text, {
    int k = 1,
    double threshold = 0.0,
  }) async {
    _checkOpen();
    if (!isSupervised) {
      throw FastTextException(
        'predict() requires a supervised model. '
        'This model is of type "${modelType.name}" (word-embedding). '
        'Use computeEmbedding() instead.',
      );
    }
    final addr = _handle.address;
    return Isolate.run(() => _predictSync(addr, text, k, threshold));
  }

  static List<FastTextPrediction> _predictSync(
      int addr, String text, int k, double threshold) {
    final handle = Pointer<FastTextHandle>.fromAddress(addr);
    const errLen = 512;
    final textPtr = text.toNativeUtf8().cast<Char>();
    final labelsPtr = calloc<Pointer<Char>>(k);
    final probsPtr = calloc<Float>(k);
    final countPtr = calloc<Int32>();
    final errPtr = calloc<Char>(errLen);
    try {
      final rc = ft_predict_k(handle, textPtr, k, threshold, labelsPtr,
          probsPtr, countPtr, errPtr, errLen);
      if (rc != 0) {
        throw FastTextException(
            'Prediction failed: ${errPtr.cast<Utf8>().toDartString()}');
      }
      final count = countPtr.value;
      final results = <FastTextPrediction>[];
      for (var i = 0; i < count; i++) {
        results.add(FastTextPrediction(
          label: labelsPtr[i].cast<Utf8>().toDartString(),
          probability: probsPtr[i],
        ));
      }
      ft_free_labels(labelsPtr, count);
      return results;
    } finally {
      calloc.free(textPtr);
      calloc.free(labelsPtr);
      calloc.free(probsPtr);
      calloc.free(countPtr);
      calloc.free(errPtr);
    }
  }

  /// Computes a dense embedding vector for [text] and returns it as a
  /// [Float32List] of length [dimension].
  ///
  /// Works for **all** model types (supervised, cbow, skipgram).
  ///
  /// > **Note:** Embeddings from `.ftz` quantized models are approximate
  /// > compared to the full `.bin` model. They are well-suited for cosine
  /// > similarity ranking but may differ slightly from the Python fasttext
  /// > library's output.
  ///
  /// Runs in a background isolate — safe to `await` from the UI.
  ///
  /// Throws [FastTextException] on native errors.
  Future<Float32List> computeEmbedding(String text) async {
    _checkOpen();
    final addr = _handle.address;
    final dim = dimension;
    return Isolate.run(() => _computeEmbeddingSync(addr, text, dim));
  }

  static Float32List _computeEmbeddingSync(int addr, String text, int dim) {
    final handle = Pointer<FastTextHandle>.fromAddress(addr);
    const errLen = 512;
    final textPtr = text.toNativeUtf8().cast<Char>();
    final outPtr = calloc<Float>(dim);
    final dimPtr = calloc<Int32>();
    final errPtr = calloc<Char>(errLen);
    try {
      final rc = ft_get_sentence_vector(
          handle, textPtr, outPtr, dimPtr, errPtr, errLen);
      if (rc != 0) {
        throw FastTextException(
            'computeEmbedding failed: ${errPtr.cast<Utf8>().toDartString()}');
      }
      final actualDim = dimPtr.value;
      return Float32List.fromList(List.generate(actualDim, (i) => outPtr[i]));
    } finally {
      calloc.free(textPtr);
      calloc.free(outPtr);
      calloc.free(dimPtr);
      calloc.free(errPtr);
    }
  }

  // ---------------------------------------------------------------------------
  // Static utilities
  // ---------------------------------------------------------------------------

  /// Computes the cosine similarity between two embedding vectors.
  ///
  /// Returns a value in the range [-1.0, 1.0]:
  /// - **1.0** — identical direction (semantically very similar)
  /// - **0.0** — orthogonal (unrelated)
  /// - **-1.0** — opposite direction
  ///
  /// Both [vectorA] and [vectorB] must have the same length.
  ///
  /// ```dart
  /// final a = await model.computeEmbedding('Flutter developer');
  /// final b = await model.computeEmbedding('Mobile app developer');
  /// final sim = FastTextModel.cosineSimilarity(a, b);
  /// print(sim.toStringAsFixed(4)); // e.g. 0.9797
  /// ```
  static double cosineSimilarity(List<double> vectorA, List<double> vectorB) {
    assert(vectorA.length == vectorB.length,
        'Vectors must have the same dimension.');
    var dot = 0.0, normA = 0.0, normB = 0.0;
    for (var i = 0; i < vectorA.length; i++) {
      dot += vectorA[i] * vectorB[i];
      normA += vectorA[i] * vectorA[i];
      normB += vectorB[i] * vectorB[i];
    }
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Closes the model and frees all native resources.
  ///
  /// After calling [close], all method calls will throw [FastTextException].
  /// Safe to call multiple times — subsequent calls are no-ops.
  void close() {
    if (_closed) return;
    _closed = true;
    _finalizer.detach(this);
    ft_destroy(_handle);
  }

  void _checkOpen() {
    if (_closed) {
      throw const FastTextException(
        'FastTextModel is closed. Load a new model with FastTextModel.load().',
      );
    }
  }
}
