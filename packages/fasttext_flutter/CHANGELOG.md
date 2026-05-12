## 0.1.2
  implement native build hook and FastTextModel wrapper for model inference

## 0.1.0


- Initial release.
- **Load** `.ftz` (quantized) and `.bin` (full) fastText models from the file system or Flutter assets.
- **`predict(text, {k, threshold})`** — top-k text classification for supervised models, returns `List<FastTextPrediction>`.
- **`computeEmbedding(text)`** — dense sentence-vector embeddings as `Float32List`, works for all model types.
- **`FastTextModel.cosineSimilarity(a, b)`** — static cosine-similarity helper.
- **`FastTextModelType`** enum — detect whether the model is `supervised`, `cbow`, or `skipgram` at runtime.
- All inference runs in a background `Isolate` — the Flutter UI thread is never blocked.
- `NativeFinalizer`-based automatic memory management with explicit `close()` for deterministic cleanup.
- Platform support: Android (arm64, arm, x86_64), iOS, macOS, Linux, Windows.
- fastText C++ library compiled from source via `native_toolchain_c` build hooks — no pre-built binaries.
