// Copyright (c) 2025, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:expect/expect.dart';
import 'package:path/path.dart' as path;
import 'package:wasm_builder/wasm_builder.dart';

import 'util.dart';

Future main() async {
  if (!Platform.isLinux && !Platform.isMacOS) return;

  await withTempDir((String tempDir) async {
    final dartFilename = 'pkg/dart2wasm/benchmark/self_compile_benchmark.dart';

    final wasmFilename = path.join(tempDir, 'self_compile_benchmark.wasm');
    final wasmFile = File(wasmFilename);

    await run([
      Platform.executable,
      'compile',
      'wasm',
      '-O0',
      dartFilename,
      '-o',
      wasmFilename,
    ]);
    final wasmBytes = wasmFile.readAsBytesSync();
    Expect.listEquals(wasmBytes, readWrite(wasmBytes));
    // Temporary files will be deleted when returning to [withTempDir].
  });
}

Uint8List readWrite(Uint8List wasmBytes) {
  final deserializer = Deserializer(wasmBytes);
  final module = Module.deserialize(deserializer);

  final serializer = Serializer();
  module.serialize(serializer);
  return serializer.data;
}
