// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'benchmark_harness.dart';

List<BenchmarkResult> runRootZoneBenchmarks() {
  final root = Zone.root;
  return [
    runBenchmark('Zone.root.run', 'Zone.root.run fast-path', () {
      sink ^= root.run(dummyAction);
    }),
  ];
}
