// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// dart2wasmOptions=--extra-compiler-option=--enable-experimental-wasm-interop

// ignore: import_internal_library
import 'dart:_wasm';
import 'dart:typed_data';

import 'package:expect/expect.dart';

const int iterations = 1000000;

void main() {
  final a = WasmArray<WasmV128>(8);
  final b = WasmArray<WasmV128>(8);
  final outDart = WasmArray<WasmV128>(8);
  final outMacro = WasmArray<WasmV128>(8);

  final aScalar = Float64List(16);
  final bScalar = Float64List(16);
  final outScalar = Float64List(16);

  for (int i = 0; i < 8; i++) {
    final v = WasmF64x2.fromDoubles(i.toDouble(), (i + 0.5).toDouble());
    a[i] = v;
    b[i] = v;
    aScalar[i * 2] = i.toDouble();
    aScalar[i * 2 + 1] = (i + 0.5).toDouble();
    bScalar[i * 2] = i.toDouble();
    bScalar[i * 2 + 1] = (i + 0.5).toDouble();
  }

  multiplyScalar(aScalar, bScalar, outScalar);
  multiplyDartSimdFixed(a, b, outDart);
  WasmSIMD.matrix4Multiply(a, b, outMacro);

  for (int i = 0; i < 8; i++) {
    final vDart0 = WasmF64x2(outDart[i]).extractLane(0).toDouble();
    final vDart1 = WasmF64x2(outDart[i]).extractLane(1).toDouble();
    final vMacro0 = WasmF64x2(outMacro[i]).extractLane(0).toDouble();
    final vMacro1 = WasmF64x2(outMacro[i]).extractLane(1).toDouble();

    Expect.approxEquals(outScalar[i * 2], vDart0);
    Expect.approxEquals(outScalar[i * 2 + 1], vDart1);
    Expect.approxEquals(outScalar[i * 2], vMacro0);
    Expect.approxEquals(outScalar[i * 2 + 1], vMacro1);
  }
  print("Verification complete.");

  // 2. Run benchmarks
  print("Warming up...");
  for (int i = 0; i < 1000; i++) {
    multiplyScalar(aScalar, bScalar, outScalar);
    multiplyDartSimdFixed(a, b, outDart);
    WasmSIMD.matrix4Multiply(a, b, outMacro);
  }

  print("Starting Scalar Multiply Benchmark ($iterations iterations)...");
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    multiplyScalar(aScalar, bScalar, outScalar);
  }
  sw.stop();
  final scalarTime = sw.elapsedMicroseconds;
  print("Scalar Time: ${scalarTime / 1000} ms");

  print("Starting Dart SIMD Multiply Benchmark ($iterations iterations)...");
  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    multiplyDartSimdFixed(a, b, outDart);
  }
  sw.stop();
  final dartSimdTime = sw.elapsedMicroseconds;
  print("Dart SIMD Time: ${dartSimdTime / 1000} ms");

  print(
    "Starting Macro-Intrinsic Multiply Benchmark ($iterations iterations)...",
  );
  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    WasmSIMD.matrix4Multiply(a, b, outMacro);
  }
  sw.stop();
  final macroSimdTime = sw.elapsedMicroseconds;
  print("Macro SIMD Time: ${macroSimdTime / 1000} ms");

  print(
    "Speedup (Macro vs Scalar): ${(scalarTime / macroSimdTime).toStringAsFixed(2)}x",
  );
  print(
    "Speedup (Macro vs Dart SIMD): ${(dartSimdTime / macroSimdTime).toStringAsFixed(2)}x",
  );
}

@pragma("wasm:prefer-inline")
void multiplyScalar(Float64List a, Float64List b, Float64List out) {
  for (int i = 0; i < 4; i++) {
    // For each column of B
    for (int j = 0; j < 4; j++) {
      // For each row of A
      double sum = 0.0;
      for (int k = 0; k < 4; k++) {
        sum += a[k * 4 + j] * b[i * 4 + k];
      }
      out[i * 4 + j] = sum;
    }
  }
}

@pragma("wasm:prefer-inline")
void multiplyDartSimd(
  WasmArray<WasmV128> a,
  WasmArray<WasmV128> b,
  WasmArray<WasmV128> out,
) {
  // Column-major 4x4 multiply using SIMD primitives in Dart
  for (int j = 0; j < 4; j++) {
    final bl = WasmF64x2(b[j * 2]);
    final bh = WasmF64x2(b[j * 2 + 1]);

    for (int part = 0; j < 2; j++) {
      // This was a typo in my mental draft, fixed below
    }
  }
}

// Let me write a proper SIMD multiply in Dart for comparison
void multiplyDartSimdFixed(
  WasmArray<WasmV128> a,
  WasmArray<WasmV128> b,
  WasmArray<WasmV128> out,
) {
  final al0 = WasmF64x2(a[0]);
  final ah0 = WasmF64x2(a[1]);
  final al1 = WasmF64x2(a[2]);
  final ah1 = WasmF64x2(a[3]);
  final al2 = WasmF64x2(a[4]);
  final ah2 = WasmF64x2(a[5]);
  final al3 = WasmF64x2(a[6]);
  final ah3 = WasmF64x2(a[7]);

  for (int j = 0; j < 4; j++) {
    final bl = WasmF64x2(b[j * 2]);
    final bh = WasmF64x2(b[j * 2 + 1]);

    final b0 = WasmF64x2.splat(bl.extractLane(0));
    final b1 = WasmF64x2.splat(bl.extractLane(1));
    final b2 = WasmF64x2.splat(bh.extractLane(0));
    final b3 = WasmF64x2.splat(bh.extractLane(1));

    out[j * 2] = (al0 * b0) + (al1 * b1) + (al2 * b2) + (al3 * b3);
    out[j * 2 + 1] = (ah0 * b0) + (ah1 * b1) + (ah2 * b2) + (ah3 * b3);
  }
}
