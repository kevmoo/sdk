// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

class BenchmarkResult {
  final String category;
  final String name;
  final double microsPerOp;
  final double opsPerSec;
  final int totalOps;
  final int elapsedMicros;

  BenchmarkResult({
    required this.category,
    required this.name,
    required this.microsPerOp,
    required this.opsPerSec,
    required this.totalOps,
    required this.elapsedMicros,
  });

  Map<String, dynamic> toJson() => {
    'category': category,
    'name': name,
    'microsPerOp': microsPerOp,
    'opsPerSec': opsPerSec,
    'totalOps': totalOps,
    'elapsedMicros': elapsedMicros,
  };
}

int sink = 0;

int dummyAction() => 42;

final customSpec = ZoneSpecification(
  run: <R>(Zone self, ZoneDelegate parent, Zone zone, R Function() f) {
    return parent.run(zone, f);
  },
);

BenchmarkResult runBenchmark(
  String category,
  String name,
  void Function() action,
) {
  final watch = Stopwatch()..start();
  // Warmup phase (500ms)
  while (watch.elapsedMilliseconds < 500) {
    for (int i = 0; i < 1000; i++) {
      action();
    }
  }
  watch.reset();
  int totalOps = 0;
  // High-precision measurement phase (2000ms / 2,000,000 micros)
  while (watch.elapsedMicroseconds < 2000000) {
    for (int i = 0; i < 10000; i++) {
      action();
    }
    totalOps += 10000;
  }
  final elapsedMicros = watch.elapsedMicroseconds;
  final microsPerOp = elapsedMicros / totalOps;
  final opsPerSec = totalOps * 1000000.0 / elapsedMicros;

  return BenchmarkResult(
    category: category,
    name: name,
    microsPerOp: microsPerOp,
    opsPerSec: opsPerSec,
    totalOps: totalOps,
    elapsedMicros: elapsedMicros,
  );
}
