# Wasm2Kernel: Milestone 1 - It Works!

## Summary
We have successfully translated a basic WebAssembly module into a functional, executable Dart Kernel file. The "add" function, implemented in Wasm, was executed natively by the Dart VM as a generated Dart method.

## Achievements

### 1. Successful Toolchain Integration
- **Source:** Hand-written `.wat` file.
- **Assembly:** Compiled to `.wasm` using `wat2wasm`.
- **Translation:** Processed by our `WasmToKernel` translator.
- **Linking:** Correctly linked against the Dart SDK's `vm_platform_strong.dill` to resolve `dart:core` types and operators.
- **Execution:** The resulting `.dill` file was executed by the Dart VM and produced the correct output (`42`).

### 2. IR Mapping Success
- **Locals:** `local.get` mapped to Kernel `VariableGet`.
- **Arithmetic:** `i32.add` mapped to a Kernel `InstanceInvocation` of the `+` operator on the `int` class.
- **Structure:** Wasm functions are encapsulated in a `WasmModule` class, with an auto-generated `main` method for testing.

## Technical Details

### Symbolic Stack implementation
The translator uses a `List<Expression>` as a symbolic stack. For `i32.add`, it pops two expressions and pushes a new `InstanceInvocation` node. This preserves the evaluation order and semantics of Wasm within the tree-based Kernel IR.

### Platform Linking
By sharing the `CanonicalName` root with the SDK's platform DILL, the translator can create "native" references to `int`, `print`, and other core members. This ensures that the VM's JIT compiler recognizes these operations as standard Dart primitives, enabling maximum performance.

## Next Steps
- Support for constants (`i32.const`).
- Support for multiple Wasm functions and inter-function calls.
- Handling of structured control flow (`block`, `loop`, `if`).
- Implementation of linear memory using `ByteData`.
