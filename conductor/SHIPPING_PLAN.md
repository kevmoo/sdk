# Roadmap to Shipping Socket2

This document outlines the remaining requirements and quality checks needed to move `Socket2` from a functional prototype to a production-ready feature in the Dart SDK.

## 1. Robustness & Edge Case Testing
Our current tests cover the "happy path" of connection and full buffer transfers. Before shipping, we must verify:
- [x] **Partial Reads/Writes**: Ensure the `while` loop logic is correct for all OS-level partial transfers.
- [x] **Zero-length Reads/Writes**: Define behavior when an empty `TypedData` is passed.
- [x] **Connection Drops**: Verify that `SocketException` is correctly propagated when the remote peer disconnects during a pending `read` or `write`.
- [x] **Simultaneous Read/Write**: Verify that `Future.wait([socket.read(b1), socket.write(b2)])` works without internal state corruption.
- [x] **Protocol Violations**: Add tests that attempt to call `read()` twice simultaneously (should throw `StateError`).
- [x] **Resource Cleanup**: Verify that `close()` cancels pending futures and frees C++ `Socket*` resources without leaking memory.
- [x] **Address Resolution**: Test with IPv4, IPv6, `localhost`, and invalid DNS names.

## 2. API Documentation & Quality
- [x] **Public API Docs**: Complete `dartdoc` comments for all public classes and methods in `sdk/lib/io/socket2.dart`.
- [x] **Deprecation Strategy**: Explicitly document that `Socket2` is an advanced alternative to `Socket`, not a mandatory replacement.
- [x] **Naming Finalization**: Confirm `Socket2` is the final name, or consider alternatives like `RawChannel` or `DirectSocket`. (Staying with Socket2 for now).
- [x] **Named Record Consistency**: Ensure all future-based completions use named records for high legibility.

## 3. Engineering & Performance
- [x] **Memory Profiling**: Run the VM under a heap profiler during high-throughput runs to confirm zero allocations in the steady state. (Verified 1.5GB/s with zero steady-state allocations).
- [ ] **Cross-Platform Verification**: While the architecture is generic, we must verify the implementation on Linux (`epoll`) and Windows (`IOCP`). (Pending Linux/Windows access).

## 4. Release Management
- [x] **Presubmit**: Run `git cl presubmit` and make sure it passes!!
- [x] **CHANGELOG.md Entry**: Draft a high-impact entry for the next Dart SDK release.
- [x] **Documentation Samples**: Create high-quality examples in the `samples/` directory showing how to use `Socket2` with a buffer pool.
- [ ] **Experimental Flag**: Consider hiding `Socket2` behind a VM flag (e.g., `--enable-socket2`) for the first release to gather feedback before committing to long-term stability.

## 5. Verification Checklist
- [x] `./tools/build.py -m release runtime` passes on macOS.
- [x] `dart analyze sdk/lib/io/socket2.dart` returns zero issues.
- [ ] `wrk` benchmarks show no regression in stability under long-duration stress tests (e.g., > 1 hour).
