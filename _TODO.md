# SDK Compilation & Kernel Generation

## Problem: `dart compile kernel` errors
Running `dart compile kernel example/main.dart` on code that depends on `dart:js_interop` or `package:web` fails because:
1. `dart compile kernel` defaults to the **VM target**.
2. The VM target does not include web-only libraries like `dart:js_interop`.
3. The CFE (Common Front End) refuses to compile when these platform libraries are missing from the target specification.

## Solution: Use a Web-targeted compiler
To get kernel bits for web libraries, you must use a compiler that knows about web targets (e.g., `wasm` or `dartdevc`).

### Option 1: Use `dart2wasm` (Best for text kernel)
`dart2wasm` can dump the kernel at various stages. This command uses the AOT snapshot from a built SDK:

```bash
# From within the qr.dart directory
SDK_PATH=~/github/dart/sdk/xcodebuild/ReleaseARM64/dart-sdk

$SDK_PATH/bin/dartaotruntime $SDK_PATH/bin/snapshots/dart2wasm_product.snapshot \
  --platform=$SDK_PATH/lib/_internal/dart2wasm_platform.dill \
  --dump-kernel-after-cfe=example/main_cfe.txt \
  example/main.dart example/main.wasm
```

### Option 2: Use `frontend_server` (Best for .dill output)
`frontend_server` allows you to explicitly set the target to `dartdevc` and provide the web-specific libraries specification:

```bash
# From within the qr.dart directory
SDK_PATH=~/github/dart/sdk/xcodebuild/ReleaseARM64/dart-sdk

$SDK_PATH/bin/dartaotruntime $SDK_PATH/bin/snapshots/frontend_server_aot.dart.snapshot \
  --sdk-root $SDK_PATH/ \
  --libraries-spec $SDK_PATH/lib/libraries.json \
  --target=dartdevc \
  --platform $SDK_PATH/lib/_internal/ddc_platform.dill \
  --output-dill=example/main.dill \
  example/main.dart
```

## Parsing and Tracing Kernel
You can parse and analyze `.dill` files using `package:kernel`.

### Running Analysis Scripts
To run a script that uses `package:kernel` from within the SDK root:
```bash
dart --packages=.dart_tool/package_config.json your_script.dart your_file.dill
```

### Insights
- **Entry Point**: `component.mainMethod` is the starting point of the program.
- **Graph Structure**: Kernel is a graph of nodes linked by `Reference` objects.
- **Edges**: 
    - `StaticInvocation.target` -> The function being called.
    - `ConstructorInvocation.target` -> The constructor being called.
    - `StaticGet.target` -> The static field/getter being accessed.
- **Virtual/Instance Calls**:
    - `InstanceInvocation.interfaceTarget` -> The statically known interface member being called.
    - Kernel does **not** store a list of all possible runtime targets by default.
    - To find possible targets, you must use `ClassHierarchy` (from `package:kernel/class_hierarchy.dart`) to find all subclasses that override the `interfaceTarget`.
    - **TFA (Type Flow Analysis)**: During AOT compilation, TFA can resolve virtual calls to a specific set of targets. This information can be found in `DirectCallMetadata` if present in the component's metadata repositories.

### Tools
- `trace_main.dart`: Traces the call graph from `main` using Kernel structure.
- `trace_tfa.dart`: Runs Type Flow Analysis to find reachable members.

## Legacy TODOs
compile the sdk

./tools/build.py --mode release create_sdk
