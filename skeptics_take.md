# Wasm2Kernel: The Skeptic's Take & Feasibility Analysis

## Executive Summary

Translating WebAssembly (Wasm) bytecode directly into Dart Kernel Intermediate Representation (`.dill`) allows Wasm-compiled modules to run inside the Dart VM without native FFI or a standalone Wasm engine.

However, from an execution performance and spec compliance standpoint, `wasm2kernel` faces severe architectural impedance. It will **not** achieve near-native execution speeds, but it can serve as a **portable, zero-FFI sandbox** for targeted algorithmic workloads in pure-Dart environments.

---

## 1. The Bottom Line on Performance

* **Versus Native Wasm Engines (V8 / Wasmtime / Wasmer):** `wasm2kernel` will realistically run **3x to 10x slower** on CPU- and memory-intensive benchmarks.
* **Versus Dart FFI (Native C/Rust Shared Libraries):** Dart FFI executes native machine instructions with direct hardware register allocation and OS memory mapping; `wasm2kernel` runs through Dart VM managed byte code with mandatory bounds checks and integer masking.
* **Where It Shines:** Pure-Dart environments (sandboxes forbidding native binaries, platforms without C compilers, or self-contained pub packages needing zero platform-specific builds).

---

## 2. Critical Structural Impedances

### A. Numeric Type Mismatches & Arithmetic Bloat

* **The `f32` (Single-Precision Float) Gap:**
  * Dart has no 32-bit floating-point scalar type. Dart `double` is strictly 64-bit IEEE 754 (`f64`).
  * Promoting `f32` to `double` alters rounding, subnormal behavior, and NaN bit patterns, failing standard Wasm spec tests.
  * Forcing true 32-bit float truncation via `Float32List` or `ByteData` buffers on every operation introduces severe memory allocations and cache churn.
* **`i32` Continuous Masking Overhead:**
  * On the 64-bit Dart VM, `int` is a 64-bit signed integer. Every Wasm `i32` operation requires explicit 32-bit truncation: `(a + b).toSigned(32)` or `& 0xFFFFFFFF`.
  * Emitting these as `InstanceInvocation` AST nodes forces repeated register masking or sign-extension instructions (`movsxd`/`sarl`) unless optimized away by the VM's IL pipeline.
* **`i64` Unsigned Operations:**
  * Dart `int` is signed two's complement. Unsigned operations (`i64.div_u`, `i64.rem_u`, `i64.shr_u`) cannot fit in positive `int64` range without software emulation or `BigInt`.
  * Software emulation for unsigned 64-bit integer division is **50x to 100x slower** than native hardware `div`.
* **SIMD (`v128`):**
  * Wasm 128-bit vector instructions (`i8x16`, `i16x8`, `i64x2`, cross-lane shuffles) have no full equivalent in Dart's high-level language types.

---

### B. Linear Memory: Software Bounds Checks vs. Hardware Guard Pages

* **Hardware Guard Pages (Native Wasm Runtimes):**
  * Native runtimes allocate a 4GB+ virtual memory reservation bounded by guard pages. Memory access is a single raw pointer dereference with **zero software bounds checks**. An out-of-bounds access triggers a hardware memory fault (`SIGSEGV`) caught by the engine.
* **Software Bounds Checks (Dart Kernel AST):**
  * In `wasm2kernel`, linear memory is represented via `TypedData` (`ByteData` or `Uint8List`).
  * Every single load and store incurs:
    1. Dart VM software array index bounds check.
    2. Endianness conversion logic.
    3. Method call overhead if invoked via `ByteData.getInt32()`.
* **Throughput Impact:** Linear memory throughput in pure Dart will be 2x to 5x slower than direct pointer dereferencing in native Wasm engines.

---

### C. Control Flow & Stack Machine Impedance

* **Stack-to-Tree Mismatch:**
  * Wasm uses a flat, structured stack machine supporting multi-level breaks (`br <n>`, `br_table`) with arbitrary value passthrough on the operand stack.
  * Dart Kernel is a structured AST (`Block`, `LabeledStatement`, `BreakStatement`, `WhileStatement`).
* **Reconciliation Complexity:**
  * Exiting nested blocks while preserving active operand stack values requires generating temporary spill variables and synthetic dispatch loops.
  * This disrupts instruction cache locality and branch predictors in the Dart VM JIT/AOT compiler.

---

### D. Wasm Traps & Spec Compliance

* Wasm specifies deterministic traps for integer division by zero, float-to-int overflow, and memory bounds violations.
* Dart runtime exceptions (`IntegerDivisionByZeroException`, `RangeError`) deviate from Wasm trap behavior without heavy guard code wrapping each sensitive instruction.

---

## 3. Comparison Matrix

| Dimension | Native Wasm (V8 / Wasmtime) | Dart FFI (C / Rust) | wasm2kernel (Dart IR) |
| :--- | :--- | :--- | :--- |
| **Performance** | High (Near Native) | High (Native Speed) | Moderate (3x–10x slower) |
| **Bounds Checks** | Zero-cost (Guard Pages) | Manual / Unchecked | Managed (Software check) |
| **Portability** | Requires C++/Rust engine | Platform-specific `.so` | 100% Pure Dart `.dill` |
| **Safety** | Sandboxed | Unsafe (Crash risk) | Memory-safe inside VM |
| **Integration** | Heavy external dependency | FFI Marshalling overhead | Native Dart Object calls |

---

## 4. Where `wasm2kernel` Makes Sense vs. Dead Ends

### ❌ Dead Ends (Do Not Build For These)
* High-performance numeric compute, audio/DSP, raytracing, or machine learning.
* Drop-in replacement for `wasmtime` or `v8` in general application hosting.
* Complex Wasm extensions (Wasm GC, Threads/Atomics, SIMD).

### ✅ Viable Niches (Worth Pursuing)
* **Zero-FFI Algorithmic Libraries:** Running pure C/Rust libraries (e.g., `zstd`, `sqlite`, `brotli`, regex engines, image decoders) inside Flutter/Dart on platforms where dynamic libraries are difficult to distribute.
* **Monolithic Snapshots:** Compiling foreign code into standard Dart `.dill` files that bundle directly into AOT binary executables (`dart compile exe`).
