// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'benchmark_base.dart';

/// Measures fast-path root zone (Zone.root.run) execution speed.
class ZoneRootRunBenchmark extends ZoneBenchmark {
  final Zone rootZone = Zone.root;

  ZoneRootRunBenchmark() : super('Zone.root.run');

  @override
  void runBatch(int batchSize) {
    int localSink = 0;
    for (int i = 0; i < batchSize; i++) {
      localSink ^= rootZone.run(dummyAction);
    }
    globalSink ^= localSink;
  }
}
