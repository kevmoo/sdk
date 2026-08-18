// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:expect/expect.dart';

void main() {
  testFusedConverterSubviews();
  testChunkedSinkSubviews();
  testNumberBufferAcrossChunkBoundariesWithSubviews();
}

Uint8List _createPoisonedSubview(List<int> bytes, int leadPad, int tailPad) {
  final backing = Uint8List(leadPad + bytes.length + tailPad);
  backing.fillRange(0, backing.length, 0xFF); // Canary poison
  backing.setRange(leadPad, leadPad + bytes.length, bytes);
  return Uint8List.sublistView(backing, leadPad, leadPad + bytes.length);
}

void testFusedConverterSubviews() {
  final testCases = <Object?>[
    -5946,
    123.45,
    "hello world",
    true,
    false,
    null,
    {"key": -98765, "float": 456.78, "active": true},
    [1, 2, 3, 4, -5.5],
  ];

  final fused = utf8.decoder.fuse(json.decoder);

  for (final val in testCases) {
    final encoded = utf8.encode(json.encode(val));
    for (final leadPad in [1, 7, 16, 32]) {
      for (final tailPad in [1, 7, 16, 32]) {
        final subview = _createPoisonedSubview(encoded, leadPad, tailPad);
        final decoded = fused.convert(subview);
        Expect.deepEquals(val, decoded);
      }
    }
  }
}

void testChunkedSinkSubviews() {
  final rawJson =
      '{"a": 12345, "b": "some long text value", "c": [1.25, 2.5, 3.75]}';
  final encoded = utf8.encode(rawJson);

  for (var chunkSize = 1; chunkSize <= 10; chunkSize++) {
    Object? result;
    final outSink = ChunkedConversionSink<Object?>.withCallback((v) {
      if (v.isNotEmpty) result = v.first;
    });
    final inSink = utf8.decoder.startChunkedConversion(
      json.decoder.startChunkedConversion(outSink),
    );

    var offset = 0;
    while (offset < encoded.length) {
      final end = (offset + chunkSize < encoded.length)
          ? offset + chunkSize
          : encoded.length;
      final chunkSlice = encoded.sublist(offset, end);
      final poisonedChunk = _createPoisonedSubview(chunkSlice, 8, 8);
      inSink.add(poisonedChunk);
      offset = end;
    }
    inSink.close();

    Expect.deepEquals(json.decode(rawJson), result);
  }
}

void testNumberBufferAcrossChunkBoundariesWithSubviews() {
  // Number split across chunks: '-59' in chunk 1, '46.125' in chunk 2
  final chunk1 = utf8.encode('{"val": -59');
  final chunk2 = utf8.encode('46.125}');

  Object? result;
  final outSink = ChunkedConversionSink<Object?>.withCallback((v) {
    if (v.isNotEmpty) result = v.first;
  });
  final inSink = utf8.decoder.startChunkedConversion(
    json.decoder.startChunkedConversion(outSink),
  );

  inSink.add(_createPoisonedSubview(chunk1, 16, 16));
  inSink.add(_createPoisonedSubview(chunk2, 16, 16));
  inSink.close();

  Expect.deepEquals({"val": -5946.125}, result);
}
