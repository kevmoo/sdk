# Proposal: Function Call Tracking in dart2wasm

This document outlines a plan to implement a "tag functions" feature in `dart2wasm` to enable precise function-level call tracking via manual instrumentation.

## 1. Objective
Add a compiler flag `--track-functions` that injects a tracking call at the entry point of every generated WebAssembly function. This allows for exact call counting and execution flow analysis in environments where sampling profilers might be insufficient or unavailable.

## 2. Compiler Changes

### 2.1. Option Definition
Add the new flag to both the high-level compiler options and the internal translator options.

*   **File:** `pkg/dart2wasm/lib/compiler_options.dart`
    *   Add `bool trackFunctions = false;` to `WasmCompilerOptions`.
*   **File:** `pkg/dart2wasm/lib/translator.dart`
    *   Add `bool trackFunctions = false;` to `TranslatorOptions`.
    *   Update `serialize` and `deserialize` in `TranslatorOptions` to persist this flag.

### 2.2. Tracking Function Import
The translator needs to define a Wasm import that the instrumentation will call.

*   **File:** `pkg/dart2wasm/lib/translator.dart`
    *   In the `Translator` class, define a `trackFunctionCall` imported function.
    ```dart
    late final w.BaseFunction trackFunctionCall = mainModule.functions.import(
      "dart2wasm", 
      "trackFunctionCall", 
      typesBuilder.defineFunction([w.NumType.i32], [])
    );
    ```

### 2.3. Code Generation Injection
Inject the call to the tracking function at the start of function bodies.

*   **File:** `pkg/dart2wasm/lib/code_generator.dart`
    *   Add a helper method to `AstCodeGenerator`:
    ```dart
    void _emitTrackingCall() {
      if (options.trackFunctions) {
        // Use the function's unique index as an ID
        b.i32_const(translator.functions.getFunctionId(enclosingMember));
        b.call(translator.trackFunctionCall);
      }
    }
    ```
    *   Call `_emitTrackingCall()` in `generateInternal` or specific entry-point methods (e.g., `_makeNonMultiEntryPointFunction`, `_makeMultipleEntryPointSharedBody`, and `SynchronousLambdaCodeGenerator.generate`).

## 3. Metadata Mapping
To make the data useful, we need a mapping from the integer IDs sent to JS back to Dart member names.

*   **File:** `pkg/dart2wasm/lib/translator.dart`
    *   During `translate()`, if `trackFunctions` is enabled, generate a JSON file (e.g., `output.wasm.map.json`) containing a map of `ID -> Member Name`.

## 4. JS Runtime Support
The JS loader needs to provide the actual tracking logic.

*   **File:** `pkg/dart2wasm/lib/js/runtime_generator.dart`
    *   Inject a tracking implementation into the `importObject`.
    ```javascript
    const functionCounts = new Uint32Array(maxFunctionId);
    const importObject = {
      dart2wasm: {
        trackFunctionCall: (id) => {
          functionCounts[id]++;
        },
      }
    };
    ```
    *   Provide a global helper (e.g., `dart2wasm_dumpCounts()`) to aggregate the results with the metadata mapping and print them to the console or return them as a JSON object.

## 5. Usage Example
1.  **Compile:**
    ```bash
    dart pkg/dart2wasm/bin/dart2wasm.dart --track-functions bin/my_app.dart out.wasm
    ```
2.  **Run:** Load the app in Chrome as usual.
3.  **Analyze:** Open DevTools Console and run:
    ```javascript
    // After exercising the app
    console.table(dart2wasm_dumpCounts());
    ```

## 6. Performance Impact
This will have a **significant** impact on execution speed and binary size. It is intended for targeted profiling and bottleneck identification in development/debugging builds only.
