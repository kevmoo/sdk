# Wasm2Kernel: Implementation & Validation Plan

## Goal
To achieve a complete and verified WebAssembly to Dart Kernel translator by systematically passing the official WebAssembly Spec Test suite.

## The Validation Model: Spec-Driven Development

### 1. Source Material
We utilize the official WebAssembly spec tests (`.wast` files), which contain both Wasm modules and detailed assertions.

### 2. Test Transformation
Since we cannot parse `.wast` files directly, we use the `wast2json` tool from the WABT toolkit:
- **Input:** `test.wast`
- **Output:** `test.json` (a manifest of commands) and multiple `.wasm` binary files (one for each module defined in the spec).

### 3. The Spec Test Harness
We will build a specialized tool, `pkg/wasm2kernel/tool/spec_harness.dart`, which:
1. Parses the generated `.json` manifest.
2. For each module: Translates the `.wasm` to a Kernel DILL file.
3. For each `invoke` or `assert_return`:
   - Generates a small Dart "wrapper" that imports the translated module.
   - Executes the call and compares the result against the spec expectation.
   - Reports success or failure.

## Implementation Roadmap (Tiered Approach)

| Tier | Category | Instructions | Purpose |
| :--- | :--- | :--- | :--- |
| **Tier 1** | **Core Numerics** | `i32.*`, `i64.*`, `f32.*`, `f64.*` | Basic arithmetic, bitwise ops, and constants. |
| **Tier 2** | **State** | `local.*`, `global.*` | Variables and module-level state. |
| **Tier 3** | **Control Flow** | `block`, `loop`, `if`, `br`, `br_if` | Structured flow and branching. |
| **Tier 4** | **Memory** | `load`, `store`, `memory.*` | Linear memory access via `ByteData`. |
| **Tier 5** | **Advanced** | `call_indirect`, `br_table` | Dynamic dispatch and complex tables. |

## Progress Tracking
We will maintain a `SPEC_STATUS.md` file in the root of the project to track passing/failing spec tests and ensure we are making measurable progress toward 100% compliance.
