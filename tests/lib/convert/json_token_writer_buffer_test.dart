// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testSinkWriterPrimitives();
  testSinkWriterNamesAndKeys();
  testSinkWriterStateMachineAndErrors();
  testSinkWriterParity();
  testSinkWriterDoesNotAliasScratch();
  testSinkWriterMaxDepthLimit();
  testShortStringAndPropertyNameFastPath();
}

/// The sink writer formats values into a reusable scratch block and hands the
/// bytes to the sink as a view rather than a copy.
///
/// `BytesBuilder(copy: false)` keeps every added list until `takeBytes` and
/// documents that an added list "should not change its content after being
/// added", so a scratch region that has been handed over must never be written
/// again. Writing several values through one writer is what exercises that: a
/// single value cannot alias anything.
void testSinkWriterDoesNotAliasScratch() {
  void check(String expected, void Function(JsonTokenWriter) build) {
    for (final copy in [true, false]) {
      final sink = BytesBuilder(copy: copy);
      final writer = JsonTokenWriter.toSink(sink);
      build(writer);
      writer.flush();
      Expect.equals(
        expected,
        utf8.decode(sink.takeBytes()),
        'BytesBuilder(copy: $copy)',
      );
    }
  }

  check('[11,22,33]', (w) {
    w.beginArray();
    w.writeInt(11);
    w.writeInt(22);
    w.writeInt(33);
    w.endArray();
  });

  check('["alpha","bravo","charlie"]', (w) {
    w.beginArray();
    w.writeString('alpha');
    w.writeString('bravo');
    w.writeString('charlie');
    w.endArray();
  });

  check('[1.5,7,2.25]', (w) {
    w.beginArray();
    w.writeDouble(1.5);
    w.writeInt(7);
    w.writeDouble(2.25);
    w.endArray();
  });

  check('{"first":1,"second":"two","third":3.5}', (w) {
    w.beginObject();
    w.writeName('first');
    w.writeInt(1);
    w.writeName('second');
    w.writeString('two');
    w.writeName('third');
    w.writeDouble(3.5);
    w.endObject();
  });

  // Enough values to refill the scratch block many times, mixing the lengths
  // so the reserve boundary is crossed at varying offsets. Strings stay short
  // enough to take the scratch path rather than the streaming one.
  final expected = StringBuffer('[');
  for (var i = 0; i < 500; i++) {
    if (i > 0) expected.write(',');
    expected.write('$i,"s$i",${i + 0.5}');
  }
  expected.write(']');
  check(expected.toString(), (w) {
    w.beginArray();
    for (var i = 0; i < 500; i++) {
      w.writeInt(i);
      w.writeString('s$i');
      w.writeDouble(i + 0.5);
    }
    w.endArray();
  });

  // Nested containers interleave structural bytes with scratch emissions.
  check('{"a":[1,2],"b":{"c":"x","d":"y"}}', (w) {
    w.beginObject();
    w.writeName('a');
    w.beginArray();
    w.writeInt(1);
    w.writeInt(2);
    w.endArray();
    w.writeName('b');
    w.beginObject();
    w.writeName('c');
    w.writeString('x');
    w.writeName('d');
    w.writeString('y');
    w.endObject();
    w.endObject();
  });
}

void testSinkWriterPrimitives() {
  // 1. Root primitives
  {
    final sink = BytesBuilder();
    final w = JsonTokenWriter.toSink(sink);
    w.writeInt(42);
    w.flush();
    Expect.equals("42", utf8.decode(sink.takeBytes()));
  }
  {
    final sink = BytesBuilder();
    final w = JsonTokenWriter.toSink(sink);
    w.writeInt(int.parse("-9223372036854775808"));
    w.flush();
    if (!identical(1, 1.0)) {
      Expect.equals("-9223372036854775808", utf8.decode(sink.takeBytes()));
    }
  }
  {
    final sink = BytesBuilder();
    final w = JsonTokenWriter.toSink(sink);
    w.writeInt(int.parse("9223372036854775807"));
    w.flush();
    if (!identical(1, 1.0)) {
      Expect.equals("9223372036854775807", utf8.decode(sink.takeBytes()));
    }
  }
  {
    final sink = BytesBuilder();
    final w = JsonTokenWriter.toSink(sink);
    w.writeInt(0);
    w.flush();
    Expect.equals("0", utf8.decode(sink.takeBytes()));
  }
  {
    final sink = BytesBuilder();
    final w = JsonTokenWriter.toSink(sink);
    w.writeDouble(3.14159);
    w.flush();
    Expect.equals(3.14159, jsonUtf8Decode(sink.takeBytes()));
  }
  {
    final sink = BytesBuilder();
    final w = JsonTokenWriter.toSink(sink);
    w.writeBool(true);
    w.flush();
    Expect.equals("true", utf8.decode(sink.takeBytes()));
  }
  {
    final sink = BytesBuilder();
    final w = JsonTokenWriter.toSink(sink);
    w.writeBool(false);
    w.flush();
    Expect.equals("false", utf8.decode(sink.takeBytes()));
  }
  {
    final sink = BytesBuilder();
    final w = JsonTokenWriter.toSink(sink);
    w.writeNull();
    w.flush();
    Expect.equals("null", utf8.decode(sink.takeBytes()));
  }
  {
    final sink = BytesBuilder();
    final w = JsonTokenWriter.toSink(sink);
    w.writeString("hello world \n \t \"quotes\" \\ \u{1F600} €");
    w.flush();
    final decoded = jsonUtf8Decode(sink.takeBytes());
    Expect.equals("hello world \n \t \"quotes\" \\ \u{1F600} €", decoded);
  }

  // 2. Structured Object
  {
    final sink = BytesBuilder();
    final w = JsonTokenWriter.toSink(sink);
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
    w.flush();

    final bytes = sink.takeBytes();
    final decoded = jsonUtf8Decode(bytes) as Map<String, dynamic>;
    Expect.equals("Alice", decoded["name"]);
    Expect.equals(30, decoded["age"]);
    Expect.equals(95.5, decoded["score"]);
    Expect.equals(true, decoded["verified"]);
    Expect.isNull(decoded["details"]);
    Expect.listEquals(["dart", "wasm", 100], decoded["tags"] as List);
  }
}

void testSinkWriterNamesAndKeys() {
  final sink = BytesBuilder();
  final w = JsonTokenWriter.toSink(sink);
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
  w.flush();

  final decoded = jsonUtf8Decode(sink.takeBytes()) as Map<String, dynamic>;
  Expect.equals(1, decoded["standard"]);
  Expect.equals(2, decoded["colonTerm"]);
  Expect.equals(3, decoded["quoted"]);
  Expect.equals(4, decoded["rawKey"]);
  Expect.equals(5, decoded['esc"\\key']);
  Expect.equals(12345, decoded["literal"]);
  Expect.mapEquals({"inner": true}, decoded["raw"] as Map);
}

void testSinkWriterStateMachineAndErrors() {
  // writeName in array
  final w1 = JsonTokenWriter.toSink(BytesBuilder());
  w1.beginArray();
  Expect.throwsStateError(() => w1.writeName('a'));

  // value before writeName in object
  final w2 = JsonTokenWriter.toSink(BytesBuilder());
  w2.beginObject();
  Expect.throwsStateError(() => w2.writeInt(1));
  Expect.throwsStateError(() => w2.writeString('val'));
  Expect.throwsStateError(() => w2.writeBool(true));
  Expect.throwsStateError(() => w2.writeNull());
  Expect.throwsStateError(() => w2.beginObject());
  Expect.throwsStateError(() => w2.beginArray());

  // consecutive writeName in object
  final w3 = JsonTokenWriter.toSink(BytesBuilder());
  w3.beginObject();
  w3.writeName('a');
  Expect.throwsStateError(() => w3.writeName('b'));

  // endObject when expecting value
  final w4 = JsonTokenWriter.toSink(BytesBuilder());
  w4.beginObject();
  w4.writeName('a');
  Expect.throwsStateError(() => w4.endObject());

  // mismatched container ends
  final w5 = JsonTokenWriter.toSink(BytesBuilder());
  w5.beginObject();
  Expect.throwsStateError(() => w5.endArray());

  final w6 = JsonTokenWriter.toSink(BytesBuilder());
  w6.beginArray();
  Expect.throwsStateError(() => w6.endObject());

  // Disallow non-finite double
  final w7 = JsonTokenWriter.toSink(BytesBuilder());
  w7.beginArray();
  Expect.throwsArgumentError(() => w7.writeDouble(double.nan));
  Expect.throwsArgumentError(() => w7.writeDouble(double.infinity));
  Expect.throwsArgumentError(() => w7.writeDouble(double.negativeInfinity));

  // Multiple root values
  final w8 = JsonTokenWriter.toSink(BytesBuilder());
  w8.writeInt(1);
  Expect.throwsStateError(() => w8.writeInt(2));

  // Writer max depth limit
  final w9 = JsonTokenWriter.toSink(BytesBuilder());
  Expect.throwsStateError(() {
    for (var i = 0; i < 1025; i++) {
      w9.beginArray();
    }
  });
}

void testSinkWriterParity() {
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

  final sink = BytesBuilder();
  final sinkWriter = JsonTokenWriter.toSink(sink);
  populate(sinkWriter);
  sinkWriter.flush();
  final sinkBytes = sink.takeBytes();

  // Pin to json.encode
  final expected = json.encode({
    "alpha": 123456,
    "beta": -42.75,
    "gamma": false,
    "delta": null,
    "epsilon": "Unicode \u{1F680} \u0000 \t \n \"quote\"",
    "nested": [
      1,
      2,
      {"inner": "val"},
    ],
  });
  Expect.equals(expected, utf8.decode(sinkBytes));
}

void testSinkWriterMaxDepthLimit() {
  // 1. Sink writer: 1,024 nested arrays succeeds cleanly
  final sinkArrOk = BytesBuilder();
  final wSinkArrOk = JsonTokenWriter.toSink(sinkArrOk);
  for (var i = 0; i < 1024; i++) {
    wSinkArrOk.beginArray();
  }
  for (var i = 0; i < 1024; i++) {
    wSinkArrOk.endArray();
  }
  wSinkArrOk.flush();
  Expect.equals('[' * 1024 + ']' * 1024, utf8.decode(sinkArrOk.takeBytes()));

  // 2. Sink writer: 1,024 nested objects succeeds cleanly
  final sinkObjOk = BytesBuilder();
  final wSinkObjOk = JsonTokenWriter.toSink(sinkObjOk);
  for (var i = 0; i < 1024; i++) {
    wSinkObjOk.beginObject();
    wSinkObjOk.writeName('a');
  }
  wSinkObjOk.writeInt(42);
  for (var i = 0; i < 1024; i++) {
    wSinkObjOk.endObject();
  }
  wSinkObjOk.flush();
  Expect.equals(
    '{"a":' * 1024 + '42' + '}' * 1024,
    utf8.decode(sinkObjOk.takeBytes()),
  );

  // 3. Sink writer: 1,025 nested arrays throws StateError
  final wSinkArrExceed = JsonTokenWriter.toSink(BytesBuilder());
  Expect.throwsStateError(() {
    for (var i = 0; i < 1025; i++) {
      wSinkArrExceed.beginArray();
    }
  });

  // 4. Sink writer: 1,025 nested objects throws StateError
  final wSinkObjExceed = JsonTokenWriter.toSink(BytesBuilder());
  Expect.throwsStateError(() {
    for (var i = 0; i < 1025; i++) {
      wSinkObjExceed.beginObject();
      wSinkObjExceed.writeName('a');
    }
  });
}

void testShortStringAndPropertyNameFastPath() {
  final testStrings = <String>[
    "",
    "a",
    "id",
    "key",
    "name",
    "status",
    "created_at",
    "description",
    "a" * 15,
    "a" * 16,
    "a" * 31,
    "a" * 32,
    "a" * 33,
    "a" * 40,
    "a" * 50,
    "a" * 100,
    "escaped\"quote",
    "back\\slash",
    "new\nline",
    "tab\tchar",
    "cr\rchar",
    "control\x00char",
    "control\x1Fchar",
    "euro € sign",
    "rocket 🚀 emoji",
    "japanese 日本語 text",
  ];

  for (final s in testStrings) {
    // 1. Value string writing
    {
      final sink = BytesBuilder();
      final sinkWriter = JsonTokenWriter.toSink(sink);
      sinkWriter.writeString(s);
      sinkWriter.flush();
      final sinkBytes = sink.takeBytes();
      Expect.equals(json.encode(s), utf8.decode(sinkBytes));
    }

    // 2. Object property name writing
    {
      final sink = BytesBuilder();
      final sinkWriter = JsonTokenWriter.toSink(sink);
      sinkWriter.beginObject();
      sinkWriter.writeName(s);
      sinkWriter.writeInt(42);
      sinkWriter.endObject();
      sinkWriter.flush();
      final sinkBytes = sink.takeBytes();
      Expect.equals(json.encode({s: 42}), utf8.decode(sinkBytes));
    }
  }
}
