// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// dart2wasmOptions=--extra-compiler-option=--enable-experimental-wasm-interop

// ignore: import_internal_library
import 'dart:_wasm';

import 'package:expect/expect.dart';

@pragma('wasm:memory-type', MemoryType(limits: Limits(1, 1)))
external Memory get _memory;

void main() {
  testRuntimeFactories();
  testLoadStoreV128();
  testShuffles();
}

void testRuntimeFactories() {
  print("Running testRuntimeFactories...");

  final double d0 = 1.1;
  final double d1 = 2.2;
  print("Creating vF64x2...");
  final vF64x2 = WasmF64x2.fromDoubles(d0, d1);
  print("Extracting lane 0...");
  Expect.equals(d0, vF64x2.extractLane(0).toDouble());
  print("Extracting lane 1...");
  Expect.equals(d1, vF64x2.extractLane(1).toDouble());

  print("Creating vF32x4...");
  final vF32x4 = WasmF32x4.fromDoubles(1.0, 2.0, 3.0, 4.0);
  print("Checking vF32x4 lanes...");
  Expect.equals(1.0, vF32x4.extractLane(0).toDouble());
  Expect.equals(4.0, vF32x4.extractLane(3).toDouble());

  print("Creating vI32x4...");
  final vI32x4 = WasmI32x4.fromInts(10, 20, 30, 40);
  print("Checking vI32x4 lanes...");
  Expect.equals(10, vI32x4.extractLane(0).toIntSigned());
  Expect.equals(40, vI32x4.extractLane(3).toIntSigned());
}

void testLoadStoreV128() {
  print("Running testLoadStoreV128...");

  // Setup memory with known double values
  _memory.storeFloat64(0, WasmF64.fromDouble(123.456));
  _memory.storeFloat64(8, WasmF64.fromDouble(789.012));

  // Load as v128
  final v128 = _memory.loadV128(0);
  final f64x2 = WasmF64x2(v128);
  Expect.equals(123.456, f64x2.extractLane(0).toDouble());
  Expect.equals(789.012, f64x2.extractLane(1).toDouble());

  // Store back as v128 at different offset
  final vF32x4 = WasmF32x4.fromDoubles(1.1, 2.2, 3.3, 4.4);
  _memory.storeV128(100, vF32x4);

  // Load individual values and verify
  Expect.approxEquals(1.1, _memory.loadFloat32(100).toDouble());
  Expect.approxEquals(2.2, _memory.loadFloat32(104).toDouble());
  Expect.approxEquals(3.3, _memory.loadFloat32(108).toDouble());
  Expect.approxEquals(4.4, _memory.loadFloat32(112).toDouble());
}

void testShuffles() {
  print("Running testShuffles...");

  // F64x2 shuffle (Swap lanes)
  final vF64x2_a = WasmF64x2.fromDoubles(1.0, 2.0);
  final vF64x2_b = WasmF64x2.fromDoubles(3.0, 4.0);
  // Indices: [v1.l0, v1.l1, v2.l0, v2.l1] -> [0, 1, 2, 3]
  // Let's take v1.l1 and v2.l0
  final vF64x2_shuffled = vF64x2_a.shuffle(vF64x2_b, const [1, 2]);
  Expect.equals(2.0, vF64x2_shuffled.extractLane(0).toDouble());
  Expect.equals(3.0, vF64x2_shuffled.extractLane(1).toDouble());

  // F32x4 shuffle (Reverse)
  final vF32x4 = WasmF32x4.fromDoubles(1.0, 2.0, 3.0, 4.0);
  final vF32x4_rev = vF32x4.shuffle(vF32x4, const [3, 2, 1, 0]);
  Expect.equals(4.0, vF32x4_rev.extractLane(0).toDouble());
  Expect.equals(3.0, vF32x4_rev.extractLane(1).toDouble());
  Expect.equals(2.0, vF32x4_rev.extractLane(2).toDouble());
  Expect.equals(1.0, vF32x4_rev.extractLane(3).toDouble());

  // I32x4 shuffle (Broadcast first element)
  final vI32x4 = WasmI32x4.fromInts(99, 1, 2, 3);
  final vI32x4_bc = vI32x4.shuffle(vI32x4, const [0, 0, 0, 0]);
  Expect.equals(99, vI32x4_bc.extractLane(0).toIntSigned());
  Expect.equals(99, vI32x4_bc.extractLane(1).toIntSigned());
  Expect.equals(99, vI32x4_bc.extractLane(2).toIntSigned());
  Expect.equals(99, vI32x4_bc.extractLane(3).toIntSigned());
}
