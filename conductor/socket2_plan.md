# Socket2 Implementation Plan (Updated April 2026)

## Background & Motivation
The current `Socket` API in `dart:io` uses a `Stream<List<int>>` paradigm, which is built on a readiness-based model (similar to traditional `epoll`). While functional, this approach introduces overhead (allocations, copying, GC pressure) that limits peak throughput and scalability for high-performance applications like HTTP clients, web servers, and database drivers.

`Socket2` aims to be a best-in-class, high-performance socket API for Dart. Drawing inspiration from modern frameworks like Rust's `tokio-uring`, it uses an **ownership-based completion model**. This allows for true zero-copy operations, maximizing bytes-per-second and minimizing CPU and GC overhead.

## Scope & Impact
- **New API**: Introduce `Socket2` and `ServerSocket2` in `dart:io` as an advanced, opt-in alternative to `Socket`.
- **Target Audience**: Savvy developers building foundational networking libraries (HTTP, RPC, databases).
- **C++ Backend**: Leverages the Dart VM's C++ layer (`runtime/bin/`) via the existing `EventHandler`.
- **Platform Support**: Verified on macOS (`kqueue`). The "hijack" architecture is designed to be cross-platform, working with existing `epoll` and `IOCP` backends in the VM.

## Finalized Solution

### 1. Dart API Layer (Named Records)
The API uses an **ownership-passing paradigm** with `Future<({int bytes, TypedData buffer})>`. The user provides a buffer to the socket, yielding ownership until the operation completes.

```dart
abstract interface class Socket2 {
  /// Initiates a read, taking ownership of [buffer].
  /// Returns a record containing the bytes read and the buffer.
  Future<({int bytes, TypedData buffer})> read(TypedData buffer);

  /// Initiates a write, taking ownership of [buffer].
  Future<({int bytes, TypedData buffer})> write(TypedData buffer);
}
```

### 2. C++ VM Layer (The "Hijack" Strategy)
Instead of building a new OS-specific async layer, the implementation "hijacks" the Dart VM's existing `EventHandler`.
- **Direct Pointers**: Uses `Dart_TypedDataAcquireData` to pin Dart memory, allowing native `read`/`write` syscalls to operate directly on Dart-owned buffers.
- **Zero-Copy**: Eliminates the intermediate copy between the OS kernel and Dart heap.

### 3. Strategic Modifications to `_NativeSocket`
To enable the "Hijack" strategy without regressing existing code, surgical changes were made to `sdk/lib/_internal/vm/bin/socket_patch.dart`:
- **API Distinction**: Added an `isSocket2` flag to `_NativeSocket` to apply performance-tuned logic only to new sockets.
- **Low-Latency Multiplexing**: Modified `multiplex()` to call handlers directly for `Socket2`, bypassing legacy microtask scheduling and eliminating the "available bytes" polling lag on macOS.
- **Controlled Interest Masks**: Enhanced `setListening()` with an `issueEvents` flag to allow silent OS interest mask updates, preventing CPU-intensive "busy-wait" loops during async completions.

### 4. Buffer Management
Highly efficient when used with buffer pooling. Benchmarks show **zero steady-state allocations** during high-throughput transfers.

## Alternatives Considered
- **Enhancing Existing `Socket`**: Rejected. Fundamentally readiness-based; changing it would break the ecosystem.
- **New IO Loop**: Rejected. Extending the existing `EventHandler` provided cross-platform support with significantly less complexity.

## Implementation Status

1.  **Phase 1: API Definition [COMPLETED]**: Defined `Socket2` and `ServerSocket2` interfaces in `sdk/lib/io/`.
2.  **Phase 2: C++ Engine [COMPLETED]**: Implemented `Socket2_ReadInto` and `Socket2_WriteFrom` in the VM.
3.  **Phase 3: Native Binding [COMPLETED]**: Integrated with `_NativeSocket` to intercept events via `RawReceivePort`.
4.  **Phase 4: Testing & Benchmarking [COMPLETED]**:
    - **Throughput**: ~1.5 GB/s (3.3x improvement over legacy `Socket`).
    - **Robustness**: Comprehensive test suite covering edge cases and simultaneous IO.

## Next Steps
- **Cross-Platform Verification**: Verify stability and performance on Linux (`epoll`) and Windows (`IOCP`).
- **Experimental Flag**: Hide the API behind `--enable-socket2` for the initial release.
  - **OR** annotate them as experimental and release without the flag.
- **Internal Migration**: Explore migrating `HttpClient` or `HttpServer` to use `Socket2` internally for performance gains.
  - **OR** Deprecate `HttpClient` and `HttpServer` and move this logic to packages.

## Verification
-   **Correctness**: Verified via `tests/standalone/io/socket2_robustness_test.dart`.
-   **Performance**: Verified via `benchmarks/socket2_throughput.dart`.
