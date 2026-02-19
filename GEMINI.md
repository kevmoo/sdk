# Dart SDK - Wasm Const Implementation

This file documents the process of adding SIMD constant support to the Dart-to-Wasm compiler.

## Environment & Build

- **Building the SDK:** 
  ```bash
  ./tools/build.py --mode release create_sdk
  ```
  *Note: If you update `wasm_types.dart`, you MUST recompile the SDK.*

- **Compiling/Running Benchmarks/Tests:**
  ```bash
  ./pkg/dart2wasm/tool/compile_benchmark \
    --run \
    --src \
    --extra-compiler-option=--enable-experimental-wasm-interop \
    <dart_file>
  ```
  *Use `--temp-output` to avoid cluttering the test directory.*

## Implementation Details

### Constant Evaluation
SIMD constants are implemented using `const WasmV128.literal([...])`.
The backend (`pkg/dart2wasm/lib/constants.dart`) recognizes these constants and lowers them to the Wasm `v128.const` instruction.
Lane values can be:
- `IntConstant` / `DoubleConstant` (for direct literals)
- `InstanceConstant` of boxed Wasm types (`WasmI32`, `WasmI64`, `WasmF32`, `WasmF64`).

### WasmF64x2.literal
`WasmF64x2.literal` is an `external static` method in `dart:_wasm`. 
It is intrinsified in `pkg/dart2wasm/lib/intrinsics.dart`:
- If arguments are constants, it emits a `v128.const`.
- Otherwise, it emits a `f64x2.splat` followed by a `f64x2.replace_lane`.

### SIMD Extension Types
All SIMD extension types (e.g., `WasmF64x2`, `WasmI32x4`) are now `const extension type`s.
To define a global constant:
```dart
const _zeroF64x2 = WasmF64x2(WasmV128.literal([WasmF64(0.0), WasmF64(0.0)]));
```

## Testing
- `tests/web/wasm/simd/simd_const_test.dart`: Verifies all SIMD shapes as constants and `WasmF64x2.literal` runtime behavior.
- `tests/web/wasm/simd/vector_test.dart`: High-level vector math test using SIMD constants.

## Tasks
- [x] Add `WasmV128` class and `WasmF64x2.literal` extension type to `sdk/lib/_wasm/wasm_types.dart`.
- [x] Implement backend support for `WasmV128.literal` in `pkg/dart2wasm`.
- [x] Verify with a test case.
