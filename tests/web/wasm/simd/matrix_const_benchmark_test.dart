// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// dart2wasmOptions=--extra-compiler-option=--enable-experimental-wasm-interop

// ignore: import_internal_library
import 'dart:_wasm';

import 'package:expect/expect.dart';

const vIdentityL = WasmF64x2.fromDoubles(1.0, 0.0);
const vIdentityH = WasmF64x2.fromDoubles(0.0, 1.0);

void main() {
  // 1. Verify that const values work
  Expect.equals(1.0, vIdentityL.extractLane(0).toDouble());
  Expect.equals(0.0, vIdentityL.extractLane(1).toDouble());
  Expect.equals(0.0, vIdentityH.extractLane(0).toDouble());
  Expect.equals(1.0, vIdentityH.extractLane(1).toDouble());

  // 2. We want to check if they are lowered efficiently.
  // We can't easily check the .wat from within the test,
  // but we can check if they are identical references if that's supported.

  final v1 = WasmF64x2.fromDoubles(1.0, 0.0); // Runtime
  final v2 = WasmF64x2.fromDoubles(1.0, 0.0); // Runtime

  // Extension types don't support identity check on the underlying value easily
  // if they are boxed, but here they should be unboxed v128 value types.
  // In Wasm, value types don't have identity.

  print("Const verification complete.");
}
