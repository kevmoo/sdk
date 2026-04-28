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
  // Simple rotation + translation
  matrix[0] = 0.866;
  matrix[1] = 0.5; // cos(30), sin(30)
  matrix[4] = -0.5;
  matrix[5] = 0.866; // -sin(30), cos(30)
  matrix[10] = 1.0;
  matrix[15] = 1.0;
  matrix[12] = 10.0;
  matrix[13] = 20.0;

  final left = 10.0, top = 10.0, right = 110.0, bottom = 60.0;
  final out = Float64List(4);

  // 1. Verify correctness
  transformRectScalar(matrix, left, top, right, bottom, out);
  final scalarRect = List.from(out);
  transformRectSimd(matrix, left, top, right, bottom, out);
  final simdRect = List.from(out);

  Expect.approxEquals(scalarRect[0], simdRect[0]);
  Expect.approxEquals(scalarRect[1], simdRect[1]);
  Expect.approxEquals(scalarRect[2], simdRect[2]);
  Expect.approxEquals(scalarRect[3], simdRect[3]);
  print("Verification complete.");

  // 2. Run benchmarks
  print("Warming up...");
  for (int i = 0; i < 1000; i++) {
    transformRectScalar(matrix, left, top, right, bottom, out);
    transformRectSimd(matrix, left, top, right, bottom, out);
  }

  print("Starting Scalar transformRect Benchmark ($iterations iterations)...");
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    transformRectScalar(matrix, left, top, right, bottom, out);
  }
  sw.stop();
  final scalarTime = sw.elapsedMicroseconds;
  print("Scalar Time: ${scalarTime / 1000} ms");

  print("Starting SIMD transformRect Benchmark ($iterations iterations)...");
  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    transformRectSimd(matrix, left, top, right, bottom, out);
  }
  sw.stop();
  final simdTime = sw.elapsedMicroseconds;
  print("SIMD Time: ${simdTime / 1000} ms");

  print("Speedup: ${(scalarTime / simdTime).toStringAsFixed(2)}x");
}

// Simplified version of MatrixUtils.transformRect (affine path)
@pragma("wasm:prefer-inline")
void transformRectScalar(
  Float64List storage,
  double l,
  double t,
  double r,
  double b,
  Float64List out,
) {
  final double x = l;
  final double y = t;
  final double w = r - l;
  final double h = b - t;

  final double wx = storage[0] * w;
  final double hx = storage[4] * h;
  final double rx = storage[0] * x + storage[4] * y + storage[12];

  final double wy = storage[1] * w;
  final double hy = storage[5] * h;
  final double ry = storage[1] * x + storage[5] * y + storage[13];

  var resLeft = rx;
  var resRight = rx;
  if (wx < 0) {
    resLeft += wx;
  } else {
    resRight += wx;
  }
  if (hx < 0) {
    resLeft += hx;
  } else {
    resRight += hx;
  }

  var resTop = ry;
  var resBottom = ry;
  if (wy < 0) {
    resTop += wy;
  } else {
    resBottom += wy;
  }
  if (hy < 0) {
    resTop += hy;
  } else {
    resBottom += hy;
  }

  out[0] = resLeft;
  out[1] = resTop;
  out[2] = resRight;
  out[3] = resBottom;
}

// SIMD version of transformRect (affine path)
// This loads transiently from the Float64List storage
@pragma("wasm:prefer-inline")
void transformRectSimd(
  Float64List storage,
  double l,
  double t,
  double r,
  double b,
  Float64List out,
) {
  // Load col0, col1, col3 (translation)
  final col0 = WasmF64x2.fromDoubles(storage[0], storage[1]);
  final col1 = WasmF64x2.fromDoubles(storage[4], storage[5]);
  final col3 = WasmF64x2.fromDoubles(storage[12], storage[13]);

  final vW = WasmF64x2.splat(WasmF64.fromDouble(r - l));
  final vH = WasmF64x2.splat(WasmF64.fromDouble(b - t));
  final vX = WasmF64x2.splat(WasmF64.fromDouble(l));
  final vY = WasmF64x2.splat(WasmF64.fromDouble(t));

  final w_vec = col0 * vW; // (wx, wy)
  final h_vec = col1 * vH; // (hx, hy)
  final r_vec = (col0 * vX) + (col1 * vY) + col3; // (rx, ry)

  final zero = WasmF64x2.splat(WasmF64.fromDouble(0.0));

  final min_parts = w_vec.min(zero) + h_vec.min(zero);
  final max_parts = w_vec.max(zero) + h_vec.max(zero);

  final res_min = r_vec + min_parts;
  final res_max = r_vec + max_parts;

  out[0] = res_min.extractLane(0).toDouble();
  out[1] = res_min.extractLane(1).toDouble();
  out[2] = res_max.extractLane(0).toDouble();
  out[3] = res_max.extractLane(1).toDouble();
}
