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
# Assuming SDK_PATH is the path to your built dart-sdk (e.g. xcodebuild/ReleaseARM64/dart-sdk)
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

## Legacy TODOs
compile the sdk

./tools/build.py --mode release create_sdk
