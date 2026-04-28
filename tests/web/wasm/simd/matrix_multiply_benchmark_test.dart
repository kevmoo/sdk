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
  final a = Float64List(16);
  final b = Float64List(16);
  final out = Float64List(16);

  // Initialize with some data
  for (int i = 0; i < 16; i++) {
    a[i] = i.toDouble() * 0.1;
    b[i] = (16 - i).toDouble() * 0.1;
  }

  // Wasm-side storage (F64)
  final aSimd64 = WasmArray<WasmV128>(8);
  final bSimd64 = WasmArray<WasmV128>(8);
  final outSimd64 = WasmArray<WasmV128>(8);

  // Wasm-side storage (F32)
  final aSimd32 = WasmArray<WasmV128>(4);
  final bSimd32 = WasmArray<WasmV128>(4);
  final outSimd32 = WasmArray<WasmV128>(4);

  for (int i = 0; i < 8; i++) {
    aSimd64[i] = WasmF64x2.fromDoubles(a[i * 2], a[i * 2 + 1]);
    bSimd64[i] = WasmF64x2.fromDoubles(b[i * 2], b[i * 2 + 1]);
  }

  for (int i = 0; i < 4; i++) {
    aSimd32[i] = WasmF32x4.fromDoubles(
      a[i * 4 + 0],
      a[i * 4 + 1],
      a[i * 4 + 2],
      a[i * 4 + 3],
    );
    bSimd32[i] = WasmF32x4.fromDoubles(
      b[i * 4 + 0],
      b[i * 4 + 1],
      b[i * 4 + 2],
      b[i * 4 + 3],
    );
  }

  print("Warming up...");
  for (int i = 0; i < 1000; i++) {
    multiplyScalar(a, b, out);
    multiplySimdF64x2(aSimd64, bSimd64, outSimd64);
    multiplySimdF32x4(aSimd32, bSimd32, outSimd32);
  }

  print("Starting Scalar Benchmark ($iterations iterations)...");
  final sw = Stopwatch()..start();
  for (int i = 0; i < iterations; i++) {
    multiplyScalar(a, b, out);
  }
  sw.stop();
  final scalarTime = sw.elapsedMicroseconds;
  print("Scalar Time: ${scalarTime / 1000} ms");

  print("Starting SIMD F64x2 Benchmark ($iterations iterations)...");
  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    multiplySimdF64x2(aSimd64, bSimd64, outSimd64);
  }
  sw.stop();
  final simd64Time = sw.elapsedMicroseconds;
  print("SIMD F64x2 Time: ${simd64Time / 1000} ms");

  print("Starting SIMD F32x4 Benchmark ($iterations iterations)...");
  sw
    ..reset()
    ..start();
  for (int i = 0; i < iterations; i++) {
    multiplySimdF32x4(aSimd32, bSimd32, outSimd32);
  }
  sw.stop();
  final simd32Time = sw.elapsedMicroseconds;
  print("SIMD F32x4 Time: ${simd32Time / 1000} ms");

  print("F64 Speedup: ${(scalarTime / simd64Time).toStringAsFixed(2)}x");
  print("F32 Speedup: ${(scalarTime / simd32Time).toStringAsFixed(2)}x");

  // Verification
  final expected = Float64List(16);
  multiplyScalar(a, b, expected);

  // Verify F64
  for (int i = 0; i < 8; i++) {
    final v = WasmF64x2(outSimd64[i]);
    Expect.approxEquals(expected[i * 2], v.extractLane(0).toDouble());
    Expect.approxEquals(expected[i * 2 + 1], v.extractLane(1).toDouble());
  }

  // Verify F32
  for (int i = 0; i < 4; i++) {
    final v = WasmF32x4(outSimd32[i]);
    Expect.approxEquals(expected[i * 4 + 0], v.extractLane(0).toDouble());
    Expect.approxEquals(expected[i * 4 + 1], v.extractLane(1).toDouble());
    Expect.approxEquals(expected[i * 4 + 2], v.extractLane(2).toDouble());
    Expect.approxEquals(expected[i * 4 + 3], v.extractLane(3).toDouble());
  }
  print("Verification complete.");
}

@pragma("wasm:prefer-inline")
void multiplyScalar(Float64List a, Float64List b, Float64List out) {
  final double a00 = a[0], a01 = a[1], a02 = a[2], a03 = a[3];
  final double a10 = a[4], a11 = a[5], a12 = a[6], a13 = a[7];
  final double a20 = a[8], a21 = a[9], a22 = a[10], a23 = a[11];
  final double a30 = a[12], a31 = a[13], a32 = a[14], a33 = a[15];

  for (int j = 0; j < 4; j++) {
    final int j4 = j * 4;
    final double b0 = b[j4 + 0];
    final double b1 = b[j4 + 1];
    final double b2 = b[j4 + 2];
    final double b3 = b[j4 + 3];

    out[j4 + 0] = a00 * b0 + a10 * b1 + a20 * b2 + a30 * b3;
    out[j4 + 1] = a01 * b0 + a11 * b1 + a21 * b2 + a31 * b3;
    out[j4 + 2] = a02 * b0 + a12 * b1 + a22 * b2 + a32 * b3;
    out[j4 + 3] = a03 * b0 + a13 * b1 + a23 * b2 + a33 * b3;
  }
}

@pragma("wasm:prefer-inline")
void multiplySimdF64x2(
  WasmArray<WasmV128> a,
  WasmArray<WasmV128> b,
  WasmArray<WasmV128> out,
) {
  final a0_l = WasmF64x2(a[0]);
  final a0_h = WasmF64x2(a[1]);
  final a1_l = WasmF64x2(a[2]);
  final a1_h = WasmF64x2(a[3]);
  final a2_l = WasmF64x2(a[4]);
  final a2_h = WasmF64x2(a[5]);
  final a3_l = WasmF64x2(a[6]);
  final a3_h = WasmF64x2(a[7]);

  for (int j = 0; j < 4; j++) {
    final bj = WasmF64x2(b[j * 2]);
    final bj2 = WasmF64x2(b[j * 2 + 1]);

    final b0 = WasmF64x2.splat(bj.extractLane(0));
    final b1 = WasmF64x2.splat(bj.extractLane(1));
    final b2 = WasmF64x2.splat(bj2.extractLane(0));
    final b3 = WasmF64x2.splat(bj2.extractLane(1));

    out[j * 2] = (a0_l * b0) + (a1_l * b1) + (a2_l * b2) + (a3_l * b3);
    out[j * 2 + 1] = (a0_h * b0) + (a1_h * b1) + (a2_h * b2) + (a3_h * b3);
  }
}

@pragma("wasm:prefer-inline")
void multiplySimdF32x4(
  WasmArray<WasmV128> a,
  WasmArray<WasmV128> b,
  WasmArray<WasmV128> out,
) {
  final a0 = WasmF32x4(a[0]);
  final a1 = WasmF32x4(a[1]);
  final a2 = WasmF32x4(a[2]);
  final a3 = WasmF32x4(a[3]);

  for (int j = 0; j < 4; j++) {
    final bj = WasmF32x4(b[j]);

    final b0 = WasmF32x4.splat(bj.extractLane(0));
    final b1 = WasmF32x4.splat(bj.extractLane(1));
    final b2 = WasmF32x4.splat(bj.extractLane(2));
    final b3 = WasmF32x4.splat(bj.extractLane(3));

    out[j] = (a0 * b0) + (a1 * b1) + (a2 * b2) + (a3 * b3);
  }
}
