// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'benchmark_base.dart';

/// Baseline: measures direct closure execution (zero wrapping or zone switching overhead).
class DirectClosureBenchmark extends ZoneBenchmark {
  DirectClosureBenchmark() : super('Direct closure invocation');

  @override
  void runBatch(int batchSize) {
    int localSink = 0;
    for (int i = 0; i < batchSize; i++) {
      localSink ^= dummyAction();
    }
    globalSink ^= localSink;
  }
}

/// Baseline: measures direct zone run (measures zone switching overhead without closure wrapping creation).
class DirectZoneRunBenchmark extends ZoneBenchmark {
  DirectZoneRunBenchmark() : super('Zone.current.run(closure)');

  @override
  void runBatch(int batchSize) {
    final current = Zone.current;
    int localSink = 0;
    for (int i = 0; i < batchSize; i++) {
      localSink ^= current.run(dummyAction);
    }
    globalSink ^= localSink;
  }
}

/// Measures fast-path runZoned execution throughput.
class RunZonedNoSpecBenchmark extends ZoneBenchmark {
  RunZonedNoSpecBenchmark() : super('runZoned (no specification)');

  @override
  void runBatch(int batchSize) {
    int localSink = 0;
    for (int i = 0; i < batchSize; i++) {
      localSink ^= runZoned(dummyAction);
    }
    globalSink ^= localSink;
  }
}

/// Measures custom specification runZoned closure wrapping and delegation throughput.
class RunZonedCustomBenchmark extends ZoneBenchmark {
  RunZonedCustomBenchmark() : super('runZoned (custom specification)');

  @override
  void runBatch(int batchSize) {
    int localSink = 0;
    for (int i = 0; i < batchSize; i++) {
      localSink ^= runZoned(dummyAction, zoneSpecification: customZoneSpec);
    }
    globalSink ^= localSink;
  }
}
