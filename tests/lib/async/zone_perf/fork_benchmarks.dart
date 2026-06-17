// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'benchmark_harness.dart';

List<BenchmarkResult> runForkBenchmarks() {
  return [
    runBenchmark('Zone.fork', 'Zone.fork (root/no-spec)', () {
      final z = Zone.current.fork();
      sink ^= z.hashCode;
    }),
    runBenchmark('Zone.fork', 'Zone.fork (custom specification)', () {
      final z = Zone.current.fork(specification: customSpec);
      sink ^= z.hashCode;
    }),
  ];
}
