// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testUnmodifiableViewsTokenReader();
  testTokenWriterBuffer();
  testTokenWriterSink();
  testNonByteTypedDataArguments();
  testEmptyAndBoundarySliceParsing();
  testZeroCapacityBufferWrites();
}

void testUnmodifiableViewsTokenReader() {
  final jsonBytes = Uint8List.fromList(
    utf8.encode('{"key": "value", "num": 123.45, "arr": [true, null]}'),
  );
  final unmodifiableViews = <Uint8List>[
    jsonBytes.asUnmodifiableView(),
    Uint8List.sublistView(jsonBytes.asUnmodifiableView(), 0, jsonBytes.length),
    Uint8List.sublistView(jsonBytes, 0, jsonBytes.length).asUnmodifiableView(),
  ];

  for (final unmodifiable in unmodifiableViews) {
    final reader = JsonTokenReader.fromBytes(unmodifiable);
    reader.beginObject();
    Expect.equals("key", reader.nextName());
    Expect.equals("value", reader.readString());
    Expect.equals("num", reader.nextName());
    Expect.equals(123.45, reader.readDouble());
    Expect.equals("arr", reader.nextName());
    reader.beginArray();
    Expect.equals(true, reader.readBool());
    reader.readNull();
    reader.endArray();
    reader.endObject();
  }
}

void testTokenWriterBuffer() {
  final w = JsonTokenWriter.toBuffer();
  w.beginObject();
  w.writeName("hello");
  w.writeString("world");
  w.writeName("pi");
  w.writeDouble(3.14159);
  w.writeName("flag");
  w.writeBool(true);
  w.writeName("empty");
  w.writeString("");
  w.writeName("high");
  w.writeString("\uD800");
  w.writeName("rocket");
  w.writeString("🚀");
  w.endObject();

  final bytes = w.toBytes();
  Expect.isTrue(bytes.isNotEmpty);
  final decoded = jsonUtf8Decode(bytes) as Map<String, dynamic>;
  Expect.equals("world", decoded["hello"]);
  Expect.equals(3.14159, decoded["pi"]);
  Expect.equals(true, decoded["flag"]);
  Expect.equals("", decoded["empty"]);
  Expect.equals("\uD800", decoded["high"]);
  Expect.equals("🚀", decoded["rocket"]);
}

void testTokenWriterSink() {
  final b = BytesBuilder(copy: false);
  final w = JsonTokenWriter.toSink(b);
  w.beginArray();
  w.writeString("test");
  w.writeDouble(42.0);
  w.writeBool(false);
  w.writeNull();
  w.endArray();

  final bytes = w.toBytes();
  final decoded = jsonUtf8Decode(bytes) as List<dynamic>;
  Expect.equals("test", decoded[0]);
  Expect.equals(42.0, decoded[1]);
  Expect.equals(false, decoded[2]);
  Expect.isNull(decoded[3]);
}

void testNonByteTypedDataArguments() {
  final int32List = Int32List(16);
  final float64List = Float64List(8);
  final uint16List = Uint16List(16);

  final nonByteBuffers = <dynamic>[int32List, float64List, uint16List];

  for (final buf in nonByteBuffers) {
    Expect.throws(
      () => JsonTokenReader.fromBytes(buf),
      (e) => e is ArgumentError || e is TypeError,
    );
  }
}

void testEmptyAndBoundarySliceParsing() {
  final emptyBuf = Uint8List(0);
  Expect.throwsFormatException(
    () => JsonTokenReader.fromBytes(emptyBuf).readDouble(),
  );

  final sampleBytes = Uint8List.fromList(utf8.encode("3.14159"));
  final emptySlice = Uint8List.sublistView(sampleBytes, 0, 0);
  Expect.throwsFormatException(
    () => JsonTokenReader.fromBytes(emptySlice).readDouble(),
  );
}

void testZeroCapacityBufferWrites() {
  Expect.throws(() => JsonTokenWriter.toBuffer(0), (e) => e is RangeError);
  Expect.throws(() => JsonTokenWriter.toBuffer(-1), (e) => e is RangeError);
}
