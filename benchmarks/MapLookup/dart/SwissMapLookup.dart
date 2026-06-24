// Benchmark comparing DefaultMap vs SwissMap under dart2wasm.
import 'dart:collection';
import 'dart:math';

double measureStringMap(Map<String, String> map, Duration duration) {
  final int batching = max(1000 ~/ max(map.length, 1), 1);
  int numberOfLookups = 0;
  final sw = Stopwatch()..start();
  final durationInMicroseconds = duration.inMicroseconds;

  do {
    for (int i = 0; i < batching; i++) {
      String? k = '0';
      while (k != null) {
        k = map[k];
      }
      numberOfLookups += map.length;
    }
  } while (sw.elapsedMicroseconds < durationInMicroseconds);

  final int totalNanoseconds = sw.elapsed.inMicroseconds * 1000;
  return totalNanoseconds / max(numberOfLookups, 1);
}

double measureIntMap(Map<int, int> map, Duration duration) {
  final int batching = max(1000 ~/ max(map.length, 1), 1);
  int numberOfLookups = 0;
  final sw = Stopwatch()..start();
  final durationInMicroseconds = duration.inMicroseconds;

  do {
    for (int i = 0; i < batching; i++) {
      int? k = 0;
      while (k != null) {
        k = map[k];
      }
      numberOfLookups += map.length;
    }
  } while (sw.elapsedMicroseconds < durationInMicroseconds);

  final int totalNanoseconds = sw.elapsed.inMicroseconds * 1000;
  return totalNanoseconds / max(numberOfLookups, 1);
}

void reportStringBenchmark(String name, Map<String, String> map) {
  measureStringMap(map, const Duration(milliseconds: 100)); // warmup
  final ns = measureStringMap(map, const Duration(seconds: 1));
  print('$name: ${ns.toStringAsFixed(2)} ns');
}

void reportIntBenchmark(String name, Map<int, int> map) {
  measureIntMap(map, const Duration(milliseconds: 100)); // warmup
  final ns = measureIntMap(map, const Duration(seconds: 1));
  print('$name: ${ns.toStringAsFixed(2)} ns');
}

void testSize(int count) {
  final defaultStringMap = LinkedHashMap<String, String>();
  final swissStringMap = LinkedHashMap<String, String>.swiss();
  final swarStringMap = LinkedHashMap<String, String>.swar();
  final defaultIntMap = LinkedHashMap<int, int>();
  final swissIntMap = LinkedHashMap<int, int>.swiss();
  final swarIntMap = LinkedHashMap<int, int>.swar();

  for (int i = 0; i < count; i++) {
    final kStr = '$i';
    final vStr = (i == count - 1) ? null : '${i + 1}';
    final vInt = (i == count - 1) ? null : i + 1;
    if (vStr != null) {
      defaultStringMap[kStr] = vStr;
      swissStringMap[kStr] = vStr;
      swarStringMap[kStr] = vStr;
    }
    if (vInt != null) {
      defaultIntMap[i] = vInt;
      swissIntMap[i] = vInt;
      swarIntMap[i] = vInt;
    }
  }

  print('=== Map Size: $count elements ===');
  print('[String Keys]');
  reportStringBenchmark('  DefaultMap      ', defaultStringMap);
  reportStringBenchmark('  SwissMap (v128) ', swissStringMap);
  reportStringBenchmark('  SwarMap  (i64)  ', swarStringMap);
  print('[Int Keys]');
  reportIntBenchmark('  DefaultMap      ', defaultIntMap);
  reportIntBenchmark('  SwissMap (v128) ', swissIntMap);
  reportIntBenchmark('  SwarMap  (i64)  ', swarIntMap);
  print('');
}

void main() {
  print(
    'Running comparative Map benchmarks (DefaultMap vs SwissMap vs SwarMap)...\n',
  );
  for (final size in [100, 1000, 10000, 50000]) {
    testSize(size);
  }
}
