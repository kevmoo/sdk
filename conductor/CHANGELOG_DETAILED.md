# Detailed Project Changelog

## Repository: `dart/sdk`

### New Files
- `sdk/lib/io/socket2.dart`: The public abstract interface for `Socket2` and `ServerSocket2`.
- `sdk/lib/_internal/vm/bin/socket2_patch.dart`: The VM-specific implementation that bridges the public API to the C++ runtime.
- `runtime/bin/socket2.h`: Header for the new C++ I/O primitives.
- `runtime/bin/socket2.cc`: Implementation of the native bindings for `ReadInto` and `WriteFrom`.

### Modifications
- `sdk/lib/io/io.dart`: Added `part 'socket2.dart';`.
- `sdk/lib/_internal/vm/bin/common_patch.dart`: Added `part 'socket2_patch.dart';`.
- `sdk/lib/_internal/vm/bin/vm_internal_bin.gni`: Registered the new patch file in the build system.
- `runtime/bin/io_natives.cc`: Registered `Socket2_ReadInto` and `Socket2_WriteFrom` native functions.
- `runtime/bin/io_impl_sources.gni`: Registered `socket2.cc` and `socket2.h` for compilation.

---

## Repository: `shelf`

### New Files
- `pkgs/bottom_shelf/lib/src/socket2_shelf_server.dart`: A new, optimized Shelf server loop built entirely on `Socket2`.
- `pkgs/bottom_shelf/test_socket2_shelf.dart`: End-to-end integration test for the new server.
- `pkgs/bottom_shelf/benchmark_server.dart`: High-throughput benchmarking server for `Socket2`.
- `pkgs/bottom_shelf/benchmark_raw_server.dart`: High-throughput benchmarking server for `Socket1` (baseline).

### Modifications
- `pkgs/bottom_shelf/lib/bottom_shelf.dart`: Exported the new `Socket2ShelfServer`.
- `pkgs/bottom_shelf/benchmark/benchmark_handler.dart`: Fixed file paths for consistent benchmarking.
