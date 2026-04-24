# Wasm2Kernel: Deep Dive into Instruction Translation

## Overview
This document details the mapping between WebAssembly (Wasm) instructions and Dart Kernel IR nodes. The translation leverages a symbolic expression stack and a control-flow stack to transform Wasm's stack-based, flat instruction list into Kernel's tree-based AST.

## Mapping Core Concepts

### 1. Values and Constants
Wasm constants map directly to Kernel literals.
- `i32.const` / `i64.const`: `IntLiteral(value)`
- `f32.const` / `f64.const`: `DoubleLiteral(value)`

### 2. Locals
Wasm locals (including parameters) map to Kernel `VariableDeclaration` nodes.
- `local.get <index>`: `VariableGet(variable)`
- `local.set <index>`: `VariableSet(variable, expression)`
- `local.tee <index>`: Encoded as a `VariableSet` nested within another expression (Kernel allows `VariableSet` to be an `Expression`).

### 3. Arithmetic and Logic
Wasm operators map to `InstanceInvocation` on the receiver (the first operand).
- `i32.add(a, b)`: `InstanceInvocation(a, Name('+'), Arguments([b]))`. 
- **Wrap-around Semantics:** For `i32` and `i64`, Wasm specifies bitwise wrap-around. In Dart, this is enforced by masking: `(a + b) & 0xFFFFFFFF`.
- **Comparison:** `i32.eq(a, b)`: `InstanceInvocation(a, Name('=='), Arguments([b]))`.

### 4. Linear Memory
Wasm memory is represented as a `ByteData` field in the generated Dart class.
- `i32.load(address)`: `InstanceInvocation(memoryField, Name('getInt32'), Arguments([address, Endian.little]))`.
- `i32.store(address, value)`: `InstanceInvocation(memoryField, Name('setInt32'), Arguments([address, value, Endian.little]))`.

## Control Flow Translation
Wasm's flat instruction list is reconstructed into a hierarchical AST using a **Control Stack**.

| Wasm Instruction | Kernel Representation |
| :--- | :--- |
| `block` | `LabeledStatement` containing a `Block` |
| `loop` | `LabeledStatement` containing a `WhileStatement(true, Block)` |
| `if` | `IfStatement` |
| `br <n>` | `BreakStatement(target: labeledStatementAtStackLevel(n))` |
| `end` | Closes the current control-flow node and pops the control stack. |

### Block Results
For blocks that return a value, the result is captured by setting a local variable before the `End` or by wrapping the block in an `ImmediatelyInvokedFunctionExpression` (IIFE).

## Symbolic Stack Algorithm
To convert from stack-based to tree-based IR:
1. Initialize an empty `List<Expression> stack`.
2. For each instruction:
   - If it produces values (e.g., `i32.const`), push the corresponding Kernel `Expression` onto the `stack`.
   - If it consumes values (e.g., `i32.add`), pop the required number of `Expression`s, combine them into a new `Expression`, and push the result back.
3. If an instruction marks the start of a block (`block`, `loop`, `if`), it captures the current `stack` state and starts a new one for the block's scope.
