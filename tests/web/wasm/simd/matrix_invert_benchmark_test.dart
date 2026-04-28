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
  final arg = Float64List(16);
  final out = Float64List(16);

  // Initialize with a known invertible matrix (translation + scale + rotation)
  arg[0] = 2.0;
  arg[5] = 2.0;
  arg[10] = 2.0;
  arg[15] = 1.0;
  arg[12] = 10.0;
  arg[13] = 20.0;
  arg[14] = 30.0;

  final aSimd64 = WasmArray<WasmV128>(8);
  for (int i = 0; i < 8; i++) {
    aSimd64[i] = WasmF64x2.fromDoubles(arg[i * 2], arg[i * 2 + 1]);
  }
  final outSimd64 = WasmArray<WasmV128>(8);

  // 1. Verify correctness
  final scalarDet = invertScalar(arg, out);
  final simdDet = invertSimdF64x2(aSimd64, outSimd64);

  Expect.approxEquals(scalarDet, simdDet);
  for (int i = 0; i < 8; i++) {
    final v = WasmF64x2(outSimd64[i]);
    Expect.approxEquals(out[i * 2], v.extractLane(0).toDouble());
    Expect.approxEquals(out[i * 2 + 1], v.extractLane(1).toDouble());
  }
  print("Verification complete.");

  // 2. Run benchmarks
  print("Warming up...");
  for (int i = 0; i < 1000; i++) {
    invertScalar(arg, out);
    invertSimdF64x2(aSimd64, outSimd64);
  }

  print("Starting Scalar Invert Benchmark ($iterations iterations)...");
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    invertScalar(arg, out);
  }
  sw.stop();
  final scalarTime = sw.elapsedMicroseconds;
  print("Scalar Time: ${scalarTime / 1000} ms");

  print("Starting SIMD F64x2 Invert Benchmark ($iterations iterations)...");
  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    invertSimdF64x2(aSimd64, outSimd64);
  }
  sw.stop();
  final simdTime = sw.elapsedMicroseconds;
  print("SIMD F64x2 Time: ${simdTime / 1000} ms");

  print("Speedup: ${(scalarTime / simdTime).toStringAsFixed(2)}x");
}

// Scalar implementation directly from vector_math
@pragma("wasm:prefer-inline")
double invertScalar(Float64List argStorage, Float64List out) {
  final a00 = argStorage[0];
  final a01 = argStorage[1];
  final a02 = argStorage[2];
  final a03 = argStorage[3];
  final a10 = argStorage[4];
  final a11 = argStorage[5];
  final a12 = argStorage[6];
  final a13 = argStorage[7];
  final a20 = argStorage[8];
  final a21 = argStorage[9];
  final a22 = argStorage[10];
  final a23 = argStorage[11];
  final a30 = argStorage[12];
  final a31 = argStorage[13];
  final a32 = argStorage[14];
  final a33 = argStorage[15];
  final b00 = a00 * a11 - a01 * a10;
  final b01 = a00 * a12 - a02 * a10;
  final b02 = a00 * a13 - a03 * a10;
  final b03 = a01 * a12 - a02 * a11;
  final b04 = a01 * a13 - a03 * a11;
  final b05 = a02 * a13 - a03 * a12;
  final b06 = a20 * a31 - a21 * a30;
  final b07 = a20 * a32 - a22 * a30;
  final b08 = a20 * a33 - a23 * a30;
  final b09 = a21 * a32 - a22 * a31;
  final b10 = a21 * a33 - a23 * a31;
  final b11 = a22 * a33 - a23 * a32;
  final det =
      b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
  if (det == 0.0) {
    return 0.0;
  }
  final invDet = 1.0 / det;
  out[0] = (a11 * b11 - a12 * b10 + a13 * b09) * invDet;
  out[1] = (-a01 * b11 + a02 * b10 - a03 * b09) * invDet;
  out[2] = (a31 * b05 - a32 * b04 + a33 * b03) * invDet;
  out[3] = (-a21 * b05 + a22 * b04 - a23 * b03) * invDet;
  out[4] = (-a10 * b11 + a12 * b08 - a13 * b07) * invDet;
  out[5] = (a00 * b11 - a02 * b08 + a03 * b07) * invDet;
  out[6] = (-a30 * b05 + a32 * b02 - a33 * b01) * invDet;
  out[7] = (a20 * b05 - a22 * b02 + a23 * b01) * invDet;
  out[8] = (a10 * b10 - a11 * b08 + a13 * b06) * invDet;
  out[9] = (-a00 * b10 + a01 * b08 - a03 * b06) * invDet;
  out[10] = (a30 * b04 - a31 * b02 + a33 * b00) * invDet;
  out[11] = (-a20 * b04 + a21 * b02 - a23 * b00) * invDet;
  out[12] = (-a10 * b09 + a11 * b07 - a12 * b06) * invDet;
  out[13] = (a00 * b09 - a01 * b07 + a02 * b06) * invDet;
  out[14] = (-a30 * b03 + a31 * b01 - a32 * b00) * invDet;
  out[15] = (a20 * b03 - a21 * b01 + a22 * b00) * invDet;
  return det;
}

// SIMD implementation of Cramer's rule
@pragma("wasm:prefer-inline")
double invertSimdF64x2(WasmArray<WasmV128> m, WasmArray<WasmV128> out) {
  // Matrix is column-major:
  // m[0,1] = col0
  // m[2,3] = col1
  // m[4,5] = col2
  // m[6,7] = col3

  final c0_l = WasmF64x2(m[0]); // a00, a01
  final c0_h = WasmF64x2(m[1]); // a02, a03
  final c1_l = WasmF64x2(m[2]); // a10, a11
  final c1_h = WasmF64x2(m[3]); // a12, a13
  final c2_l = WasmF64x2(m[4]); // a20, a21
  final c2_h = WasmF64x2(m[5]); // a22, a23
  final c3_l = WasmF64x2(m[6]); // a30, a31
  final c3_h = WasmF64x2(m[7]); // a32, a33

  // For 4x4 inversion, we need 2x2 determinants of submatrices.
  // b00 = a00 * a11 - a01 * a10
  // b01 = a00 * a12 - a02 * a10
  // ...

  // This implementation is a bit more complex to vectorize fully without
  // f64x2.shuffle, but we have shuffle!

  // b00 = a00 * a11 - a01 * a10
  // a00, a01 is c0_l
  // a11, a10 is c1_l swizzled
  final c1_l_swiz = c1_l.shuffle(c1_l, const [1, 0]);
  final b00_vec = (c0_l * c1_l_swiz);
  final b00 =
      b00_vec.extractLane(0).toDouble() - b00_vec.extractLane(1).toDouble();

  // b01 = a00 * a12 - a02 * a10
  final b01 =
      c0_l.extractLane(0).toDouble() * c1_h.extractLane(0).toDouble() -
      c0_h.extractLane(0).toDouble() * c1_l.extractLane(0).toDouble();

  // b02 = a00 * a13 - a03 * a10
  final b02 =
      c0_l.extractLane(0).toDouble() * c1_h.extractLane(1).toDouble() -
      c0_h.extractLane(1).toDouble() * c1_l.extractLane(0).toDouble();

  // b03 = a01 * a12 - a02 * a11
  final b03 =
      c0_l.extractLane(1).toDouble() * c1_h.extractLane(0).toDouble() -
      c0_h.extractLane(0).toDouble() * c1_l.extractLane(1).toDouble();

  // b04 = a01 * a13 - a03 * a11
  final b04 =
      c0_l.extractLane(1).toDouble() * c1_h.extractLane(1).toDouble() -
      c0_h.extractLane(1).toDouble() * c1_l.extractLane(1).toDouble();

  // b05 = a02 * a13 - a03 * a12
  final b05_vec = (c0_h * c1_h.shuffle(c1_h, const [1, 0]));
  final b05 =
      b05_vec.extractLane(0).toDouble() - b05_vec.extractLane(1).toDouble();

  // b06 = a20 * a31 - a21 * a30
  final c3_l_swiz = c3_l.shuffle(c3_l, const [1, 0]);
  final b06_vec = (c2_l * c3_l_swiz);
  final b06 =
      b06_vec.extractLane(0).toDouble() - b06_vec.extractLane(1).toDouble();

  // b07 = a20 * a32 - a22 * a30
  final b07 =
      c2_l.extractLane(0).toDouble() * c3_h.extractLane(0).toDouble() -
      c2_h.extractLane(0).toDouble() * c3_l.extractLane(0).toDouble();

  // b08 = a20 * a33 - a23 * a30
  final b08 =
      c2_l.extractLane(0).toDouble() * c3_h.extractLane(1).toDouble() -
      c2_h.extractLane(1).toDouble() * c3_l.extractLane(0).toDouble();

  // b09 = a21 * a32 - a22 * a31
  final b09 =
      c2_l.extractLane(1).toDouble() * c3_h.extractLane(0).toDouble() -
      c2_h.extractLane(0).toDouble() * c3_l.extractLane(1).toDouble();

  // b10 = a21 * a33 - a23 * a31
  final b10 =
      c2_l.extractLane(1).toDouble() * c3_h.extractLane(1).toDouble() -
      c2_h.extractLane(1).toDouble() * c3_l.extractLane(1).toDouble();

  // b11 = a22 * a33 - a23 * a32
  final b11_vec = (c2_h * c3_h.shuffle(c3_h, const [1, 0]));
  final b11 =
      b11_vec.extractLane(0).toDouble() - b11_vec.extractLane(1).toDouble();

  final det =
      b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06;
  if (det == 0.0) return 0.0;

  final invDet = 1.0 / det;
  final vInvDet = WasmF64x2.splat(WasmF64.fromDouble(invDet));

  // The adjugate matrix calculation can be significantly vectorized
  // out[0] = (a11 * b11 - a12 * b10 + a13 * b09) * invDet;
  // out[1] = (-a01 * b11 + a02 * b10 - a03 * b09) * invDet;

  // Note: For now, I'm doing a hybrid to ensure I can get this working.
  // A fully vectorized 4x4 inversion usually uses the "Shuffle-based 4x4" approach
  // which is very different from Cramer's Rule.

  final a11 = c1_l.extractLane(1).toDouble();
  final a12 = c1_h.extractLane(0).toDouble();
  final a13 = c1_h.extractLane(1).toDouble();
  final a01 = c0_l.extractLane(1).toDouble();
  final a02 = c0_h.extractLane(0).toDouble();
  final a03 = c0_h.extractLane(1).toDouble();
  final a31 = c3_l.extractLane(1).toDouble();
  final a32 = c3_h.extractLane(0).toDouble();
  final a33 = c3_h.extractLane(1).toDouble();
  final a21 = c2_l.extractLane(1).toDouble();
  final a22 = c2_h.extractLane(0).toDouble();
  final a23 = c2_h.extractLane(1).toDouble();

  final a10 = c1_l.extractLane(0).toDouble();
  final a00 = c0_l.extractLane(0).toDouble();
  final a30 = c3_l.extractLane(0).toDouble();
  final a20 = c2_l.extractLane(0).toDouble();

  out[0] = WasmF64x2.fromDoubles(
    (a11 * b11 - a12 * b10 + a13 * b09) * invDet,
    (-a01 * b11 + a02 * b10 - a03 * b09) * invDet,
  );
  out[1] = WasmF64x2.fromDoubles(
    (a31 * b05 - a32 * b04 + a33 * b03) * invDet,
    (-a21 * b05 + a22 * b04 - a23 * b03) * invDet,
  );
  out[2] = WasmF64x2.fromDoubles(
    (-a10 * b11 + a12 * b08 - a13 * b07) * invDet,
    (a00 * b11 - a02 * b08 + a03 * b07) * invDet,
  );
  out[3] = WasmF64x2.fromDoubles(
    (-a30 * b05 + a32 * b02 - a33 * b01) * invDet,
    (a20 * b05 - a22 * b02 + a23 * b01) * invDet,
  );
  out[4] = WasmF64x2.fromDoubles(
    (a10 * b10 - a11 * b08 + a13 * b06) * invDet,
    (-a00 * b10 + a01 * b08 - a03 * b06) * invDet,
  );
  out[5] = WasmF64x2.fromDoubles(
    (a30 * b04 - a31 * b02 + a33 * b00) * invDet,
    (-a20 * b04 + a21 * b02 - a23 * b00) * invDet,
  );
  out[6] = WasmF64x2.fromDoubles(
    (-a10 * b09 + a11 * b07 - a12 * b06) * invDet,
    (a00 * b09 - a01 * b07 + a02 * b06) * invDet,
  );
  out[7] = WasmF64x2.fromDoubles(
    (-a30 * b03 + a31 * b01 - a32 * b00) * invDet,
    (a20 * b03 - a21 * b01 + a22 * b00) * invDet,
  );

  return det;
}
