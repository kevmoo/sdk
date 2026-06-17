// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'benchmark_harness.dart';

List<BenchmarkResult> runRunZonedBenchmarks() {
  final currentZone = Zone.current;
  return [
    // Baseline: direct closure execution (zero wrapping or zone switching overhead)
    runBenchmark('Closure Wrapping Overhead', 'Direct closure invocation', () {
      sink ^= dummyAction();
    }),
    // Baseline: direct zone run (measures zone switching overhead without closure wrapping creation)
    runBenchmark('Closure Wrapping Overhead', 'Zone.current.run(closure)', () {
      sink ^= currentZone.run(dummyAction);
    }),
    runBenchmark('runZoned', 'runZoned (no specification)', () {
      sink ^= runZoned(dummyAction);
    }),
    runBenchmark('runZoned', 'runZoned (custom specification)', () {
      sink ^= runZoned(dummyAction, zoneSpecification: customSpec);
    }),
  ];
}
