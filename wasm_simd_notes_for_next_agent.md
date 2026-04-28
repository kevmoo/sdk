# Wasm SIMD Optimization for Flutter: Status Report

## Context
The goal of this work is to leverage WebAssembly SIMD (v128) instructions to accelerate Flutter's core math operations (`Offset`, `Rect`, `Matrix4`). We have successfully implemented the necessary compiler building blocks and verified massive performance gains in micro-benchmarks.

## Key Accomplishments

### 1. Compiler & IR Infrastructure (`pkg/wasm_builder`)
- **Memory Operations**: Added `V128Load` and `V128Store` IR nodes.
- **Opcode Fix**: Corrected prefix encoding to `0xFD` and fixed the `v128.store` opcode to `0x0B`.
- **Refactor**: Overhauled `MemoryInstruction` to support multi-byte sub-opcodes (LEB128), preventing double-emission of prefix bytes.
- **Builder API**: Added `v128_load` and `v128_store` to `InstructionsBuilder`.

### 2. SDK Libraries (`sdk/lib/_wasm`)
- **Memory Access**: Added `loadV128` and `storeV128` to `MemoryAccessExtension` in `memory.dart`.
- **SIMD Shuffles**: Added shape-specific `shuffle(other, lanes)` methods to `WasmF64x2`, `WasmF32x4`, `WasmI32x4`, `WasmI16x8`, and `WasmI8x16`.
- **Ergonomic Factories**: Added runtime `fromDoubles` and `fromInts` factories to extension types.

### 3. Compiler Intrinsics (`pkg/dart2wasm`)
- **Shuffle Intrinsification**: Implemented complex lane-to-byte mapping logic to translate high-level SIMD shuffles into `i8x16.shuffle`.
- **Type Safety**: Fixed `RuntimeError: unreachable` by adding explicit type conversions (e.g., `f32.demote_f64` and `i32.wrap_i64`) inside SIMD factories.
- **Constant Support**: Updated constant lowering to handle boxed types like `WasmF64` inside `WasmV128` constructors.

## Verified Performance Gains (1M Iterations)
| Benchmark | Scalar Time | SIMD Time | Speedup |
| :--- | :--- | :--- | :--- |
| **Matrix4 Multiply (F64)** | 219 ms | 40 ms | **~5.5x** |
| **Matrix4 Multiply (F32)** | 219 ms | 23 ms | **~9.5x** |
| **`transformPoint` (F64)** | 37 ms | 9 ms | **~4.1x** |
| **`transformRect` (F64)** | 92 ms | 7 ms | **13.1x** |

## Technical "Gotchas" for the Next Agent
1. **Lane Indices**: `extractLane(index)` MUST use a literal integer (e.g. `0`, `1`). Dynamic variables will cause compiler errors.
2. **Return Types**: Every `case` in the intrinsifier MUST return a `w.ValueType`. Missing returns lead to `unreachable` instructions.
3. **Record Crash**: `dart2wasm` currently crashes when returning a Record containing Wasm types (e.g. `(WasmF64x2, WasmF64x2)`). Workaround: Pass a `WasmArray` to store results or return a single `WasmV128`.
4. **Documentation**: Detailed "wish I knew" notes are now in `CONTRIBUTING.md` in both `pkg/wasm_builder` and `pkg/dart2wasm`.

## Next Steps: Flutter Integration
- [ ] **Import Flutter Source**: Point the agent to the local Flutter checkout.
- [ ] **Analyze Core Types**: Map `painting/matrix_utils.dart` hand-optimized methods to our new SIMD intrinsics.
- [ ] **Implement SIMD-Ready `Matrix4`**: Prototype a version of `Matrix4` that uses `WasmArray<WasmV128>` storage.
- [ ] **Verify End-to-End**: Run existing Flutter painting tests on the new SIMD-accelerated paths.

**Branch**: `wasm_simd_perf` (all changes are committed and pass presubmit).
