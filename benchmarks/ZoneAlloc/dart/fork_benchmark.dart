// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'benchmark_base.dart';

/// Measures fast-path Zone.fork without specification.
class ZoneForkRootBenchmark extends ZoneBenchmark {
  ZoneForkRootBenchmark() : super('Zone.fork (root/no-spec)');

  @override
  void runBatch(int batchSize) {
    final current = Zone.current;
    int localSink = 0;
    for (int i = 0; i < batchSize; i++) {
      final z = current.fork();
      localSink ^= z.hashCode;
    }
    globalSink ^= localSink;
  }
}

/// Measures custom specification Zone.fork execution and allocation churn.
class ZoneForkCustomBenchmark extends ZoneBenchmark {
  ZoneForkCustomBenchmark() : super('Zone.fork (custom specification)');

  @override
  void runBatch(int batchSize) {
    final current = Zone.current;
    int localSink = 0;
    for (int i = 0; i < batchSize; i++) {
      final z = current.fork(specification: customZoneSpec);
      localSink ^= z.hashCode;
    }
    globalSink ^= localSink;
  }
}
