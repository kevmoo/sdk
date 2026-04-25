# Handover Notes for the Next Agent

Hello! You are picking up on Project Socket2 in the Dart SDK. Here is the
current state and what you need to know to continue.

## Current State
- **Feature**: `Socket2` is a high-performance, zero-copy, completion-based
  socket API for Dart.
- **Status**: The basic implementation is in place and functional. We are
  currently working on Section 1 of the `SHIPPING_PLAN.md` (Robustness & Edge
  Case Testing).
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

## Active Issue: Unhandled SocketException
The tests in `tests/standalone/io/socket2_robustness_test.dart` are failing
with an unhandled exception:
```
Unhandled exception:
SocketException: Socket closed
```
This happens after `testPartialWrite` completes (it seems to pass based on
prints). It might be triggered by `testCloseCancelsPendingRead` or one of the
earlier tests leaving a pending future that fails when the socket is closed in
cleanup.

I have tried to:
- Complete pending futures in `_Socket2Impl.close()` with a "Socket closed"
  error (in `socket2_patch.dart`).
- Handle errors in tests using `catchError` and `Future.wait`.
- But the exception is still reported as unhandled by the test runner.

## Next Steps
1.  **Debug the Unhandled Exception**: You need to find which Future is
    completing with an error and has no listener attached in the same
    microtask.
    - Check `tests/standalone/io/socket2_robustness_test.dart`.
    - Check `sdk/lib/_internal/vm/bin/socket2_patch.dart`.
    - Try to run tests individually to isolate the failing one (you can comment
      out calls in `main()`).
2.  **Finish Section 1 of Shipping Plan**: Once the exception is fixed, you can
    check off "Resource Cleanup" if the test passes.
3.  **Move to Next Sections**: Proceed to Section 2 (Documentation) or other
    sections in `SHIPPING_PLAN.md`.

## Useful Files
- `conductor/SHIPPING_PLAN.md`: The TODO list.
- `conductor/STUMBLES.md`: Read items #7, #8, #9, and #10 for context on recent
  fixes.
- `conductor/cheat_sheet_for_the_agent.md`: Commands for building and testing.

Good luck!
