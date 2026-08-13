// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

void main() {
  print('=== JSON UTF-8 Kernels & Formatters Microbenchmark Suite ===\n');

  benchmarkWriteIntToBuffer();
  benchmarkWriteBoolToBuffer();
  benchmarkWriteDoubleToBuffer();
  benchmarkWriteStringToBuffer();
  benchmarkJsonKeyOptionsSelectKey();
  benchmarkDecodeString();
  benchmarkJsonUtf8DecoderConvert();

  print('=== JSON UTF-8 Macro Benchmark Suite (Canonical Datasets) ===\n');
  benchmarkMacroCanadaGeoJson();
  benchmarkMacroCitmCatalog();
  benchmarkMacroCoordinateArray();

  print('=== JSON UTF-8 Direct Buffer Throughput Suites ===\n');
  benchmarkFloatArrayDirectFormat();
  benchmarkAsciiStringArrayDirectFormat();
}

void benchmarkWriteIntToBuffer() {
  final buffer = Uint8List(64);
  final testInts = [
    0,
    42,
    -42,
    123456789,
    -123456789,
    9223372036854775807,
    -9223372036854775808,
  ];

  // Warmup
  for (var i = 0; i < 10000; i++) {
    for (final v in testInts) {
      JsonUtf8Encoder.writeIntToBuffer(v, buffer, 0);
    }
  }

  const iterations = 500000;
  final sw = Stopwatch()..start();
  var totalBytes = 0;
  for (var i = 0; i < iterations; i++) {
    for (final v in testInts) {
      totalBytes += JsonUtf8Encoder.writeIntToBuffer(v, buffer, 0);
    }
  }
  sw.stop();

  final totalOps = iterations * testInts.length;
  final opsPerSec = (totalOps / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(0);
  final mbPerSec =
      ((totalBytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000))
          .toStringAsFixed(2);

  print('1. writeIntToBuffer:');
  print(
    '   Ops: $totalOps in ${sw.elapsedMilliseconds} ms ($opsPerSec ops/s, $mbPerSec MB/s, totalBytes=$totalBytes)\n',
  );
}

void benchmarkWriteBoolToBuffer() {
  final buffer = Uint8List(64);
  final testBools = [true, false, true, true, false, false];

  // Warmup
  for (var i = 0; i < 10000; i++) {
    for (final v in testBools) {
      JsonUtf8Encoder.writeBoolToBuffer(v, buffer, 0);
    }
  }

  const iterations = 1000000;
  final sw = Stopwatch()..start();
  var totalBytes = 0;
  for (var i = 0; i < iterations; i++) {
    for (final v in testBools) {
      totalBytes += JsonUtf8Encoder.writeBoolToBuffer(v, buffer, 0);
    }
  }
  sw.stop();

  final totalOps = iterations * testBools.length;
  final opsPerSec = (totalOps / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(0);
  final mbPerSec =
      ((totalBytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000))
          .toStringAsFixed(2);

  print('2. writeBoolToBuffer:');
  print(
    '   Ops: $totalOps in ${sw.elapsedMilliseconds} ms ($opsPerSec ops/s, $mbPerSec MB/s, totalBytes=$totalBytes)\n',
  );
}

void benchmarkWriteDoubleToBuffer() {
  final buffer = Uint8List(64);
  final testDoubles = [
    0.0,
    3.1415926535,
    -42.5,
    1.23456e10,
    1e-5,
    9007199254740991.0,
  ];

  // Warmup
  for (var i = 0; i < 10000; i++) {
    for (final v in testDoubles) {
      JsonUtf8Encoder.writeDoubleToBuffer(v, buffer, 0);
    }
  }

  const iterations = 300000;
  final sw = Stopwatch()..start();
  var totalBytes = 0;
  for (var i = 0; i < iterations; i++) {
    for (final v in testDoubles) {
      totalBytes += JsonUtf8Encoder.writeDoubleToBuffer(v, buffer, 0);
    }
  }
  sw.stop();

  final totalOps = iterations * testDoubles.length;
  final opsPerSec = (totalOps / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(0);
  final mbPerSec =
      ((totalBytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000))
          .toStringAsFixed(2);

  print('3. writeDoubleToBuffer:');
  print(
    '   Ops: $totalOps in ${sw.elapsedMilliseconds} ms ($opsPerSec ops/s, $mbPerSec MB/s, totalBytes=$totalBytes)\n',
  );
}

void benchmarkWriteStringToBuffer() {
  final buffer = Uint8List(256);
  final testStrings = [
    'id',
    'userName',
    'descriptionWithSomeLongerAsciiContent',
    'escaped"quotes"and\\slashes\n\t',
  ];

  // Warmup
  for (var i = 0; i < 10000; i++) {
    for (final s in testStrings) {
      JsonUtf8Encoder.writeStringToBuffer(s, buffer, 0);
    }
  }

  const iterations = 500000;
  final sw = Stopwatch()..start();
  var totalBytes = 0;
  for (var i = 0; i < iterations; i++) {
    for (final s in testStrings) {
      totalBytes += JsonUtf8Encoder.writeStringToBuffer(s, buffer, 0);
    }
  }
  sw.stop();

  final totalOps = iterations * testStrings.length;
  final opsPerSec = (totalOps / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(0);
  final mbPerSec =
      ((totalBytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000))
          .toStringAsFixed(2);

  print('4. writeStringToBuffer:');
  print(
    '   Ops: $totalOps in ${sw.elapsedMilliseconds} ms ($opsPerSec ops/s, $mbPerSec MB/s, totalBytes=$totalBytes)\n',
  );
}

void benchmarkJsonKeyOptionsSelectKey() {
  // Test with a 30-key schema (typical of API payload schemas)
  final keyNames = List.generate(30, (i) => 'property_name_field_$i');
  final options = JsonKeyOptions.of(keyNames);

  final testByteSpans = keyNames
      .map((k) => utf8.encode(k) as Uint8List)
      .toList();

  // Warmup
  for (var i = 0; i < 5000; i++) {
    for (final b in testByteSpans) {
      options.selectKey(b, 0, b.length);
    }
  }

  const iterations = 100000;
  final sw = Stopwatch()..start();
  var matchSum = 0;
  for (var i = 0; i < iterations; i++) {
    for (final b in testByteSpans) {
      matchSum += options.selectKey(b, 0, b.length);
    }
  }
  sw.stop();

  final totalOps = iterations * testByteSpans.length;
  final opsPerSec = (totalOps / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(0);

  print('5. JsonKeyOptions.selectKey (30 keys):');
  print(
    '   Ops: $totalOps in ${sw.elapsedMilliseconds} ms ($opsPerSec ops/s, matchSum=$matchSum)\n',
  );
}

void benchmarkDecodeString() {
  final asciiBytes = Uint8List.fromList(
    utf8.encode('standard_verbatim_ascii_property_string_value'),
  );
  final escapedBytes = Uint8List.fromList(
    utf8.encode(r'line1\nline2\ttab\"quoted\"'),
  );
  final utf8Bytes = Uint8List.fromList(
    utf8.encode('Unicode text with € and 😀 emoji'),
  );

  // Warmup
  for (var i = 0; i < 5000; i++) {
    JsonUtf8Decoder.decodeString(asciiBytes, 0, asciiBytes.length);
    JsonUtf8Decoder.decodeString(escapedBytes, 0, escapedBytes.length);
    JsonUtf8Decoder.decodeString(utf8Bytes, 0, utf8Bytes.length);
  }

  const iterations = 200000;
  final sw = Stopwatch()..start();
  var charCount = 0;
  for (var i = 0; i < iterations; i++) {
    charCount += JsonUtf8Decoder.decodeString(
      asciiBytes,
      0,
      asciiBytes.length,
    ).length;
    charCount += JsonUtf8Decoder.decodeString(
      escapedBytes,
      0,
      escapedBytes.length,
    ).length;
    charCount += JsonUtf8Decoder.decodeString(
      utf8Bytes,
      0,
      utf8Bytes.length,
    ).length;
  }
  sw.stop();

  final totalOps = iterations * 3;
  final opsPerSec = (totalOps / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(0);

  print('6. JsonUtf8Decoder.decodeString:');
  print(
    '   Ops: $totalOps in ${sw.elapsedMilliseconds} ms ($opsPerSec ops/s, charCount=$charCount)\n',
  );
}

void benchmarkJsonUtf8DecoderConvert() {
  final jsonDoc = '''
{
  "id": 123456,
  "name": "Benchmark Item",
  "active": true,
  "score": 98.6,
  "tags": ["performance", "dart", "json", "utf8"],
  "metadata": {
    "created": "2026-08-13T00:00:00Z",
    "owner": "engine-team",
    "retries": 3
  }
}
''';
  final utf8Doc = Uint8List.fromList(utf8.encode(jsonDoc));
  final decoder = const JsonUtf8Decoder();

  // Warmup
  for (var i = 0; i < 2000; i++) {
    decoder.convert(utf8Doc);
  }

  const iterations = 50000;
  final sw = Stopwatch()..start();
  var dummyHash = 0;
  for (var i = 0; i < iterations; i++) {
    final res = decoder.convert(utf8Doc) as Map<String, dynamic>;
    dummyHash ^= (res['id'] as int);
  }
  sw.stop();

  final totalOps = iterations;
  final opsPerSec = (totalOps / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(0);
  final totalBytes = iterations * utf8Doc.length;
  final mbPerSec =
      ((totalBytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000))
          .toStringAsFixed(2);

  print('7. JsonUtf8Decoder.convert (Full UTF-8 JSON document):');
  print(
    '   Ops: $totalOps in ${sw.elapsedMilliseconds} ms ($opsPerSec ops/s, $mbPerSec MB/s, dummyHash=$dummyHash)\n',
  );
}

void benchmarkMacroCanadaGeoJson() {
  // Simulates canada.json: float-heavy GeoJSON dataset with thousands of float coordinates
  final coords = <List<double>>[];
  for (var i = 0; i < 25000; i++) {
    coords.add([-65.613617 + (i % 100) * 0.001, 43.420273 + (i % 80) * 0.001]);
  }
  final geoJson = {
    "type": "FeatureCollection",
    "features": [
      {
        "type": "Feature",
        "properties": {"name": "Canada Boundary"},
        "geometry": {
          "type": "Polygon",
          "coordinates": [coords],
        },
      },
    ],
  };

  // Warmup
  for (var i = 0; i < 5; i++) {
    jsonUtf8Encode(geoJson);
  }

  const iterations = 50;
  final sw = Stopwatch()..start();
  var totalBytes = 0;
  for (var i = 0; i < iterations; i++) {
    final encoded = jsonUtf8Encode(geoJson);
    totalBytes += encoded.length;
  }
  sw.stop();

  final opsPerSec = (iterations / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(1);
  final mbPerSec =
      ((totalBytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000))
          .toStringAsFixed(2);

  print('8. Macro: canada.json (Float-heavy GeoJSON):');
  print(
    '   ${iterations} iterations (${(totalBytes / iterations / 1024).toStringAsFixed(1)} KB/doc) in ${sw.elapsedMilliseconds} ms ($opsPerSec docs/s, $mbPerSec MB/s)\n',
  );
}

void benchmarkMacroCitmCatalog() {
  // Simulates citm_catalog.json: string-heavy ticketing catalog
  final events = <Map<String, dynamic>>[];
  for (var i = 0; i < 5000; i++) {
    events.add({
      "id": 100000 + i,
      "name": "Festival Performance Event #$i - Grand Hall Symphony",
      "description":
          "Comprehensive musical performance with orchestra and soloist ensemble in metropolitan hall #$i",
      "venue":
          "Metropolitan Philharmonic Concert Hall & Opera Complex, Stage ${i % 12}",
      "category": "Classical and Contemporary Symphony Orchestra Performances",
      "date": "2026-08-13T20:00:00.000Z",
      "status": "AVAILABLE_FOR_BOOKING",
      "price": 149.50,
      "tags": ["concert", "music", "orchestra", "symphony", "festival"],
    });
  }
  final catalog = {
    "catalogName": "International Summer Music Festival 2026",
    "version": "2.4.0",
    "totalEvents": events.length,
    "events": events,
  };

  // Warmup
  for (var i = 0; i < 5; i++) {
    jsonUtf8Encode(catalog);
  }

  const iterations = 30;
  final sw = Stopwatch()..start();
  var totalBytes = 0;
  for (var i = 0; i < iterations; i++) {
    final encoded = jsonUtf8Encode(catalog);
    totalBytes += encoded.length;
  }
  sw.stop();

  final opsPerSec = (iterations / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(1);
  final mbPerSec =
      ((totalBytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000))
          .toStringAsFixed(2);

  print('9. Macro: citm_catalog.json (String-heavy Catalog):');
  print(
    '   ${iterations} iterations (${(totalBytes / iterations / 1024).toStringAsFixed(1)} KB/doc) in ${sw.elapsedMilliseconds} ms ($opsPerSec docs/s, $mbPerSec MB/s)\n',
  );
}

void benchmarkMacroCoordinateArray() {
  // Simulates 1.json: large-scale coordinate stream (50k points in micro-run)
  const count = 50000;
  final coords = List.generate(
    count,
    (i) => {
      "x": 0.123456 + (i % 1000) * 0.001,
      "y": -12.3456 + (i % 500) * 0.002,
      "z": 98.7654 + (i % 250) * 0.005,
      "name": "coord_point_$i",
    },
  );
  final doc = {
    "dataset": "Kostya Coordinate Benchmark Dataset",
    "coordinates": coords,
  };

  final encoded = jsonUtf8Encode(doc);

  // Measure stream decode throughput
  final sw = Stopwatch()..start();
  const iterations = 20;
  var checksum = 0.0;
  for (var i = 0; i < iterations; i++) {
    final reader = JsonTokenReader.fromBytes(encoded);
    reader.beginObject();
    while (reader.hasNext()) {
      final key = reader.nextName();
      if (key == 'coordinates') {
        reader.beginArray();
        while (reader.hasNext()) {
          reader.beginObject();
          while (reader.hasNext()) {
            final fName = reader.nextName();
            if (fName == 'x' || fName == 'y' || fName == 'z') {
              checksum += reader.readDouble();
            } else {
              reader.skipValue();
            }
          }
          reader.endObject();
        }
        reader.endArray();
      } else {
        reader.skipValue();
      }
    }
    reader.endObject();
  }
  sw.stop();

  final totalBytes = iterations * encoded.length;
  final mbPerSec =
      ((totalBytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000))
          .toStringAsFixed(2);

  print('10. Macro: 1.json (50k Coordinates Stream Zero-Copy Reader):');
  print(
    '   ${iterations} stream passes (${(encoded.length / 1024).toStringAsFixed(1)} KB/doc) in ${sw.elapsedMilliseconds} ms ($mbPerSec MB/s, checksum=${checksum.toStringAsFixed(0)})\n',
  );
}

void benchmarkFloatArrayDirectFormat() {
  // Directly measures raw buffer throughput for writeDoubleToBuffer across 100,000 float points
  const count = 100000;
  final floats = List.generate(count, (i) => -122.419415 + (i % 1000) * 0.0001);
  final buffer = Uint8List(count * 20);

  // Warmup
  for (var i = 0; i < 5; i++) {
    var cursor = 0;
    for (final v in floats) {
      cursor += JsonUtf8Encoder.writeDoubleToBuffer(v, buffer, cursor);
    }
  }

  const iterations = 50;
  final sw = Stopwatch()..start();
  var totalBytes = 0;
  for (var i = 0; i < iterations; i++) {
    var cursor = 0;
    for (final v in floats) {
      cursor += JsonUtf8Encoder.writeDoubleToBuffer(v, buffer, cursor);
    }
    totalBytes += cursor;
  }
  sw.stop();

  final totalOps = iterations * count;
  final opsPerSec = (totalOps / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(0);
  final mbPerSec =
      ((totalBytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000))
          .toStringAsFixed(2);

  print(
    '11. Direct Contiguous Float Array Formatting (100k coords into Uint8List):',
  );
  print(
    '    $totalOps floats in ${sw.elapsedMilliseconds} ms ($opsPerSec floats/s, $mbPerSec MB/s, totalBytes=$totalBytes)\n',
  );
}

void benchmarkAsciiStringArrayDirectFormat() {
  // Directly measures raw buffer throughput for writeStringToBuffer across 50,000 ASCII strings
  const count = 50000;
  final strings = List.generate(
    count,
    (i) => 'property_name_identifier_field_token_key_$i',
  );
  final buffer = Uint8List(count * 64);

  // Warmup
  for (var i = 0; i < 5; i++) {
    var cursor = 0;
    for (final s in strings) {
      cursor += JsonUtf8Encoder.writeStringToBuffer(s, buffer, cursor);
    }
  }

  const iterations = 50;
  final sw = Stopwatch()..start();
  var totalBytes = 0;
  for (var i = 0; i < iterations; i++) {
    var cursor = 0;
    for (final s in strings) {
      cursor += JsonUtf8Encoder.writeStringToBuffer(s, buffer, cursor);
    }
    totalBytes += cursor;
  }
  sw.stop();

  final totalOps = iterations * count;
  final opsPerSec = (totalOps / (sw.elapsedMicroseconds / 1000000))
      .toStringAsFixed(0);
  final mbPerSec =
      ((totalBytes / (1024 * 1024)) / (sw.elapsedMicroseconds / 1000000))
          .toStringAsFixed(2);

  print(
    '12. Direct Contiguous ASCII String Array Formatting (50k keys into Uint8List):',
  );
  print(
    '    $totalOps strings in ${sw.elapsedMilliseconds} ms ($opsPerSec strings/s, $mbPerSec MB/s, totalBytes=$totalBytes)\n',
  );
}
