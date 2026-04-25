# Roadmap to Shipping Socket2

This document outlines the remaining requirements and quality checks needed to move `Socket2` from a functional prototype to a production-ready feature in the Dart SDK.

## 1. Robustness & Edge Case Testing
Our current tests cover the "happy path" of connection and full buffer transfers. Before shipping, we must verify:
- [ ] **Partial Reads/Writes**: Ensure the `while` loop logic is correct for all OS-level partial transfers.
- [x] **Zero-length Reads/Writes**: Define behavior when an empty `TypedData` is passed.
- [x] **Connection Drops**: Verify that `SocketException` is correctly propagated when the remote peer disconnects during a pending `read` or `write`.
- [x] **Simultaneous Read/Write**: Verify that `Future.wait([socket.read(b1), socket.write(b2)])` works without internal state corruption.
- [x] **Protocol Violations**: Add tests that attempt to call `read()` twice simultaneously (should throw `StateError`).
- [ ] **Resource Cleanup**: Verify that `close()` cancels pending futures and frees C++ `Socket*` resources without leaking memory.
- [x] **Address Resolution**: Test with IPv4, IPv6, `localhost`, and invalid DNS names.

## 2. API Documentation & Quality
- [ ] **Public API Docs**: Complete `dartdoc` comments for all public classes and methods in `sdk/lib/io/socket2.dart`.
- [ ] **Deprecation Strategy**: Explicitly document that `Socket2` is an advanced alternative to `Socket`, not a mandatory replacement.
- [ ] **Naming Finalization**: Confirm `Socket2` is the final name, or consider alternatives like `RawChannel` or `DirectSocket`.
- [ ] **Named Record Consistency**: Ensure all future-based completions use named records for high legibility.

## 3. Engineering & Performance
- [ ] **Memory Profiling**: Run the VM under a heap profiler during high-throughput runs to confirm zero allocations in the steady state.
- [ ] **Cross-Platform Verification**: While the architecture is generic, we must verify the implementation on Linux (`epoll`) and Windows (`IOCP`).

## 4. Release Management
- [ ] **Presubmit**: Run `git cl presubmit` and make sure it passes!!
- [ ] **CHANGELOG.md Entry**: Draft a high-impact entry for the next Dart SDK release.
- [ ] **Documentation Samples**: Create high-quality examples in the `samples/` directory showing how to use `Socket2` with a buffer pool.
- [ ] **Experimental Flag**: Consider hiding `Socket2` behind a VM flag (e.g., `--enable-socket2`) for the first release to gather feedback before committing to long-term stability.

## 5. Verification Checklist
- [x] `./tools/build.py -m release runtime` passes on macOS.
- [x] `dart analyze sdk/lib/io/socket2.dart` returns zero issues.
- [ ] `wrk` benchmarks show no regression in stability under long-duration stress tests (e.g., > 1 hour).
