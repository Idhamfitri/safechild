// Copyright 2024 the fasttext_flutter authors. Apache-2.0 license.

/// Exception thrown by [FastTextModel] on any native-level error.
class FastTextException implements Exception {
  /// Human-readable error message from the native layer.
  final String message;

  const FastTextException(this.message);

  @override
  String toString() => 'FastTextException: $message';
}
