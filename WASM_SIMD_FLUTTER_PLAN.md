# Wasm SIMD Optimization: Flutter Specialization Plan

This document outlines the "Ground Work" phase to prove that WebAssembly SIMD is ready for core Flutter math specialization.

## Goal
Demonstrate significant, production-ready performance gains for `vector_math` and `painting` logic when compiled with `dart2wasm`.

---

## Area 1: Complex Math (Matrix Inversion & Determinant)
**Status**: Critical "Stress Test"

*   **Objective**: Implement a SIMD 4x4 matrix inversion.
*   **Method**: 
    *   Use Cramer's Rule with sub-determinant shuffles.
    *   Leverage `WasmF64x2.shuffle` to compute cross-products and adjugate values in parallel.
*   **Success Metric**: >3x speedup over `Matrix4.copyInverse` (scalar).
*   **Key Verification**: Ensure precision matches the scalar version across common Flutter transforms (translation, rotation, perspective).

## Area 2: Data Movement (Bulk Memory Interop)
**Status**: The "Bridge" Problem (Optional if using Native Storage)

*   **Objective**: Minimize the overhead of loading data from `Float64List` into SIMD registers.
*   **Method**: 
    *   Benchmark transformation of a `Float64List` containing 1,000 points.
    *   **New Feature**: Investigate adding a `dart2wasm` intrinsic for direct `v128.load` from a `TypedData` backing buffer.
*   **Success Metric**: SIMD should be faster than scalar even when including the cost of loading/storing from a standard Dart list.
*   **Shift in Strategy**: Our research indicates that we can achieve much higher gains (13x vs 2.45x) by **avoiding** `Float64List` entirely for core types like `Matrix4`.

---

## Architectural Strategy: Platform Abstraction

To unlock maximum performance, we should move toward a platform-specialized implementation of `vector_math` (and related painting logic).

### 1. Wasm-Native Storage
*   **Approach**: Specialize `Matrix4`, `Offset`, and `Rect` to use `WasmArray<WasmV128>` as their primary storage on Wasm.
*   **Benefit**: Math operations (multiplication, inversion, transformation) achieve their "Golden" **10x-13x speedup** because data never leaves the SIMD-optimized Wasm GC arrays. *(Note: This massive speedup is actually a combination of ~1.5x-2.7x from the SIMD instructions themselves, and a ~3.5x-4x speedup from shedding `Float64List` abstraction overhead by using raw unboxed memory).*

### 2. The "Interface Boundary" Challenge
Many Flutter and Engine APIs (e.g., `Canvas.transform`, `SceneBuilder.pushTransform`) expect a `Float64List`.
*   **Strategy A (Copy-on-Export)**: Provide a `.storage` getter that copies the `v128` data into a transient `Float64List`.
*   **Strategy B (Engine Specialization)**: Update the Wasm implementation of `dart:ui` to accept Wasm-native SIMD storage directly, bypassing the `Float64List` requirement.
*   **Strategy C (Vectorized List)**: Back the standard `Float64List` implementation on Wasm with `WasmArray<WasmV128>`.

### 3. Performance Trade-off (The "Math Dividend")
*   **The Loss**: Accessing a single `double` (e.g., `matrix.entry(0,0)`) sees a **1.69x slowdown** compared to native `f64` access.
*   **The Win**: Core math operations see **10x-13x speedups**.
*   **Conclusion**: In a rendering framework like Flutter, where math complexity vastly outweighs simple scalar property access, this is a massive net win. We should prioritize the **Math Dividend**.

---

## Area 3: Layout Primitives (AABB & Bounding Boxes)
**Status**: The "Bread & Butter" operations

*   **Objective**: Optimize the specific logic used in `MatrixUtils.transformRect` and `absoluteRotate`.
*   **Method**: 
    *   Mirror the logic in `painting/matrix_utils.dart`.
    *   Verify that `WasmF64x2.min`, `.max`, and `.abs` are correctly intrinsified to low-level Wasm instructions.
*   **Success Metric**: Maintain the 13x speedup seen in micro-benchmarks when integrated into a realistic "simulated" layout loop.

## Area 4: Compilation Efficiency (Constant Lowering)
**Status**: Code Size & Startup

*   **Objective**: Ensure common constants (Identity, Zero) are zero-cost.
*   **Method**: 
    *   Verify that `const` SIMD instances are lowered to the Wasm data section.
    *   Inspect `.wat` output to confirm no runtime constructor calls for `const Matrix4.identity()`.
*   **Success Metric**: Inspection shows `v128.const` or single memory loads for all `const` math primitives.

---

## Execution Order
1.  **[CURRENT] Area 1**: Prototype SIMD Matrix Inversion (The hardest math).
2.  **Area 3**: Verify Layout Primitives (The most common math).
3.  **Area 2**: Optimize Memory Interop (The performance bridge).
4.  **Area 4**: Finalize Constant Lowering (The polish).
