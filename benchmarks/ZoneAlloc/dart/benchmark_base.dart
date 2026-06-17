// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

/// Global accumulator variable to prevent compiler dead-code elimination (DCE).
int globalSink = 0;

/// Dummy action executed inside zone benchmarks.
int dummyAction() => 42;

/// Standard custom interceptor specification used across zone benchmarks.
final customZoneSpec = ZoneSpecification(
  run: <R>(Zone self, ZoneDelegate parent, Zone zone, R Function() f) {
    return parent.run(zone, f);
  },
);

/// Abstract base class for focused zone performance benchmarks.
abstract class ZoneBenchmark {
  final String name;

  ZoneBenchmark(this.name);

  /// Executes a single batch of target operations.
  void runBatch(int batchSize);

  /// Executes the warmup phase (500 ms) and measurement phase (2000 ms).
  BenchmarkResult measure() {
    final watch = Stopwatch()..start();
    // Warmup phase (500 ms)
    while (watch.elapsedMilliseconds < 500) {
      runBatch(1000);
    }
    watch.reset();
    int totalOps = 0;
    // Measurement phase (2000 ms / 2,000,000 micros) with 100,000 op batch sizes
    while (watch.elapsedMicroseconds < 2000000) {
      runBatch(100000);
      totalOps += 100000;
    }
    final elapsedMicros = watch.elapsedMicroseconds;
    final microsPerOp = elapsedMicros / totalOps;
    final opsPerSec = totalOps * 1000000.0 / elapsedMicros;
    return BenchmarkResult(name, microsPerOp, opsPerSec);
  }
}

class BenchmarkResult {
  final String name;
  final double microsPerOp;
  final double opsPerSec;

  BenchmarkResult(this.name, this.microsPerOp, this.opsPerSec);

  Map<String, dynamic> toJson() => {
    'name': name,
    'microsPerOp': microsPerOp,
    'opsPerSec': opsPerSec,
  };

  void printReport() {
    print('--- Benchmark: $name ---');
    print('Time per iteration: ${microsPerOp.toStringAsFixed(6)} us');
    print('Throughput: ${opsPerSec.toStringAsFixed(2)} ops/sec\n');
  }
}
