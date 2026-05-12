<!--
  Copyright 2024 the fasttext_flutter authors. Apache-2.0 license.
-->

# fasttext_flutter

[![pub.dev](https://img.shields.io/pub/v/fasttext_flutter.svg)](https://pub.dev/packages/fasttext_flutter)
[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)

On-device text classification and sentence embeddings using [fastText](https://fasttext.cc) `.ftz` quantized models via Dart FFI — no internet, no server required.

---

> **⚠️ Platform Status**
>
> Only **Android** has been tested so far.
> The build infrastructure (native_toolchain_c hooks) is in place for other
> platforms but **has not been verified**. If you test on iOS, macOS, Linux,
> or Windows, please open a PR or report your results in the
> [issue tracker](https://github.com/FahadQasim283/fasttext_flutter/issues).
>
> **👋 Contributors welcome!** See [Contributing](#contributing) below.

---

## Platform support

| Platform | Status |
|---|---|
| Android (arm64-v8a, armeabi-v7a, x86_64) | ✅ **Verified** |
| iOS | 🔲 Untested — help wanted |
| macOS | 🔲 Untested — help wanted |
| Linux | 🔲 Untested — help wanted |
| Windows | 🔲 Untested — help wanted |

---

## Features

- Load `.ftz` (quantized) and `.bin` (full) fastText models
- `predict()` — top-k text classification for supervised models
- `computeEmbedding()` — dense sentence-vector embeddings (`Float32List`)
- `FastTextModel.cosineSimilarity()` — static cosine-similarity helper
- `FastTextModelType` — detect `supervised`, `cbow`, or `skipgram` at runtime
- Background-isolate inference — never blocks the UI thread
- Automatic memory cleanup via `NativeFinalizer` + explicit `close()`

---

## Getting started

### 1. Add the dependency

```yaml
dependencies:
  fasttext_flutter: ^0.1.1
```

### 2. Add your model as an asset

```yaml
flutter:
  assets:
    - assets/model.ftz
```

Download a pre-trained language-ID model (917 KB, 177 languages):
<https://fasttext.cc/docs/en/language-identification.html>

---

## Usage

### Load a model

```dart
import 'package:fasttext_flutter/fasttext_flutter.dart';

// From Flutter assets
final model = await FastTextModel.loadAsset('assets/lid.176.ftz');

// From an absolute file path
final model = await FastTextModel.load('/sdcard/downloads/model.ftz');
```

### Classify text (supervised models only)

```dart
final results = await model.predict('Bonjour le monde', k: 3);
print(results.first.cleanLabel);    // fr
print(results.first.probability);   // 0.9994...
```

### Compute sentence embeddings (all model types)

```dart
final vector = await model.computeEmbedding('Flutter developer');
// → Float32List of length model.dimension
```

### Cosine similarity

```dart
final a = await model.computeEmbedding('Flutter developer');
final b = await model.computeEmbedding('Mobile app developer');
final sim = FastTextModel.cosineSimilarity(a, b);
print(sim.toStringAsFixed(4)); // e.g. 0.9797
```

### Check model type

```dart
print(model.modelType);    // FastTextModelType.supervised / .cbow / .skipgram
print(model.isSupervised); // true for classification models
print(model.dimension);    // embedding dimension
print(model.labelCount);   // 0 for unsupervised models
```

### Close the model

```dart
model.close(); // frees native memory; safe to call multiple times
```

---

## FastTextPrediction

```dart
final r = results.first;
r.label       // raw label e.g. '__label__en'
r.cleanLabel  // stripped label e.g. 'en'
r.probability // double in [0.0, 1.0]
```

---

## Error handling

```dart
try {
  final model = await FastTextModel.load('/bad/path.ftz');
} on FastTextException catch (e) {
  print(e.message);
}
```

Calling `predict()` on an unsupervised model throws `FastTextException` with a
clear message directing you to `computeEmbedding()` instead.

---

## Performance notes

- `.ftz` quantized models are 10–100× smaller than `.bin` and nearly as accurate.
- All inference runs in `Isolate.run()` — the UI thread is never blocked.
- Load the model once and reuse it across requests.

---

## Contributing

**This package needs your help to support more platforms!**

Only Android has been tested so far. If you can verify (or fix) any of these:

- **iOS** — swipe `hook/build.dart` flags and test on Simulator + device
- **macOS** — test with `flutter run -d macos` from the `example/` folder
- **Linux** — test with `flutter run -d linux`
- **Windows** — test with `flutter run -d windows`

Please open an issue with your results or a PR with fixes at:
<https://github.com/FahadQasim283/fasttext_flutter>

Every contribution — bug reports, test results, docs fixes — is welcome.

---

## License

Apache-2.0. See [LICENSE](LICENSE).

Bundled fastText C++ sources: © Facebook, Inc., MIT license.
