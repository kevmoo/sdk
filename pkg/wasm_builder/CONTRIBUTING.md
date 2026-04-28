# Contributing to `pkg/wasm_builder`

This package defines the IR (Intermediate Representation) and the builder API
for generating WebAssembly binaries.

## Instruction Encoding

When adding new instructions, pay close attention to how they are serialized
in `lib/src/ir/instruction.dart`.

### Multi-byte Opcodes (SIMD and Atomic)

Most WebAssembly instructions have a single-byte opcode. However, SIMD and
Atomic instructions use a prefix byte followed by an LEB128 encoded sub-opcode.

*   **SIMD Prefix**: `0xFD`
*   **Atomic Prefix**: `0xFE`

Example of a SIMD memory instruction serialization:

```dart
@override
void serialize(Serializer s) {
  s.writeByte(0xFD);
  s.writeUnsigned(0x0B); // Opcode for v128.store
  memory.serialize(s);   // alignment and offset
}
```

**Crucial Note**: Do not rely on the `encoding` field in the `MemoryInstruction`
base class for multi-byte opcodes. The base class `serialize` method only writes
a single byte. Overriding `serialize` completely is safer for prefixed
instructions.

## Builder API vs. IR

*   **IR (`lib/src/ir/`)**: Defines the data structures representing the Wasm
    module (functions, globals, instructions).
*   **Builder (`lib/src/builder/`)**: Provides a fluent API for emitting
    instructions.

When adding an instruction to the builder in `lib/src/builder/instructions.dart`,
always include:
1.  A call to `_verifyTypes` to ensure the stack state is correct.
2.  A `trace` entry that matches the Wasm text format (e.g., `v128.load`).
3.  A call to `_add` with the corresponding IR node.

## Testing

Run tests using the standard Dart test runner or via `tools/test.py` in the
SDK root.

```bash
dart test
# or from SDK root:
python3 tools/test.py -c dart2wasm -r d8
```
