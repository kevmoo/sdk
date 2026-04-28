// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// dart2wasmOptions=--extra-compiler-option=--enable-experimental-wasm-interop

// ignore: import_internal_library
import 'dart:_wasm';
import 'dart:typed_data';

import 'package:expect/expect.dart';

const int numPoints = 1000;
const int iterations = 10000;

void main() {
  final matrix = WasmArray<WasmV128>(8);
  final points = WasmArray<WasmV128>(numPoints * 2);
  final outDart = WasmArray<WasmV128>(numPoints * 2);
  final outMacro = WasmArray<WasmV128>(numPoints * 2);

  // Initialize identity-ish matrix and some points
  for (int i = 0; i < 4; i++) {
    matrix[i * 2] = WasmF64x2.fromDoubles(1.0, 0.0);
    matrix[i * 2 + 1] = WasmF64x2.fromDoubles(0.0, 1.0);
  }
  for (int i = 0; i < numPoints * 2; i++) {
    points[i] = WasmF64x2.fromDoubles(i.toDouble(), (i + 0.5).toDouble());
  }

  // 1. Verify correctness
  transformDart(points, matrix, outDart);
  WasmSIMD.transformPoints(points, matrix, outMacro);

  for (int i = 0; i < numPoints * 2; i++) {
    final vDart = WasmF64x2(outDart[i]);
    final vMacro = WasmF64x2(outMacro[i]);
    Expect.approxEquals(
      vDart.extractLane(0).toDouble(),
      vMacro.extractLane(0).toDouble(),
    );
    Expect.approxEquals(
      vDart.extractLane(1).toDouble(),
      vMacro.extractLane(1).toDouble(),
    );
  }
  print("Verification complete.");

  // 2. Run benchmarks
  print("Warming up...");
  for (int i = 0; i < 100; i++) {
    transformDart(points, matrix, outDart);
    WasmSIMD.transformPoints(points, matrix, outMacro);
  }

  print(
    "Starting Dart SIMD Transform ($numPoints points, $iterations iterations)...",
  );
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    transformDart(points, matrix, outDart);
  }
  sw.stop();
  final dartTime = sw.elapsedMicroseconds;
  print("Dart Time: ${dartTime / 1000} ms");

  print(
    "Starting Macro-Intrinsic Transform ($numPoints points, $iterations iterations)...",
  );
  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    WasmSIMD.transformPoints(points, matrix, outMacro);
  }
  sw.stop();
  final macroTime = sw.elapsedMicroseconds;
  print("Macro Time: ${macroTime / 1000} ms");

  print("Speedup: ${(dartTime / macroTime).toStringAsFixed(2)}x");
}

@pragma("wasm:prefer-inline")
void transformDart(
  WasmArray<WasmV128> points,
  WasmArray<WasmV128> matrix,
  WasmArray<WasmV128> out,
) {
  final ml0 = WasmF64x2(matrix[0]);
  final mh0 = WasmF64x2(matrix[1]);
  final ml1 = WasmF64x2(matrix[2]);
  final mh1 = WasmF64x2(matrix[3]);
  final ml2 = WasmF64x2(matrix[4]);
  final mh2 = WasmF64x2(matrix[5]);
  final ml3 = WasmF64x2(matrix[6]);
  final mh3 = WasmF64x2(matrix[7]);

  final int len = points.length;
  for (int i = 0; i < len; i += 2) {
    final pl = WasmF64x2(points[i]);
    final ph = WasmF64x2(points[i + 1]);

    // Low part
    final vL0 = ml0 * WasmF64x2.splat(pl.extractLane(0));
    final vL1 = ml1 * WasmF64x2.splat(pl.extractLane(1));
    final vL2 = ml2 * WasmF64x2.splat(ph.extractLane(0));
    final vL3 = ml3 * WasmF64x2.splat(ph.extractLane(1));
    out[i] = vL0 + vL1 + vL2 + vL3;

    // High part
    final vH0 = mh0 * WasmF64x2.splat(pl.extractLane(0));
    final vH1 = mh1 * WasmF64x2.splat(pl.extractLane(1));
    final vH2 = mh2 * WasmF64x2.splat(ph.extractLane(0));
    final vH3 = mh3 * WasmF64x2.splat(ph.extractLane(1));
    out[i + 1] = vH0 + vH1 + vH2 + vH3;
  }
}
