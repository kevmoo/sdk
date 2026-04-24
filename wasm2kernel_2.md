# Wasm2Kernel: Serialization and Artifact Generation

## Top-Level Structure
A Kernel program is contained within a `Component` node. To generate a functional `.dill` file from Wasm, the following hierarchy is established:

1. **`Component`**: The root of the Kernel AST.
2. **`Library`**: A logical container for the translated module (e.g., `package:wasm_module/module.dart`).
3. **`Class`**: Represents the Wasm module itself (e.g., `class WasmModule`).
4. **`Field`**: Holds the linear memory as a `ByteData` or `Uint8List`.
5. **`Procedure`**: Each Wasm function is translated into a method within the `Class`.

## The Serialization Process
The `pkg/kernel/lib/kernel.dart` and `pkg/kernel/lib/binary/ast_to_binary.dart` files provide the necessary tools for serialization.

### Steps to Generate `.dill`
1. **Initialize Component**: `var component = Component();`
2. **Build Library**:
   ```dart
   var lib = Library(Uri.parse('package:wasm_module/module.dart'), fileUri: ...);
   component.libraries.add(lib);
   lib.parent = component;
   ```
3. **Populate AST**: Add the generated `Class`, `Field`s, and `Procedure`s to the library.
4. **Link References**: Use `CoreTypes` and `LibraryIndex` (loaded from the SDK's `vm_platform_strong.dill`) to resolve `interfaceTarget`s for bitwise operations and memory access.
5. **Write to File**:
   ```dart
   await writeComponentToBinary(component, 'output.dill');
   ```

## Standard Library Dependencies
Translation requires access to `dart:core` and `dart:typed_data` members. To ensure the generated Kernel is valid:
- **`interfaceTarget`**: Every `InstanceInvocation` (e.g., `a + b`) must point to the specific `Procedure` in the standard library.
- **Platform Loading**: The translator must load the platform's `dill` (e.g., `lib/src/outline.dill` in the SDK) into the `Component`'s name root to resolve these targets during generation.

## Execution Model
The resulting `.dill` file can be executed by the Dart VM:
```bash
dart output.dill
```
Alternatively, the `WasmModule` class can be imported and instantiated by other Dart code if the library is included in a larger compilation unit.
