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
**Status**: The "Bridge" Problem

*   **Objective**: Minimize the overhead of loading data from `Float64List` into SIMD registers.
*   **Method**: 
    *   Benchmark transformation of a `Float64List` containing 1,000 points.
    *   **New Feature**: Investigate adding a `dart2wasm` intrinsic for direct `v128.load` from a `TypedData` backing buffer, bypassing the `list[i]` scalar extraction and boxing.
*   **Success Metric**: SIMD should be faster than scalar even when including the cost of loading/storing from a standard Dart list.

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
