// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

final dartAotExecutable = Uri.parse(
  Platform.resolvedExecutable,
).resolve('dartaotruntime').toFilePath();
final dart2wasmSnapshot = Uri.parse(
  Platform.resolvedExecutable,
).resolve('snapshots/dart2wasm_product.snapshot').toFilePath();
final wasmOptExecutable = Uri.parse(
  Platform.resolvedExecutable,
).resolve('utils/wasm-opt').toFilePath();
final platformDill = Uri.parse(
  Platform.resolvedExecutable,
).resolve('../lib/_internal/dart2wasm_platform.dill').toFilePath();
final standalonePlatformDill = Uri.parse(
  Platform.resolvedExecutable,
).resolve('../lib/_internal/dart2wasm_standalone_platform.dill').toFilePath();
final jsCompatibilityPlatformDill = Uri.parse(Platform.resolvedExecutable)
    .resolve('../lib/_internal/dart2wasm_js_compatibility_platform.dill')
    .toFilePath();

/// Environment variables to force compile_benchmark to use the Bazel-built SDK.
Map<String, String> get compileBenchmarkEnvironment {
  return {
    'DART_VM': Platform.resolvedExecutable,
    'DART_AOT_RUNTIME': dartAotExecutable,
    'DART2WASM_AOT_SNAPSHOT': dart2wasmSnapshot,
    'DART2WASM_PLATFORM': platformDill,
    'DART2WASM_STANDALONE_PLATFORM': standalonePlatformDill,
    'DART2WASM_JS_COMPATIBILITY_PLATFORM': jsCompatibilityPlatformDill,
    'BINARYEN': wasmOptExecutable,
  };
}

Future<void> run(
  List<String> command, {
  bool throwOutputOnFailure = false,
}) async {
  final args = command.skip(1).toList();
  if (command.first == Platform.executable && Platform.packageConfig != null) {
    final packageConfigPath = Uri.parse(Platform.packageConfig!).toFilePath();
    final packagesFlag = '--packages=$packageConfigPath';
    if (!args.any((arg) => arg.startsWith('--packages='))) {
      if (args.length >= 2 &&
          args[0] == 'compile' &&
          (args[1] == 'wasm' || args[1] == 'js')) {
        args.insert(2, packagesFlag);
      } else if (args.isNotEmpty && (args[0] == 'run' || args[0] == 'test')) {
        args.insert(1, packagesFlag);
      } else {
        args.insert(0, packagesFlag);
      }
    }
  }
  print('Running: ${command.first} ${args.join(' ')}');
  final result = await Process.run(command.first, args);
  if (result.exitCode != 0) {
    if (throwOutputOnFailure) {
      throw '${result.stdout}\n${result.stderr}';
    }

    print('-> Failed with exit code ${result.exitCode}');
    print('-> stdout:\n${result.stdout}');
    print('-> stderr:\n${result.stderr}');
    throw 'Subprocess failed';
  }
}

Future withTempDir(Future Function(String directory) fun) async {
  final dir = Directory.systemTemp.createTempSync('dart2wasm_self_compile');
  try {
    print('Running with temporary directory: ${dir.path}');
    return await fun(dir.path);
  } finally {
    if (!keepTemporaryDirectory) {
      dir.deleteSync(recursive: true);
    }
  }
}

final bool keepTemporaryDirectory =
    (Platform.environment['KEEP_TEMPORARY_DIRECTORIES'] ?? 'false') != 'false';
