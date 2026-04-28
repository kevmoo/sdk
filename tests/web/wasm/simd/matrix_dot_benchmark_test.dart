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
  final a = WasmF64x2.fromDoubles(2.0, 3.0);
  final b = WasmF64x2.fromDoubles(4.0, 5.0);

  // 1. Verify correctness
  final expected = 2.0 * 4.0 + 3.0 * 5.0; // 8 + 15 = 23.0
  final scalar = dotScalar(2.0, 3.0, 4.0, 5.0);
  final dartSimd = dotDartSimd(a, b);
  final macroSimd = a.dotProduct(b).toDouble();

  Expect.approxEquals(expected, scalar);
  Expect.approxEquals(expected, dartSimd);
  Expect.approxEquals(expected, macroSimd);
  print("Verification complete.");

  // 2. Run benchmarks
  print("Warming up...");
  for (int i = 0; i < 1000; i++) {
    dotScalar(2.0, 3.0, 4.0, 5.0);
    dotDartSimd(a, b);
    a.dotProduct(b);
  }

  print("Starting Scalar Dot Benchmark ($iterations iterations)...");
  final sw = Stopwatch()..start();
  var sum1 = 0.0;
  for (int i = 0; i < iterations; i++) {
    sum1 += dotScalar(2.0, 3.0, 4.0, 5.0);
  }
  sw.stop();
  final scalarTime = sw.elapsedMicroseconds;
  print("Scalar Time: ${scalarTime / 1000} ms (sum: $sum1)");

  print("Starting Dart SIMD Dot Benchmark ($iterations iterations)...");
  sw
    ..reset()
    ..start();
  var sum2 = 0.0;
  for (int i = 0; i < iterations; i++) {
    sum2 += dotDartSimd(a, b);
  }
  sw.stop();
  final dartSimdTime = sw.elapsedMicroseconds;
  print("Dart SIMD Time: ${dartSimdTime / 1000} ms (sum: $sum2)");

  print("Starting Macro-Intrinsic Dot Benchmark ($iterations iterations)...");
  sw
    ..reset()
    ..start();
  var sum3 = 0.0;
  for (int i = 0; i < iterations; i++) {
    sum3 += a.dotProduct(b).toDouble();
  }
  sw.stop();
  final macroSimdTime = sw.elapsedMicroseconds;
  print("Macro SIMD Time: ${macroSimdTime / 1000} ms (sum: $sum3)");

  print(
    "Speedup (Macro vs Scalar): ${(scalarTime / macroSimdTime).toStringAsFixed(2)}x",
  );
  print(
    "Speedup (Macro vs Dart SIMD): ${(dartSimdTime / macroSimdTime).toStringAsFixed(2)}x",
  );
}

@pragma("wasm:prefer-inline")
double dotScalar(double ax, double ay, double bx, double by) {
  return ax * bx + ay * by;
}

@pragma("wasm:prefer-inline")
double dotDartSimd(WasmF64x2 a, WasmF64x2 b) {
  final mul = a * b;
  return mul.extractLane(0).toDouble() + mul.extractLane(1).toDouble();
}
