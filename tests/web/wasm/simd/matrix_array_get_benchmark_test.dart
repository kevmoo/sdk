// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// dart2wasmOptions=--extra-compiler-option=--enable-experimental-wasm-interop

// ignore: import_internal_library
import 'dart:_wasm';
import 'dart:typed_data';

import 'package:expect/expect.dart';

const int iterations = 10000000;

void main() {
  final f64Array = WasmArray<WasmF64>(16);
  final v128Array = WasmArray<WasmV128>(8);

  for (int i = 0; i < 16; i++) {
    f64Array.write(i, i.toDouble());
  }
  for (int i = 0; i < 8; i++) {
    v128Array[i] = WasmF64x2.fromDoubles(i * 2.0, i * 2.0 + 1.0);
  }

  // 1. Verify correctness
  final v1 = loadFromF64(f64Array, 0);
  final v2 = loadFromV128(v128Array, 0);
  Expect.approxEquals(
    v1.extractLane(0).toDouble(),
    v2.extractLane(0).toDouble(),
  );
  Expect.approxEquals(
    v1.extractLane(1).toDouble(),
    v2.extractLane(1).toDouble(),
  );
  print("Verification complete.");

  // 2. Run benchmarks
  print("Warming up...");
  for (int i = 0; i < 1000; i++) {
    loadFromF64(f64Array, 0);
    loadFromV128(v128Array, 0);
  }

  print(
    "Starting WasmArray<WasmF64> Pure SIMD Benchmark ($iterations iterations)...",
  );
  var vSum1 = WasmF64x2.splat(WasmF64.fromDouble(0.0));
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    vSum1 = vSum1 + loadFromF64(f64Array, 0);
  }
  sw.stop();
  final f64Time = sw.elapsedMicroseconds;
  print(
    "F64 Load Time: ${f64Time / 1000} ms (sum: ${vSum1.extractLane(0).toDouble()})",
  );

  print(
    "Starting WasmArray<WasmV128> Pure SIMD Benchmark ($iterations iterations)...",
  );
  var vSum2 = WasmF64x2.splat(WasmF64.fromDouble(0.0));
  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    vSum2 = vSum2 + loadFromV128(v128Array, 0);
  }
  sw.stop();
  final v128Time = sw.elapsedMicroseconds;
  print(
    "V128 Load Time: ${v128Time / 1000} ms (sum: ${vSum2.extractLane(0).toDouble()})",
  );

  print("Speedup: ${(f64Time / v128Time).toStringAsFixed(2)}x");
}

@pragma("wasm:prefer-inline")
WasmF64x2 loadFromF64(WasmArray<WasmF64> array, int index) {
  // Loading 2 elements and packing into v128
  return WasmF64x2.fromDoubles(array.read(index), array.read(index + 1));
}

@pragma("wasm:prefer-inline")
WasmF64x2 loadFromV128(WasmArray<WasmV128> array, int index) {
  // Single array.get instruction
  return WasmF64x2(array[index]);
}
