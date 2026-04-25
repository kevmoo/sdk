# Project Stumbles

Developing a high-performance Socket API in the heart of the Dart VM provided several opportunities for "learning experiences."

## 1. The "Newline" Build Failure
When first adding the C++ files (`socket2.cc`, `socket2.h`, etc.), the build failed because I forgot a trailing newline at the end of the files. The Dart SDK build system uses very strict clang flags (`-Werror`, `-Wnewline-eof`).
*   **Lesson**: Always ensure C++ headers and source files end with a blank line.

## 2. ByteBuffer vs. TypedData
I initially designed the API around `ByteBuffer`. While technically correct for raw memory, it proved unergonomic in Dart. To do anything with a `ByteBuffer`, you almost always have to wrap it in a `Uint8List` view first.
*   **Stumble**: The native binding `Dart_TypedDataAcquireData` failed when passed a `ByteBuffer` because it specifically expects a `TypedData` object.
*   **Fix**: Migrated the entire API to use `TypedData`, which allows for easier slicing via `Uint8List.sublistView`.

## 3. The `null` check operator crash
During the transition from `Future<(int, TypedData)>` to named records, I introduced a bug where I was awaiting a Completer's future *after* I had potentially completed and nulled it out in the same microtask.
*   **Error**: `Null check operator used on a null value` in `socket2_patch.dart`.
*   **Fix**: Captured the future into a local variable before initiating the async operation, ensuring it remained stable even if the completer was cleared.

## 4. The Loopback Throughput Trap
My first benchmark returned a 2-byte "ok". I was surprised to see that `Socket2` and `Socket1` had nearly identical Requests-per-Second.
*   **Stumble**: I was benchmarking the **Event Loop overhead**, not the **I/O throughput**.
*   **Correction**: Switched to a 1.3MB payload. This immediately revealed the "Slam Dunk" performance gap where `Socket2` crushed `Socket1` by 3.3x in bandwidth and 360x in latency.

## 5. Partial Writes
I initially forgot that `write()` syscalls can be partial. If the OS socket buffer is full, it might only take 64KB of a 1MB buffer. My first benchmark code just "fired and forgot" the write, leading to broken HTTP responses in `wrk`.
*   **Fix**: Implemented an async `while` loop in the server code to ensure the entire buffer is consumed across multiple `Socket2.write` calls.

## 6. The Missing Port Getter
While writing tests for `Socket2`, I realized that `ServerSocket2` does not
expose the port it is bound to. This is problematic when binding to port 0
(random available port).
*   **Stumble**: I couldn't easily find the port to connect the client to in
    the test.
*   **Fix**: Used a hack `(server as dynamic)._socket.port` to access the
    private field for testing purposes. A future improvement should add a
    `port` getter to the interface.

## 7. The Dummy Class Compilation Error
After adding the `port` getter to the `ServerSocket2` interface and the
actual implementation in `socket2_patch.dart`, the build failed.
*   **Stumble**: The non-abstract class `_ServerSocket2` in `socket2.dart`
    (which acts as a dummy implementation) was missing the `port` getter
    implementation.
*   **Fix**: Added the `port` getter to `_ServerSocket2` with a throw of
    `UnimplementedError`.

## 8. Zero-Length Read/Write Hang
While testing edge cases, I found that passing an empty buffer to `read()` or
`write()` caused the test to time out.
*   **Stumble**: The C++ binding returned 0 (read 0 bytes), but the Dart
    implementation interpreted `result == 0` as "would block" and waited
    indefinitely for the next event.
*   **Fix**: Added early returns in Dart for empty buffers, returning
    immediately without making native calls.

## 9. Event Loop Starvation in Tests
The `testPartialWrite` test timed out because the server read loop never
started.
*   **Stumble**: The client loop was running in a microtask chain (since the
    initial writes completed immediately) and starved the event queue where
    the server read future was waiting to be scheduled.
*   **Fix**: Added `await Future.delayed(Duration.zero)` before the client
    loop to yield control to the event loop, allowing the server to start
    reading.
*   **Update**: I found that yielding once before the loop was not enough if
    the client loop writes fast in microtasks. I needed to yield *inside* the
    while loop as well to ensure the server gets scheduled to read.
