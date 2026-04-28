# Contributing to `pkg/dart2wasm`

The `dart2wasm` compiler translates Dart code directly to WebAssembly.

## The Intrinsifier (`lib/intrinsics.dart`)

The intrinsifier is responsible for mapping specific Dart method calls to
low-level Wasm instructions.

### Type Conversions

Dart's standard `double` is equivalent to Wasm `f64`, and `int` is equivalent to
Wasm `i64`. When working with 32-bit types (like `WasmF32` or `WasmI32`), you
**must** perform explicit conversions in the generated Wasm:

*   **Double to F32**: `b.f32_demote_f64()`
*   **Int to I32**: `b.i32_wrap_i64()`

Example:
```dart
codeGen.translateExpression(node.arguments.positional[0], w.NumType.f64);
b.f32_demote_f64(); // Explicitly demote to f32 before calling splat
b.f32x4_splat();
```

### Constant Extraction

The compiler can optimize `const` instances of Wasm types. Use
`_extractDoubleValue` or `_extractIntValue` to pull literal values out of
expressions. For boxed Wasm types (like `WasmF64`), you must unwrap the
`InstanceConstant` first:

```dart
Expression unwrap(Expression e, Class expectedClass) {
  if (e is ConstantExpression) {
    final c = e.constant;
    if (c is InstanceConstant && c.classNode == expectedClass) {
      return ConstantExpression(c.fieldValues.values.single);
    }
  }
  return e;
}
```

### Return Types

Every `case` in `generateStaticInvocationIntrinsic` and
`generateConstructorInvocationIntrinsic` must return a `w.ValueType` (the type
left on the Wasm stack) or `codeGen.voidMarker` (if the instruction returns
nothing).

**Missing return types will cause `unreachable` errors at runtime!**

## Development Workflow

1.  **Build the SDK**: `tools/build.py -m release -a arm64 dart2wasm`
2.  **Run Tests**: `python3 tools/test.py -m release -c dart2wasm -r d8 <test_path>`

Always use the compiled SDK's `dart` binary for analysis and running tools to
ensure you are testing against your local changes to `dart:_wasm`.
