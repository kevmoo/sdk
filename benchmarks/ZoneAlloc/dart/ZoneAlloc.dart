// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'benchmark_base.dart';
import 'fork_benchmark.dart';
import 'run_zoned_benchmark.dart';
import 'root_run_benchmark.dart';

void main(List<String> args) {
  final jsonMode = args.contains('--json');
  String? filter;
  for (final arg in args) {
    if (arg.startsWith('--filter=')) {
      filter = arg.substring('--filter='.length);
    } else if (!arg.startsWith('--') && filter == null) {
      filter = arg;
    }
  }

  if (!jsonMode) {
    print(
      'Starting Modular Zone Performance & Allocation Benchmark Suite...\n',
    );
    if (filter != null) {
      print('Filtering benchmarks matching: "$filter"\n');
    }
  }

  final benchmarks = <ZoneBenchmark>[
    DirectClosureBenchmark(),
    DirectZoneRunBenchmark(),
    ZoneForkRootBenchmark(),
    ZoneForkCustomBenchmark(),
    RunZonedNoSpecBenchmark(),
    RunZonedCustomBenchmark(),
    ZoneRootRunBenchmark(),
  ];

  final results = <BenchmarkResult>[];
  for (final bench in benchmarks) {
    if (filter != null &&
        !bench.name.toLowerCase().contains(filter.toLowerCase())) {
      continue;
    }
    final result = bench.measure();
    results.add(result);
  }

  if (jsonMode) {
    print(jsonEncode(results.map((r) => r.toJson()).toList()));
  } else {
    for (final res in results) {
      res.printReport();
    }
  }

  if (globalSink == 0xdeadbeef) print(globalSink);
}
