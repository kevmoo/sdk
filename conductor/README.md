# Conductor Index

> [!NOTE]
> **Project Socket2**: This directory documents the design, implementation, and
> results of `Socket2`, a new high-performance, zero-copy, completion-based
> socket API for Dart. By moving away from the readiness-based `Stream` model
> to an ownership-passing paradigm, `Socket2` eliminates garbage collection 
> spikes caused by excessive object allocations during steady-state I/O.

## The Performance Wins

1.  **Real-World HTTP Server (Concurrent Streaming)**:
    When integrated into a fully AOT-compiled HTTP server (`bottom_shelf`)
    handling 50 concurrent connections streaming 1.3 MB payloads, `Socket2`
    delivered a **7% - 10% increase in Requests-Per-Second (RPS)** over the 
    standard `dart:io` C++ backend. 
    
    More importantly, `Socket2` achieved a **28% reduction in P99 tail latency** 
    (from 64.9ms down to 46.8ms), completely validating the theory that 
    zero-allocation byte pooling eliminates the GC pauses inherent to `Stream<List<int>>`.

2.  **Straight-Line Microbenchmarks**:
    *(Caveat: Initial prototype metrics)* In isolated, single-connection microbenchmarks 
    designed to strictly measure event-loop overhead without concurrency, `Socket2` 
    achieved up to **3.3x faster throughput** and **360x lower latency** than legacy Dart. 
    However, under real-world concurrent load, Dart's asynchronous context-switching 
    forces the actual gains closer to the 10% RPS increase cited above.

## Document Index
- [Socket2 Implementation Plan](./socket2_plan.md)
- [Project Stumbles](./STUMBLES.md)
- [Technical Breakthroughs](./BREAKTHROUGHS.md)
- [User-Driven Design Notes](./PROMPTS.md)
- [Detailed Changelog](./CHANGELOG_DETAILED.md)
- [Final Benchmark Results](./BENCHMARKS_FINAL.md)
- [Shipping Plan](./SHIPPING_PLAN.md)
- [Update 2026-04-25](./update_2026-04-25.md)

## Future Improvements

While the current implementation of `Socket2` is cross-platform (by
leveraging `SocketBase` and hijacking the existing `EventHandler`), it is
technically a **simulated completion model**. The Dart API exposes a
completion-based interface (passing ownership of buffers), but the
underlying C++ implementation still relies on Dart's readiness-based event
loop (`epoll` / `kqueue`).

To push performance even further, future work could involve:
-   **True OS Completion Models**: Implementing native backends using
    `io_uring` on Linux or full `IOCP` on Windows. This would allow for true
    zero-copy operations at the OS level, bypassing the readiness
    notifications entirely.
-   **Exposing the Buffer Pool**: We successfully proved the concept of a 
    zero-allocation `BufferPool` and a batched `BufferedWriter` in our custom 
    `package:shelf` implementation. Future work should involve standardizing 
    this pool directly into the `dart:io` or `dart:typed_data` SDK so all Dart 
    developers can easily write GC-free pipelines.
