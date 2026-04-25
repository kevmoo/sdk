# Handover Notes for the Next Agent

Hello! You are picking up on Project Socket2 in the Dart SDK. Here is the
current state and what you need to know to continue.

## Current State
- **Feature**: `Socket2` is a high-performance, zero-copy, completion-based
  socket API for Dart.
- **Status**: The basic implementation is in place and functional. All tests in `tests/standalone/io/socket2_robustness_test.dart` now complete successfully!
- **Completed in Section 1**:
    - **Zero-length Reads/Writes**: Fixed a hang where empty buffers caused the
      implementation to wait indefinitely.
    - **Connection Drops**: Verified `SocketException` propagation.
    - **Simultaneous Read/Write**: Verified it works without corruption.
    - **Protocol Violations**: Verified that calling `read()` twice throws
      `StateError`.
    - **Address Resolution**: Verified localhost and invalid domains.
    - **Partial Writes**: Verified with a 1MB payload after solving an event
      loop starvation issue.
    - **Unhandled Exceptions**: Fixed unhandled exceptions during test execution in `testReadTwiceThrows` and `testConnectionDropDuringRead` by attaching error listeners *before* triggering operations that fail.
    - **Resource Cleanup**: Bypassed `RawSocket` and `RawServerSocket` to avoid leaking event handlers and stream controllers.

## Active Issue: Post-Exit Unhandled Exception
While all tests in `tests/standalone/io/socket2_robustness_test.dart` now complete and `main()` exits normally, the test runner still reports an unhandled exception *after* exit:
```
Unhandled exception:
SocketException: Socket closed
```
This does not go through our instrumentation in `_completeAllWithError` in `socket2_patch.dart`. It is likely happening in the native event handler thread during isolate teardown when it tries to deliver an event to a port that has been closed or is shutting down.

## Next Steps
1.  **Investigate Native Teardown**: If you need to eliminate this post-exit error, you likely need to look at how the `EventHandler` interacts with `_NativeSocket` during isolate shutdown in the C++ runtime.
2.  **Assess Completion**: Alternatively, discuss with the user if passing all functional tests is sufficient for this stage, given that the error happens after the test logic completes.
3.  **Move to Next Sections**: Proceed to Section 2 (Documentation) or other sections in `SHIPPING_PLAN.md`.

## Useful Files
- `conductor/SHIPPING_PLAN.md`: The TODO list.
- `conductor/STUMBLES.md`: Read items #11 and #12 for context on the recent fixes regarding unhandled exceptions.
- `conductor/cheat_sheet_for_the_agent.md`: Commands for building and testing.

Good luck!
