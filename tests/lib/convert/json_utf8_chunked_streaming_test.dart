// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testFusedUtf8JsonDecoderSpecialization();
  testChunkedStringStreamingSmallBuffer();
  testChunkedStringStreamingEscapesAndSurrogates();
  testChunkedLargeDocumentStreaming();
  testEncoderConvertSmallBufferSize();
  testMicroBufferSizeChunkedStreaming();
}

final class _ChunkCapturingSink extends ByteConversionSink {
  final List<Uint8List> chunks = [];
  bool isClosed = false;

  @override
  void add(List<int> chunk) {
    chunks.add(chunk is Uint8List ? chunk : Uint8List.fromList(chunk));
  }

  @override
  void addSlice(List<int> chunk, int start, int end, bool isLast) {
    final slice = Uint8List.fromList(
      chunk is Uint8List
          ? Uint8List.sublistView(chunk, start, end)
          : chunk.sublist(start, end),
    );
    chunks.add(slice);
    if (isLast) close();
  }

  @override
  void close() {
    isClosed = true;
  }
}

/// Verifies that utf8.decoder.fuse(json.decoder) specializes to JsonUtf8Decoder
/// across all platforms (VM, dart2js, dart2wasm).
void testFusedUtf8JsonDecoderSpecialization() {
  // 1. Basic fuse: utf8.decoder.fuse(json.decoder)
  final fused = utf8.decoder.fuse(json.decoder);
  Expect.type<JsonUtf8Decoder>(fused);
  Expect.isTrue(fused is JsonUtf8Decoder);
  final jsonUtf8Dec = fused as JsonUtf8Decoder;
  Expect.isFalse(jsonUtf8Dec.allowMalformed);
  Expect.isNull(jsonUtf8Dec.reviver);

  // 2. Decode standard payload through fused decoder
  final sampleJson = '{"greeting": "hello world", "count": 42, "ratio": 3.14}';
  final sampleBytes = Uint8List.fromList(utf8.encode(sampleJson));
  final decoded = fused.convert(sampleBytes) as Map<String, dynamic>;
  Expect.equals('hello world', decoded['greeting']);
  Expect.equals(42, decoded['count']);
  Expect.equals(3.14, decoded['ratio']);

  // 3. Fused with reviver
  final reviver = (Object? k, Object? v) => k == 'count' ? 100 : v;
  final fusedReviver = utf8.decoder.fuse(JsonDecoder(reviver));
  Expect.type<JsonUtf8Decoder>(fusedReviver);
  Expect.equals(reviver, (fusedReviver as JsonUtf8Decoder).reviver);
  final decodedReviver =
      fusedReviver.convert(sampleBytes) as Map<String, dynamic>;
  Expect.equals(100, decodedReviver['count']);

  // 4. Fused with allowMalformed: true
  final fusedMalformed =
      Utf8Decoder(allowMalformed: true).fuse(json.decoder) as JsonUtf8Decoder;
  Expect.isTrue(fusedMalformed.allowMalformed);
  final malformedBytes = Uint8List.fromList([0x22, 0x80, 0x22]); // '"\x80"'
  Expect.equals('\uFFFD', fusedMalformed.convert(malformedBytes));
}

/// Verifies that chunked encoding with small bufferSize (e.g. 256 bytes)
/// streams multi-megabyte strings in slices strictly bounded by bufferSize.
void testChunkedStringStreamingSmallBuffer() {
  // Create a 2 MB string
  final chunkPattern =
      "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
  final buffer = StringBuffer();
  while (buffer.length < 2 * 1024 * 1024) {
    buffer.write(chunkPattern);
  }
  final largeString = buffer.toString();

  const bufferSize = 256;
  final byteSink = _ChunkCapturingSink();

  final encoder = JsonUtf8Encoder(null, null, bufferSize);
  final sink = encoder.startChunkedConversion(byteSink);

  sink.add(largeString);
  sink.close();

  final chunks = byteSink.chunks;
  Expect.isTrue(chunks.isNotEmpty);

  // Contract guarantee: each emitted chunk must not exceed bufferSize
  for (var i = 0; i < chunks.length; i++) {
    final chunk = chunks[i];
    Expect.isTrue(
      chunk.length <= bufferSize,
      'Chunk $i length ${chunk.length} exceeds bufferSize $bufferSize',
    );
  }

  // Reassemble all chunks and verify roundtrip decoding
  final totalBytes = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final assembled = Uint8List(totalBytes);
  var offset = 0;
  for (final chunk in chunks) {
    assembled.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }

  final decoded = jsonUtf8.decode(assembled);
  Expect.equals(largeString, decoded);
}

/// Verifies chunked streaming on multi-megabyte strings containing
/// escape sequences, Unicode multi-byte chars, and isolated surrogates.
void testChunkedStringStreamingEscapesAndSurrogates() {
  const bufferSize = 128;
  final byteSink = _ChunkCapturingSink();

  final encoder = JsonUtf8Encoder(null, null, bufferSize);
  final sink = encoder.startChunkedConversion(byteSink);

  // Pattern with escapes and multi-byte UTF-8
  final pattern = 'hello "world" \n \t \\ \u20AC \u{1F680} test';
  final sb = StringBuffer();
  while (sb.length < 500 * 1024) {
    sb.write(pattern);
  }
  final richString = sb.toString();

  sink.add(richString);
  sink.close();

  final chunks = byteSink.chunks;
  for (var i = 0; i < chunks.length; i++) {
    Expect.isTrue(
      chunks[i].length <= bufferSize,
      'Chunk $i length ${chunks[i].length} exceeds bufferSize $bufferSize',
    );
  }

  final totalBytes = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final assembled = Uint8List(totalBytes);
  var offset = 0;
  for (final chunk in chunks) {
    assembled.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }

  final decoded = jsonUtf8.decode(assembled);
  Expect.equals(richString, decoded);
}

/// Verifies chunked streaming on large structured JSON objects with small bufferSize.
void testChunkedLargeDocumentStreaming() {
  const bufferSize = 512;
  final byteSink = _ChunkCapturingSink();

  final encoder = JsonUtf8Encoder(null, null, bufferSize);
  final sink = encoder.startChunkedConversion(byteSink);

  // Large map with many keys and long values
  final map = <String, Object?>{};
  for (var i = 0; i < 500; i++) {
    map['key_$i'] = 'long_value_${i}_' + ('x' * 200);
  }

  sink.add(map);
  sink.close();

  final chunks = byteSink.chunks;
  for (var i = 0; i < chunks.length; i++) {
    Expect.isTrue(
      chunks[i].length <= bufferSize,
      'Chunk $i length ${chunks[i].length} exceeds bufferSize $bufferSize',
    );
  }

  final totalBytes = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final assembled = Uint8List(totalBytes);
  var offset = 0;
  for (final chunk in chunks) {
    assembled.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }

  final decoded = jsonUtf8.decode(assembled) as Map<String, dynamic>;
  Expect.equals(map.length, decoded.length);
  for (var i = 0; i < 500; i++) {
    Expect.equals(map['key_$i'], decoded['key_$i']);
  }
}

/// Verifies that JsonUtf8Encoder.convert with small bufferSize works seamlessly
/// on large payloads.
void testEncoderConvertSmallBufferSize() {
  final encoder = JsonUtf8Encoder(null, null, 256);
  final largeList = List.generate(2000, (i) => 'entry_$i');
  final bytes = encoder.convert(largeList);
  final decoded = jsonUtf8.decode(bytes) as List;
  Expect.equals(largeList.length, decoded.length);
  for (var i = 0; i < largeList.length; i++) {
    Expect.equals(largeList[i], decoded[i]);
  }
}

/// Verifies extreme micro-buffer sizes (1, 2, 4, 8, 16 bytes) across complex
/// payloads (Unicode, escapes, numbers, maps, arrays).
void testMicroBufferSizeChunkedStreaming() {
  final payload = {
    'string': 'The quick brown fox jumps over the lazy dog',
    'unicode': 'Dart 4.0 \u{1F680} \u20AC \u{10FFFF}',
    'escapes': 'Quotes: "hello" \n\t\r\b\f\\',
    'isolated_surrogates': '\uD800 and \uDFFF',
    'numbers': [0, -1, 42, 9007199254740991, -9007199254740991, 3.14159, 1e-15],
    'booleans': [true, false, null],
  };

  for (final bufferSize in [1, 2, 4, 8, 16, 32, 64]) {
    final byteSink = _ChunkCapturingSink();
    final encoder = JsonUtf8Encoder(null, null, bufferSize);
    final sink = encoder.startChunkedConversion(byteSink);

    sink.add(payload);
    sink.close();

    final chunks = byteSink.chunks;
    for (var i = 0; i < chunks.length; i++) {
      Expect.isTrue(
        chunks[i].length <= bufferSize,
        'Chunk $i length ${chunks[i].length} exceeds bufferSize $bufferSize',
      );
    }

    final totalBytes = chunks.fold<int>(0, (sum, c) => sum + c.length);
    final assembled = Uint8List(totalBytes);
    var offset = 0;
    for (final chunk in chunks) {
      assembled.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    final decoded = jsonUtf8.decode(assembled) as Map<String, dynamic>;
    Expect.equals(payload['string'], decoded['string']);
    Expect.equals(payload['unicode'], decoded['unicode']);
    Expect.equals(payload['escapes'], decoded['escapes']);
    Expect.equals(
      payload['isolated_surrogates'],
      decoded['isolated_surrogates'],
    );
    Expect.equals(42, (decoded['numbers'] as List)[2]);
    Expect.equals(true, (decoded['booleans'] as List)[0]);
  }
}
