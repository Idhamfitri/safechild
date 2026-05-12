// Copyright 2024 the fasttext_flutter authors. Apache-2.0 license.

/// A single prediction result returned by [FastTextModel.predict].
class FastTextPrediction {
  /// The raw label string as stored in the model, e.g. `'__label__en'`.
  final String label;

  /// Prediction probability in the range [0.0, 1.0].
  final double probability;

  const FastTextPrediction({required this.label, required this.probability});

  /// Returns the label with the default `__label__` prefix removed.
  ///
  /// For example, `'__label__en'` becomes `'en'`.
  String get cleanLabel {
    const prefix = '__label__';
    return label.startsWith(prefix) ? label.substring(prefix.length) : label;
  }

  @override
  String toString() =>
      'FastTextPrediction(label: $label, probability: ${probability.toStringAsFixed(4)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FastTextPrediction &&
          other.label == label &&
          other.probability == probability;

  @override
  int get hashCode => Object.hash(label, probability);
}
