# Technical Breakthroughs

Several key architectural decisions allowed `Socket2` to achieve "best-in-class" performance with very little code.

## 1. The "Hijack" Strategy
The biggest breakthrough was realizing we didn't need to rebuild the OS event loop. By extending `_NativeSocket` and manually setting the `RawReceivePort` handler, we were able to "hijack" the existing Dart VM `EventHandler`.
*   **Impact**: We gained multi-platform support (kqueue, epoll, IOCP) for free. We also gained all of Dart's existing connection logic (DNS resolution, IPv6 dual-stack, etc.) while still exposing a completely different, high-performance API to the user.

## 2. Ownership-Passing via Records
Replacing the `Stream` paradigm with `Future<({int bytes, TypedData buffer})>` was the "Aha!" moment for performance.
*   **Impact**: It explicitly forces the user to think about who "owns" the memory. By returning the buffer in the Future, we enable a perfectly zero-copy pipeline where a single piece of RAM can flow from the OS kernel, into Dart for parsing, and back to the kernel for response, without ever being copied or allocated during the steady state.

## 3. Direct Pointer Access (`Dart_TypedDataAcquireData`)
Instead of copying bytes into a `List<int>` or `Uint8List`, we used the VM's native ability to "pin" memory.
*   **Impact**: The C++ `write()` and `read()` syscalls operate directly on the memory address of the Dart `TypedData` object. This eliminates the "Double-Copy" problem (Kernel -> Native -> Dart) that plagues many managed language runpoints.

## 4. Named Records for Ergonomics
The user's prompt to use **Named Records** was a significant breakthrough for the API's usability. 
*   **Impact**: Changing `result.$1` to `result.bytes` made the code self-documenting and reduced the likelihood of developer error, without adding the overhead of a formal "Result" class object.
