# Socket2 Implementation Plan

## Background & Motivation
The current `Socket` API in `dart:io` uses a `Stream<List<int>>` paradigm, which is built on a readiness-based model (similar to traditional `epoll`). While functional, this approach introduces overhead (allocations, copying, GC pressure) that limits peak throughput and scalability for high-performance applications like HTTP clients, web servers, and database drivers.

`Socket2` aims to be a best-in-class, high-performance socket API for Dart. Drawing inspiration from modern frameworks like Rust's `tokio-uring`, it will use an **ownership-based completion model**. This allows for true zero-copy operations, maximizing bytes-per-second and minimizing CPU and GC overhead.

## Scope & Impact
- **New API**: Introduce `Socket2` (or a similar naming convention) in `dart:io` as an advanced, opt-in alternative to `Socket`.
- **Target Audience**: Savvy developers building foundational networking libraries (HTTP, RPC, databases) rather than casual end-users.
- **C++ Backend**: Implement the heavy lifting in the Dart VM's C++ layer (`runtime/bin/`).
- **Initial Platform Support**: Due to current environment constraints, the initial implementation will focus on macOS using `kqueue`. The architecture will be designed to easily accommodate Linux (`io_uring`/`epoll`) and Windows (`IOCP`) in the future.

## Proposed Solution

### 1. Dart API Layer (The Interface)
Move away from `Stream` to an **ownership-passing paradigm** using Futures. The user provides a buffer to the socket, yielding ownership until the operation completes.

```dart
// Conceptual API
class ReadResult {
  final int bytesRead;
  final ByteBuffer buffer; // Ownership returned
  ReadResult(this.bytesRead, this.buffer);
}

abstract class Socket2 {
  // ... connection methods ...

  /// Initiates a read, taking ownership of [buffer].
  /// The future completes with the buffer and the number of bytes read.
  Future<ReadResult> read(ByteBuffer buffer);

  /// Initiates a write, taking ownership of [buffer].
  Future<WriteResult> write(ByteBuffer buffer);
}
```

### 2. C++ VM Layer (The Engine)
- **Abstraction**: Create a C++ abstraction over OS-specific async APIs that supports the completion model.
- **kqueue Implementation**: Build the initial backend using macOS `kqueue`.
- **Zero-Copy**: Implement mechanisms to read/write directly to memory visible to Dart (e.g., pinning `TypedData` or using direct memory allocation) to avoid intermediate copies between kernel space, native space, and Dart space.

### 3. Buffer Management
Encourage the use of buffer pooling to eliminate allocations during steady-state network operations.

## Alternatives Considered
- **Enhancing Existing `Socket`**: Rejected. The existing `Stream` API is fundamentally readiness-based and changing it would break the vast ecosystem built on `dart:io`.
- **Callback-driven Readiness**: Rejected. Familiar to C/epoll developers, but less safe than ownership passing and less optimal for future integration with modern APIs like `io_uring`.

## Implementation Plan
1.  **Phase 1: API Definition**: Define the Dart `Socket2` interface and any necessary buffer management primitives in `sdk/lib/io/`.
2.  **Phase 2: C++ Engine (macOS)**: Implement the async completion behavior by integrating with the Dart VM's existing `EventHandler` (`kqueue` backend) to wait for readiness, executing operations upon notification to simulate completion.
3.  **Phase 3: FFI / Native Binding**: Connect the Dart `Socket2` API to the C++ backend using `@pragma("vm:external-name")` and the existing `_EventHandler` infrastructure (`_EventHandler._sendData`) to listen for completion events via a `RawReceivePort`.
4.  **Phase 4: Testing & Benchmarking**: Write unit tests and benchmarks to validate functionality and measure throughput/GC improvements against the legacy `Socket`.

## Verification
-   **Correctness**: Comprehensive test suite covering edge cases, partial reads/writes, and connection drops.
-   **Performance**: Benchmarks demonstrating significant improvements in throughput and reduced GC pauses compared to the existing `Socket`.

## Migration & Rollback
-   **Migration**: `Socket2` is an opt-in API. No existing users are forced to migrate. `HttpClient` and other internal tools can be migrated progressively once the API is stable.
-   **Rollback**: As a new, additive API, rollback simply involves deprecating or removing the `Socket2` classes.
