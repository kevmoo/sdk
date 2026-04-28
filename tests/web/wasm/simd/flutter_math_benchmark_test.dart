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
  final matrix = Float64List(16);
  for (int i = 0; i < 16; i++) matrix[i] = (i + 1) * 0.1;
  matrix[15] = 1.0;

  final aSimd64 = WasmArray<WasmV128>(8);
  for (int i = 0; i < 8; i++) {
    aSimd64[i] = WasmF64x2.fromDoubles(matrix[i * 2], matrix[i * 2 + 1]);
  }

  // 1. Verify correctness
  verifyTransformPoint(matrix, aSimd64);
  verifyTransformRect(matrix, aSimd64);

  // 2. Run benchmarks
  print("Warming up...");
  for (int i = 0; i < 1000; i++) {
    transformPointScalar(matrix, 10.0, 20.0);
    transformPointSimd(aSimd64, 10.0, 20.0);
    transformRectPerspectiveScalar(matrix, 0.0, 0.0, 100.0, 100.0);
    transformRectPerspectiveSimd(aSimd64, 0.0, 0.0, 100.0, 100.0);
  }

  benchmarkTransformPoint(matrix, aSimd64);
  benchmarkTransformRect(matrix, aSimd64);
}

void verifyTransformPoint(Float64List m, WasmArray<WasmV128> mSimd) {
  final x = 10.5;
  final y = 20.5;

  final double rx = m[0] * x + m[4] * y + m[12];
  final double ry = m[1] * x + m[5] * y + m[13];

  final res = transformPointSimdInternal(mSimd, x, y);

  Expect.approxEquals(rx, res.extractLane(0).toDouble());
  Expect.approxEquals(ry, res.extractLane(1).toDouble());
  print("verifyTransformPoint passed.");
}

void verifyTransformRect(Float64List m, WasmArray<WasmV128> mSimd) {
  const l = 0.0, t = 0.0, r = 100.0, b = 100.0;

  double x1 = m[0] * l + m[4] * t + m[12];
  double y1 = m[1] * l + m[5] * t + m[13];
  double x2 = m[0] * r + m[4] * t + m[12];
  double y2 = m[1] * r + m[5] * t + m[13];
  double x3 = m[0] * l + m[4] * b + m[12];
  double y3 = m[1] * l + m[5] * b + m[13];
  double x4 = m[0] * r + m[4] * b + m[12];
  double y4 = m[1] * r + m[5] * b + m[13];

  double minX = x1;
  if (x2 < minX) minX = x2;
  if (x3 < minX) minX = x3;
  if (x4 < minX) minX = x4;

  double minY = y1;
  if (y2 < minY) minY = y2;
  if (y3 < minY) minY = y3;
  if (y4 < minY) minY = y4;

  final results = WasmArray<WasmV128>(2);
  transformRectPerspectiveSimdInternal(mSimd, l, t, r, b, results);
  final min = WasmF64x2(results[0]);

  Expect.approxEquals(minX, min.extractLane(0).toDouble());
  Expect.approxEquals(minY, min.extractLane(1).toDouble());
  print("verifyTransformRect passed.");
}

void benchmarkTransformPoint(Float64List matrix, WasmArray<WasmV128> aSimd64) {
  print("\n--- transformPoint (1M iterations) ---");
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    transformPointScalar(matrix, 1.1, 2.2);
  }
  sw.stop();
  final scalarTime = sw.elapsedMicroseconds;
  print("Scalar Time: ${scalarTime / 1000} ms");

  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    transformPointSimd(aSimd64, 1.1, 2.2);
  }
  sw.stop();
  final simdTime = sw.elapsedMicroseconds;
  print("SIMD F64x2 Time: ${simdTime / 1000} ms");
  print("Speedup: ${(scalarTime / simdTime).toStringAsFixed(2)}x");
}

void benchmarkTransformRect(Float64List matrix, WasmArray<WasmV128> aSimd64) {
  print("\n--- transformRect Perspective (1M iterations) ---");
  final results = WasmArray<WasmV128>(2);
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    transformRectPerspectiveScalar(matrix, 0.0, 0.0, 100.0, 100.0);
  }
  sw.stop();
  final scalarTime = sw.elapsedMicroseconds;
  print("Scalar Time: ${scalarTime / 1000} ms");

  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    transformRectPerspectiveSimdInternal(
      aSimd64,
      0.0,
      0.0,
      100.0,
      100.0,
      results,
    );
  }
  sw.stop();
  final simdTime = sw.elapsedMicroseconds;
  print("SIMD F64x2 Time: ${simdTime / 1000} ms");
  print("Speedup: ${(scalarTime / simdTime).toStringAsFixed(2)}x");
}

@pragma("wasm:prefer-inline")
void transformPointScalar(Float64List m, double x, double y) {
  final double rx = m[0] * x + m[4] * y + m[12];
  final double ry = m[1] * x + m[5] * y + m[13];
  final double rw = m[3] * x + m[7] * y + m[15];
  if (rw != 1.0) {
    final double invRw = 1.0 / rw;
    rx * invRw;
    ry * invRw;
  }
}

@pragma("wasm:prefer-inline")
WasmF64x2 transformPointSimdInternal(
  WasmArray<WasmV128> m,
  double x,
  double y,
) {
  final vX = WasmF64x2.splat(WasmF64.fromDouble(x));
  final vY = WasmF64x2.splat(WasmF64.fromDouble(y));
  return (WasmF64x2(m[0]) * vX) + (WasmF64x2(m[2]) * vY) + WasmF64x2(m[6]);
}

@pragma("wasm:prefer-inline")
void transformPointSimd(WasmArray<WasmV128> m, double x, double y) {
  transformPointSimdInternal(m, x, y);
}

@pragma("wasm:prefer-inline")
void transformRectPerspectiveScalar(
  Float64List m,
  double l,
  double t,
  double r,
  double b,
) {
  double x1 = m[0] * l + m[4] * t + m[12];
  double y1 = m[1] * l + m[5] * t + m[13];
  double x2 = m[0] * r + m[4] * t + m[12];
  double y2 = m[1] * r + m[5] * t + m[13];
  double x3 = m[0] * l + m[4] * b + m[12];
  double y3 = m[1] * l + m[5] * b + m[13];
  double x4 = m[0] * r + m[4] * b + m[12];
  double y4 = m[1] * r + m[5] * b + m[13];

  double minX = x1 < x2 ? x1 : x2;
  if (x3 < minX) minX = x3;
  if (x4 < minX) minX = x4;

  double minY = y1 < y2 ? y1 : y2;
  if (y3 < minY) minY = y3;
  if (y4 < minY) minY = y4;
}

@pragma("wasm:prefer-inline")
void transformRectPerspectiveSimdInternal(
  WasmArray<WasmV128> m,
  double l,
  double t,
  double r,
  double b,
  WasmArray<WasmV128> results,
) {
  final col0 = WasmF64x2(m[0]);
  final col1 = WasmF64x2(m[2]);
  final col3 = WasmF64x2(m[6]);

  final c1 =
      (col0 * WasmF64x2.splat(WasmF64.fromDouble(l))) +
      (col1 * WasmF64x2.splat(WasmF64.fromDouble(t))) +
      col3;
  final c2 =
      (col0 * WasmF64x2.splat(WasmF64.fromDouble(r))) +
      (col1 * WasmF64x2.splat(WasmF64.fromDouble(t))) +
      col3;
  final c3 =
      (col0 * WasmF64x2.splat(WasmF64.fromDouble(l))) +
      (col1 * WasmF64x2.splat(WasmF64.fromDouble(b))) +
      col3;
  final c4 =
      (col0 * WasmF64x2.splat(WasmF64.fromDouble(r))) +
      (col1 * WasmF64x2.splat(WasmF64.fromDouble(b))) +
      col3;

  results[0] = c1.min(c2).min(c3).min(c4);
  results[1] = c1.max(c2).max(c3).max(c4);
}

@pragma("wasm:prefer-inline")
void transformRectPerspectiveSimd(
  WasmArray<WasmV128> m,
  double l,
  double t,
  double r,
  double b,
) {
  final results = WasmArray<WasmV128>(2);
  transformRectPerspectiveSimdInternal(m, l, t, r, b, results);
}
