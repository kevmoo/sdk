# Wasm2Kernel: Testing and Validation Strategy

## Programmatic Test Generation
To avoid dependencies on external tools like `wat2wasm`, we will use the SDK's own `pkg/wasm_builder` to generate sample Wasm modules for testing. This ensures that our test inputs are compatible with the SDK's IR from the start.

### Target 1: Basic Arithmetic (`add.wasm`)
A simple function to verify the symbolic stack and basic operator mapping.
- **Wasm:** `(func (param i32 i32) (result i32) (i32.add (local.get 0) (local.get 1)))`
- **Expected Kernel:** A method that takes two `int`s, adds them, and masks the result with `0xFFFFFFFF`.

### Target 2: Control Flow (`factorial.wasm`)
A function using `loop` and `br_if` to verify structured control-flow reconstruction.
- **Wasm:** A standard recursive or iterative factorial implementation.
- **Expected Kernel:** A `WhileStatement` or recursive `StaticInvocation` with proper `BreakStatement` logic.

### Target 3: Linear Memory (`sum_array.wasm`)
A function that iterates over linear memory and sums values.
- **Wasm:** Uses `i32.load` in a loop.
- **Expected Kernel:** Iterative access to a `ByteData` field using `getInt32`.

## Validation Pipeline
Each test case will follow this lifecycle:
1. **Generate Wasm:** Use `ModuleBuilder` to create the `.wasm` file.
2. **Translate:** Run the `Wasm2Kernel` translator to produce a `.dill` file.
3. **Execute:** Run the `.dill` file using the Dart VM.
4. **Assert:** Compare the actual output with the expected result.

## Tooling
We will create a helper utility `tool/generate_samples.dart` that populates a `test_data/` directory with these `.wasm` binaries. This directory will then serve as the input for our translator's test suite.
