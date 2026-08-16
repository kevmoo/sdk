// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testBufferWriterPrimitives();
  testBufferWriterGrowth();
  testBufferWriterToBytesView();
  testBufferWriterNamesAndKeys();
  testBufferWriterStateMachineAndErrors();
  testBothWritersParity();
  testBufferWriterRejectsNonPositiveCapacity();
}

/// A non-positive initial capacity is a caller mistake, usually a size hint
/// that computed to zero, and is reported rather than silently replaced with
/// the default. [JsonUtf8Encoder] rejects its `bufferSize` the same way.
void testBufferWriterRejectsNonPositiveCapacity() {
  for (final capacity in [0, -1, -1000]) {
    Expect.throwsRangeError(
      () => JsonTokenWriter.toBuffer(capacity),
      'initialCapacity $capacity should be rejected',
    );
  }

  // The smallest legal capacity still encodes correctly, growing as needed.
  final w = JsonTokenWriter.toBuffer(1);
  w.beginArray();
  w.writeInt(1);
  w.writeString('two');
  w.writeDouble(3.5);
  w.endArray();
  Expect.equals('[1,"two",3.5]', utf8.decode(w.toBytes()));

  // Omitting the capacity keeps the default.
  final d = JsonTokenWriter.toBuffer();
  d.writeInt(7);
  Expect.equals('7', utf8.decode(d.toBytes()));
}

void testBufferWriterPrimitives() {
  // 1. Root primitives
  {
    final w = JsonTokenWriter.toBuffer(8);
    w.writeInt(42);
    Expect.equals("42", utf8.decode(w.toBytes()));
  }
  {
    final w = JsonTokenWriter.toBuffer();
    w.writeInt(-9223372036854775808);
    Expect.equals("-9223372036854775808", utf8.decode(w.toBytes()));
  }
  {
    final w = JsonTokenWriter.toBuffer();
    w.writeInt(9223372036854775807);
    Expect.equals("9223372036854775807", utf8.decode(w.toBytes()));
  }
  {
    final w = JsonTokenWriter.toBuffer();
    w.writeInt(0);
    Expect.equals("0", utf8.decode(w.toBytes()));
  }
  {
    final w = JsonTokenWriter.toBuffer();
    w.writeDouble(3.14159);
    Expect.equals(3.14159, jsonUtf8Decode(w.toBytes()));
  }
  {
    final w = JsonTokenWriter.toBuffer();
    w.writeBool(true);
    Expect.equals("true", utf8.decode(w.toBytes()));
  }
  {
    final w = JsonTokenWriter.toBuffer();
    w.writeBool(false);
    Expect.equals("false", utf8.decode(w.toBytes()));
  }
  {
    final w = JsonTokenWriter.toBuffer();
    w.writeNull();
    Expect.equals("null", utf8.decode(w.toBytes()));
  }
  {
    final w = JsonTokenWriter.toBuffer();
    w.writeString("hello world \n \t \"quotes\" \\ \u{1F600} €");
    final decoded = jsonUtf8Decode(w.toBytes());
    Expect.equals("hello world \n \t \"quotes\" \\ \u{1F600} €", decoded);
  }

  // 2. Structured Object
  {
    final w = JsonTokenWriter.toBuffer(16);
    w.beginObject();
    w.writeName("name");
    w.writeString("Alice");
    w.writeName("age");
    w.writeInt(30);
    w.writeName("score");
    w.writeDouble(95.5);
    w.writeName("verified");
    w.writeBool(true);
    w.writeName("details");
    w.writeNull();
    w.writeName("tags");
    w.beginArray();
    w.writeString("dart");
    w.writeString("wasm");
    w.writeInt(100);
    w.endArray();
    w.endObject();

    final bytes = w.toBytes();
    final decoded = jsonUtf8Decode(bytes) as Map<String, dynamic>;
    Expect.equals("Alice", decoded["name"]);
    Expect.equals(30, decoded["age"]);
    Expect.equals(95.5, decoded["score"]);
    Expect.equals(true, decoded["verified"]);
    Expect.isNull(decoded["details"]);
    Expect.listEquals(["dart", "wasm", 100], decoded["tags"] as List);
  }
}

void testBufferWriterGrowth() {
  // Start with very tiny buffer capacity = 1 to force frequent growth
  final w = JsonTokenWriter.toBuffer(1);
  w.beginArray();
  for (var i = 0; i < 5000; i++) {
    w.writeInt(i);
  }
  w.endArray();

  final bytes = w.toBytes();
  final decoded = jsonUtf8Decode(bytes) as List;
  Expect.equals(5000, decoded.length);
  for (var i = 0; i < 5000; i++) {
    Expect.equals(i, decoded[i]);
  }

  // Test large strings forcing capacity growth
  final w2 = JsonTokenWriter.toBuffer(4);
  w2.beginObject();
  for (var i = 0; i < 100; i++) {
    w2.writeName("key_$i");
    w2.writeString("value_${"x" * (i * 20)}");
  }
  w2.endObject();

  final decodedObj = jsonUtf8Decode(w2.toBytes()) as Map<String, dynamic>;
  Expect.equals(100, decodedObj.length);
  for (var i = 0; i < 100; i++) {
    Expect.equals("value_${"x" * (i * 20)}", decodedObj["key_$i"]);
  }
}

void testBufferWriterToBytesView() {
  final w = JsonTokenWriter.toBuffer(1024);
  w.beginArray();
  w.writeInt(1);
  w.writeInt(2);
  w.endArray();

  final bytes = w.toBytes();
  Expect.equals(5, bytes.length); // "[1,2]" is 5 bytes
  Expect.equals("[1,2]", utf8.decode(bytes));

  // Verify toBytes() returns Uint8List sublistView
  Expect.isTrue(bytes is Uint8List);
}

void testBufferWriterNamesAndKeys() {
  final w = JsonTokenWriter.toBuffer(32);
  w.beginObject();

  // Standard writeName
  w.writeName("standard");
  w.writeInt(1);

  // Colon-terminated bytes
  w.writeNameBytes(Uint8List.fromList('"colonTerm":'.codeUnits));
  w.writeInt(2);

  // Quoted bytes without colon
  w.writeNameBytes(Uint8List.fromList('"quoted":'.substring(0, 8).codeUnits));
  w.writeInt(3);

  // Raw unquoted bytes
  w.writeNameBytes(Uint8List.fromList('rawKey'.codeUnits));
  w.writeInt(4);

  // Raw bytes needing escaping
  w.writeNameBytes(Uint8List.fromList('esc"\\key'.codeUnits));
  w.writeInt(5);

  // writeAsciiLiteral
  w.writeName("literal");
  w.writeAsciiLiteral(Uint8List.fromList("12345".codeUnits));

  // writeRawJson
  w.writeName("raw");
  w.writeRawJson(Uint8List.fromList('{"inner":true}'.codeUnits));

  w.endObject();

  final decoded = jsonUtf8Decode(w.toBytes()) as Map<String, dynamic>;
  Expect.equals(1, decoded["standard"]);
  Expect.equals(2, decoded["colonTerm"]);
  Expect.equals(3, decoded["quoted"]);
  Expect.equals(4, decoded["rawKey"]);
  Expect.equals(5, decoded['esc"\\key']);
  Expect.equals(12345, decoded["literal"]);
  Expect.mapEquals({"inner": true}, decoded["raw"] as Map);
}

void testBufferWriterStateMachineAndErrors() {
  // writeName in array
  final w1 = JsonTokenWriter.toBuffer();
  w1.beginArray();
  Expect.throwsStateError(() => w1.writeName('a'));

  // value before writeName in object
  final w2 = JsonTokenWriter.toBuffer();
  w2.beginObject();
  Expect.throwsStateError(() => w2.writeInt(1));
  Expect.throwsStateError(() => w2.writeString('val'));
  Expect.throwsStateError(() => w2.writeBool(true));
  Expect.throwsStateError(() => w2.writeNull());
  Expect.throwsStateError(() => w2.beginObject());
  Expect.throwsStateError(() => w2.beginArray());

  // consecutive writeName in object
  final w3 = JsonTokenWriter.toBuffer();
  w3.beginObject();
  w3.writeName('a');
  Expect.throwsStateError(() => w3.writeName('b'));

  // endObject when expecting value
  final w4 = JsonTokenWriter.toBuffer();
  w4.beginObject();
  w4.writeName('a');
  Expect.throwsStateError(() => w4.endObject());

  // mismatched container ends
  final w5 = JsonTokenWriter.toBuffer();
  w5.beginObject();
  Expect.throwsStateError(() => w5.endArray());

  final w6 = JsonTokenWriter.toBuffer();
  w6.beginArray();
  Expect.throwsStateError(() => w6.endObject());

  // Disallow non-finite double
  final w7 = JsonTokenWriter.toBuffer();
  w7.beginArray();
  Expect.throwsArgumentError(() => w7.writeDouble(double.nan));
  Expect.throwsArgumentError(() => w7.writeDouble(double.infinity));
  Expect.throwsArgumentError(() => w7.writeDouble(double.negativeInfinity));

  // Multiple root values
  final w8 = JsonTokenWriter.toBuffer();
  w8.writeInt(1);
  Expect.throwsStateError(() => w8.writeInt(2));

  // Writer max depth limit
  final w9 = JsonTokenWriter.toBuffer();
  Expect.throwsStateError(() {
    for (var i = 0; i < 65; i++) {
      w9.beginArray();
    }
  });
}

void testBothWritersParity() {
  void populate(JsonTokenWriter writer) {
    writer.beginObject();
    writer.writeName("alpha");
    writer.writeInt(123456);
    writer.writeName("beta");
    writer.writeDouble(-42.75);
    writer.writeName("gamma");
    writer.writeBool(false);
    writer.writeName("delta");
    writer.writeNull();
    writer.writeName("epsilon");
    writer.writeString("Unicode 🚀 \u0000 \t \n \"quote\"");
    writer.writeName("nested");
    writer.beginArray();
    writer.writeInt(1);
    writer.writeInt(2);
    writer.beginObject();
    writer.writeName("inner");
    writer.writeString("val");
    writer.endObject();
    writer.endArray();
    writer.endObject();
  }

  final sinkWriter = JsonTokenWriter.toSink(BytesBuilder());
  populate(sinkWriter);
  final sinkBytes = sinkWriter.toBytes();

  final bufferWriter = JsonTokenWriter.toBuffer();
  populate(bufferWriter);
  final bufferBytes = bufferWriter.toBytes();

  Expect.listEquals(sinkBytes, bufferBytes);
}
