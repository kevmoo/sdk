# Conductor Index

> [!NOTE]
> **Project Socket2**: This directory documents the design, implementation, and
> results of `Socket2`, a new high-performance, zero-copy, completion-based
> socket API for Dart. By moving away from the readiness-based `Stream` model
> to an ownership-passing paradigm, `Socket2` achieves **3.3x faster
> throughput** and **360x lower latency** in high-load scenarios.

- [Socket2 Implementation Plan](./socket2_plan.md)
- [Project Stumbles](./STUMBLES.md)
- [Technical Breakthroughs](./BREAKTHROUGHS.md)
- [User-Driven Design Notes](./PROMPTS.md)
- [Detailed Changelog](./CHANGELOG_DETAILED.md)
- [Final Benchmark Results](./BENCHMARKS_FINAL.md)
- [Shipping Plan](./SHIPPING_PLAN.md)

## Future Improvements

While the current implementation of `Socket2` is cross-platform (by
leveraging `SocketBase` and hijacking the existing `EventHandler`), it is
technically a **simulated completion model**. The Dart API exposes a
completion-based interface (passing ownership of buffers), but the
underlying C++ implementation still relies on Dart's readiness-based event
loop.

To push performance even further, future work could involve:
-   **True OS Completion Models**: Implementing native backends using
    `io_uring` on Linux or full `IOCP` on Windows. This would allow for true
    zero-copy operations at the OS level, avoiding the overhead of readiness
    notifications entirely.
-   **Buffer Pooling**: Standardizing a buffer pool implementation in Dart to
    make it easy for users to reuse buffers and completely eliminate
    allocations in the steady state.
