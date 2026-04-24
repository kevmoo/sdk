# Wasm2Kernel: Executing WebAssembly as Native Dart IR

## The Concept
The goal is to create a "Wasm Frontend" for the Dart VM. By translating WebAssembly (Wasm) binary modules directly into Dart Kernel IR (`.dill`), we can execute Wasm-implemented algorithms as native code within the Dart VM, bypassing FFI overhead and separate runtime requirements.

## Current Findings

### 1. Wasm Deserialization
The SDK already possesses the capability to parse Wasm binaries.
- **Location:** `pkg/wasm_builder/lib/src/serialize/deserializer.dart` and `pkg/wasm_builder/lib/src/ir/module.dart`.
- **Capability:** `Module.deserialize(Deserializer d)` can take a byte array and produce a structured Wasm IR.
- **Instructions:** `Instruction.deserialize` exists for the full Wasm instruction set, providing the necessary hooks to traverse and translate Wasm logic.

### 2. Kernel Generation
The `pkg/kernel` package provides the standard API for building Dart IR.
- **AST Nodes:** `Procedure`, `FunctionNode`, `Block`, `VariableDeclaration`, and various `Expression` nodes are available to reconstruct Wasm logic.
- **Target:** We can generate a standalone Library or Class that represents the Wasm module, where Wasm functions become Dart methods.

## Proposed Translation Strategy

### Memory Mapping
Wasm linear memory can be mapped to a `Uint8List` or `ByteData` field in a generated "Wasm Module" class. 
- `i32.load`: Translated to a `MethodInvocation` on the `ByteData` buffer (e.g., `buffer.getInt32(address)`).
- `i32.store`: Translated to `buffer.setInt32(address, value)`.

### Stack-to-Tree Translation
Wasm is stack-based, while Kernel is tree-based (AST). This is resolved using a **Symbolic Stack** during translation:
- Maintain a `List<Expression>` during the translation of each function.
- **Push:** Wasm instructions like `local.get` or `i32.const` push a new Kernel `VariableGet` or `IntLiteral` onto the stack.
- **Pop:** Instructions like `i32.add` pop two expressions from the symbolic stack, combine them into a `MethodInvocation` (for `+`), and push the result back onto the stack.
- **Finality:** At the end of a block or function, the symbolic stack should contain the resulting expression(s).

### Semantics & Types
- **Integers:** Wasm `i32` and `i64` map to Dart `int`. 32-bit wrap-around is handled with bitwise masking (`& 0xFFFFFFFF`).
- **Floats:** Wasm `f64` maps to Dart `double`. `f32` may require specific handling via `Float32List` to preserve 32-bit precision if needed.
- **Control Flow:** Wasm's structured control flow (`block`, `loop`, `if`, `br`) maps to Kernel's `Block`, `WhileStatement`, `IfStatement`, and `BreakStatement`.

## Advantages
- **Performance:** Leverages the Dart VM's JIT/AOT compilers for the translated Wasm code.
- **Interoperability:** Seamless data sharing via `TypedData` between Dart and Wasm.
- **Portability:** Resulting `.dill` files are standard Dart artifacts.
