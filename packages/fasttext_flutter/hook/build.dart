// Copyright 2024 the fasttext_flutter authors. Apache-2.0 license.
// Build hook: compiles fastText C++ sources + our C wrapper into a shared lib.
// ignore_for_file: avoid_print, cascade_invocations

import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';
import 'package:logging/logging.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageName = input.packageName;
    final os = input.config.code.targetOS;

    // ── Gather all .cc sources from third_party/fasttext/ ──────────────────
    final srcDir = Directory.fromUri(
        input.packageRoot.resolve('src/third_party/fasttext/'));
    final fastTextSources = srcDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.cc'))
        .map((f) => 'src/third_party/fasttext/${f.uri.pathSegments.last}')
        .toList();

    // ── Compiler flags ──────────────────────────────────────────────────────
    final flags = <String>[
      '-std=c++17',
      '-Os',            // optimise for size (important on mobile)
      '-DNDEBUG',
      // Hide internal symbols on non-Windows
      if (os != OS.windows) '-fvisibility=hidden',
      // Needed on Android / Linux for math functions (sin, log, etc.)
      if (os == OS.android || os == OS.linux) '-lm',
      // Android-specific: ensure POSIX APIs (posix_memalign) are available.
      if (os == OS.android) '-D_POSIX_C_SOURCE=200809L',
    ];

    // Android: use the toolchain default `c++_shared` (do not use `c++_static`
    // for a shared library — it can produce an unloadable .so with missing
    // libc++ ABI symbols such as `_ZTISt12length_error` in fat apps).
    //
    // The host app must ship `libc++_shared.so` from the same NDK revision
    // (see SafeChild `android/app/build.gradle.kts`).

    final cbuilder = CBuilder.library(
      name: packageName,
      assetName: 'src/${packageName}_bindings_generated.dart',
      sources: [
        'src/fasttext_api.cpp',
        ...fastTextSources,
      ],
      includes: [
        'src',
        'src/third_party/fasttext',
      ],
      flags: flags,
      language: Language.cpp,
    );

    await cbuilder.run(
      input: input,
      output: output,
      logger: Logger('')
        ..level = Level.ALL
        ..onRecord.listen((record) => print(record.message)),
    );
  });
}
