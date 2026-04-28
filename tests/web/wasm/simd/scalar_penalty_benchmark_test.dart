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
    if (i % 2 == 0) {
      v128Array[i >> 1] = WasmF64x2.fromDoubles(
        i.toDouble(),
        (i + 1).toDouble(),
      );
    }
  }

  // 1. Verify correctness
  for (int i = 0; i < 16; i++) {
    Expect.equals(getF64(f64Array, i), getV128(v128Array, i));
  }
  print("Verification complete.");

  // 2. Run benchmarks
  print("Warming up...");
  for (int i = 0; i < 1000; i++) {
    getF64(f64Array, i % 16);
    getV128(v128Array, i % 16);
  }

  print("Starting Scalar Access (WasmArray<f64>) ($iterations iterations)...");
  var sum1 = 0.0;
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    sum1 += getF64(f64Array, i % 16);
  }
  sw.stop();
  final f64Time = sw.elapsedMicroseconds;
  print("F64 Access Time: ${f64Time / 1000} ms (sum: $sum1)");

  print("Starting Scalar Access (WasmArray<v128>) ($iterations iterations)...");
  var sum2 = 0.0;
  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    sum2 += getV128(v128Array, i % 16);
  }
  sw.stop();
  final v128Time = sw.elapsedMicroseconds;
  print("V128 Access Time: ${v128Time / 1000} ms (sum: $sum2)");

  print(
    "Scalar Penalty: ${(v128Time / f64Time).toStringAsFixed(2)}x (Higher = Slower)",
  );
}

@pragma("wasm:prefer-inline")
double getF64(WasmArray<WasmF64> array, int index) {
  return array.read(index);
}

@pragma("wasm:prefer-inline")
double getV128(WasmArray<WasmV128> array, int index) {
  final v = WasmF64x2(array[index >> 1]);
  return (index & 1 == 0)
      ? v.extractLane(0).toDouble()
      : v.extractLane(1).toDouble();
}
