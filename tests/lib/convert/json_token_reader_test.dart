// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testTokenReaderPrimitives();
  testTokenReaderNestedStructures();
  testTokenReaderSelectName();
  testTokenReaderSelectString();
  testTokenReaderSkipValue();
  testTokenWriter();
  testDomainModelStreaming();
  testTokenReaderCommas();
  testTokenReaderPeekAndTokenSpan();
  testTokenWriterStateMachine();
  testMaxNestingDepthLimits();
  testTokenReaderOutsideObject();
  testTokenWriterMultipleRoots();
  testTokenReaderPeekWithCommas();
}

void testTokenReaderPrimitives() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // String
  var reader = JsonTokenReader.fromBytes(b('"hello world"'));
  Expect.equals(JsonTokenType.string, reader.peek());
  Expect.equals('hello world', reader.readString());

  // Int
  reader = JsonTokenReader.fromBytes(b('12345'));
  Expect.equals(JsonTokenType.number, reader.peek());
  Expect.equals(12345, reader.readInt());

  // Double
  reader = JsonTokenReader.fromBytes(b('3.14159'));
  Expect.equals(JsonTokenType.number, reader.peek());
  Expect.equals(3.14159, reader.readDouble());

  // Double from Int
  reader = JsonTokenReader.fromBytes(b('42'));
  Expect.equals(42.0, reader.readDouble());

  // Num
  reader = JsonTokenReader.fromBytes(b('100'));
  Expect.equals(100, reader.readNum());
  reader = JsonTokenReader.fromBytes(b('100.5'));
  Expect.equals(100.5, reader.readNum());

  // Bool
  reader = JsonTokenReader.fromBytes(b('true'));
  Expect.equals(JsonTokenType.boolean, reader.peek());
  Expect.isTrue(reader.readBool());

  reader = JsonTokenReader.fromBytes(b('false'));
  Expect.equals(JsonTokenType.boolean, reader.peek());
  Expect.isFalse(reader.readBool());

  // Null
  reader = JsonTokenReader.fromBytes(b('null'));
  Expect.equals(JsonTokenType.nullValue, reader.peek());
  reader.readNull();
}

void testTokenReaderNestedStructures() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Empty object
  var reader = JsonTokenReader.fromBytes(b('{}'));
  Expect.equals(JsonTokenType.beginObject, reader.peek());
  reader.beginObject();
  Expect.isFalse(reader.hasNext());
  reader.endObject();

  // Simple object
  reader = JsonTokenReader.fromBytes(b('{"a": 1, "b": "two", "c": true}'));
  reader.beginObject();
  Expect.isTrue(reader.hasNext());
  Expect.equals('a', reader.nextName());
  Expect.equals(1, reader.readInt());

  Expect.isTrue(reader.hasNext());
  Expect.equals('b', reader.nextName());
  Expect.equals('two', reader.readString());

  Expect.isTrue(reader.hasNext());
  Expect.equals('c', reader.nextName());
  Expect.isTrue(reader.readBool());

  Expect.isFalse(reader.hasNext());
  reader.endObject();

  // Array
  reader = JsonTokenReader.fromBytes(b('[10, 20, 30]'));
  Expect.equals(JsonTokenType.beginArray, reader.peek());
  reader.beginArray();
  Expect.isTrue(reader.hasNext());
  Expect.equals(10, reader.readInt());
  Expect.isTrue(reader.hasNext());
  Expect.equals(20, reader.readInt());
  Expect.isTrue(reader.hasNext());
  Expect.equals(30, reader.readInt());
  Expect.isFalse(reader.hasNext());
  reader.endArray();
}

void testTokenReaderSelectName() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final options = JsonKeyOptions.of(['id', 'title', 'active', 'tags']);
  final reader = JsonTokenReader.fromBytes(
    b('{"title": "Dart 4", "id": 42, "unknown": "skip", "active": true}'),
  );

  reader.beginObject();

  // "title" -> index 1
  Expect.equals(1, reader.selectName(options));
  Expect.equals('Dart 4', reader.readString());

  // "id" -> index 0
  Expect.equals(0, reader.selectName(options));
  Expect.equals(42, reader.readInt());

  // "unknown" -> index -1
  Expect.equals(-1, reader.selectName(options));
  reader.skipValue();

  // "active" -> index 2
  Expect.equals(2, reader.selectName(options));
  Expect.isTrue(reader.readBool());

  Expect.isFalse(reader.hasNext());
  reader.endObject();
}

void testTokenReaderSelectString() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final roles = JsonKeyOptions.of(['admin', 'member', 'guest']);
  final reader = JsonTokenReader.fromBytes(b('["guest", "admin", "member"]'));

  reader.beginArray();
  Expect.equals(2, reader.selectString(roles)); // "guest"
  Expect.equals(0, reader.selectString(roles)); // "admin"
  Expect.equals(1, reader.selectString(roles)); // "member"
  Expect.isFalse(reader.hasNext());
  reader.endArray();
}

void testTokenReaderSkipValue() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final reader = JsonTokenReader.fromBytes(
    b('{"skipMe": {"nested": [1, 2, {"a": "b"}]}, "keepMe": 100}'),
  );

  reader.beginObject();
  Expect.equals('skipMe', reader.nextName());
  reader.skipValue();

  Expect.isTrue(reader.hasNext());
  Expect.equals('keepMe', reader.nextName());
  Expect.equals(100, reader.readInt());
  reader.endObject();
}

void testTokenWriter() {
  final sink = BytesBuilder();
  final writer = JsonTokenWriter.toSink(sink);

  writer.beginObject();
  writer.writeName('name');
  writer.writeString('Alice');
  writer.writeName('age');
  writer.writeInt(30);
  writer.writeName('score');
  writer.writeDouble(95.5);
  writer.writeName('verified');
  writer.writeBool(true);
  writer.writeName('details');
  writer.writeNull();
  writer.writeName('tags');
  writer.beginArray();
  writer.writeString('dart');
  writer.writeString('wasm');
  writer.endArray();
  writer.endObject();

  final jsonStr = utf8.decode(sink.takeBytes());
  final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

  Expect.equals('Alice', decoded['name']);
  Expect.equals(30, decoded['age']);
  Expect.equals(95.5, decoded['score']);
  Expect.equals(true, decoded['verified']);
  Expect.isNull(decoded['details']);
  Expect.listEquals(['dart', 'wasm'], decoded['tags'] as List);
}

void testDomainModelStreaming() {
  // Coordinate Domain Model streaming test
  final coordJson = '{"latitude": 37.7749, "longitude": -122.4194}';
  final bytes = Uint8List.fromList(utf8.encode(coordJson));

  final keys = JsonKeyOptions.of(['latitude', 'longitude', 'lat', 'lon']);
  final reader = JsonTokenReader.fromBytes(bytes);

  double? lat;
  double? lon;

  reader.beginObject();
  while (reader.hasNext()) {
    switch (reader.selectName(keys)) {
      case 0: // latitude
      case 2: // lat
        lat = reader.readDouble();
      case 1: // longitude
      case 3: // lon
        lon = reader.readDouble();
      default:
        reader.skipValue();
    }
  }
  reader.endObject();

  Expect.equals(37.7749, lat);
  Expect.equals(-122.4194, lon);
}

void testTokenReaderCommas() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Trailing comma in object
  final r1 = JsonTokenReader.fromBytes(b('{"a": 1,}'));
  r1.beginObject();
  Expect.isTrue(r1.hasNext());
  Expect.equals('a', r1.nextName());
  Expect.equals(1, r1.readInt());
  Expect.throwsFormatException(() => r1.hasNext());

  // Missing comma in object
  final r2 = JsonTokenReader.fromBytes(b('{"a": 1 "b": 2}'));
  r2.beginObject();
  Expect.isTrue(r2.hasNext());
  Expect.equals('a', r2.nextName());
  Expect.equals(1, r2.readInt());
  Expect.throwsFormatException(() => r2.hasNext());

  // Trailing comma in array
  final r3 = JsonTokenReader.fromBytes(b('[1, 2,]'));
  r3.beginArray();
  Expect.isTrue(r3.hasNext());
  Expect.equals(1, r3.readInt());
  Expect.isTrue(r3.hasNext());
  Expect.equals(2, r3.readInt());
  Expect.throwsFormatException(() => r3.hasNext());

  // Trailing comma in single-item array
  final r4 = JsonTokenReader.fromBytes(b('[1,]'));
  r4.beginArray();
  Expect.isTrue(r4.hasNext());
  Expect.equals(1, r4.readInt());
  Expect.throwsFormatException(() => r4.hasNext());

  // Missing comma in array
  final r5 = JsonTokenReader.fromBytes(b('[1 2]'));
  r5.beginArray();
  Expect.isTrue(r5.hasNext());
  Expect.equals(1, r5.readInt());
  Expect.throwsFormatException(() => r5.hasNext());
}

void testTokenReaderPeekAndTokenSpan() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final bytes = b('{"key": "val", "num": 42}');
  final r = JsonTokenReader.fromBytes(bytes);
  r.beginObject();

  // Inside object before key: peek must return propertyName
  Expect.equals(JsonTokenType.propertyName, r.peek());

  // getTokenSpan is non-destructive
  final (s1, e1) = r.getTokenSpan();
  Expect.equals('key', utf8.decode(bytes.sublist(s1, e1)));
  Expect.equals(JsonTokenType.propertyName, r.peek());
  final (s1b, e1b) = r.getTokenSpan();
  Expect.equals(s1, s1b);
  Expect.equals(e1, e1b);

  Expect.equals('key', r.nextName());

  // After nextName (after colon): peek returns string
  Expect.equals(JsonTokenType.string, r.peek());
  Expect.equals('val', r.readString());

  Expect.isTrue(r.hasNext());
  Expect.equals(JsonTokenType.propertyName, r.peek());
  Expect.equals('num', r.nextName());

  Expect.equals(JsonTokenType.number, r.peek());
  final (s2, e2) = r.getTokenSpan();
  Expect.equals('42', utf8.decode(bytes.sublist(s2, e2)));
  Expect.equals(42, r.readInt());

  Expect.isFalse(r.hasNext());
  r.endObject();
}

void testTokenWriterStateMachine() {
  // Disallow writeName in array
  final w1 = JsonTokenWriter.toSink(BytesBuilder());
  w1.beginArray();
  Expect.throwsStateError(() => w1.writeName('a'));

  // Disallow value before writeName in object
  final w2 = JsonTokenWriter.toSink(BytesBuilder());
  w2.beginObject();
  Expect.throwsStateError(() => w2.writeInt(1));
  Expect.throwsStateError(() => w2.writeString('val'));
  Expect.throwsStateError(() => w2.writeBool(true));
  Expect.throwsStateError(() => w2.writeNull());
  Expect.throwsStateError(() => w2.beginObject());
  Expect.throwsStateError(() => w2.beginArray());

  // Disallow consecutive writeName in object
  final w3 = JsonTokenWriter.toSink(BytesBuilder());
  w3.beginObject();
  w3.writeName('a');
  Expect.throwsStateError(() => w3.writeName('b'));

  // Disallow endObject when expecting value
  final w4 = JsonTokenWriter.toSink(BytesBuilder());
  w4.beginObject();
  w4.writeName('a');
  Expect.throwsStateError(() => w4.endObject());

  // Disallow mismatched container ends
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
}

void testMaxNestingDepthLimits() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Reader object depth limit
  final nestedObj = '{' * 65 + '}' * 65;
  final rObj = JsonTokenReader.fromBytes(b(nestedObj));
  Expect.throwsFormatException(() {
    for (var i = 0; i < 65; i++) {
      rObj.beginObject();
    }
  });

  // Reader array depth limit
  final nestedArr = '[' * 65 + ']' * 65;
  final rArr = JsonTokenReader.fromBytes(b(nestedArr));
  Expect.throwsFormatException(() {
    for (var i = 0; i < 65; i++) {
      rArr.beginArray();
    }
  });

  // Writer depth limit
  final w = JsonTokenWriter.toSink(BytesBuilder());
  Expect.throws(() {
    for (var i = 0; i < 65; i++) {
      w.beginArray();
    }
  }, (e) => e is StateError || e is FormatException);
}

void testTokenReaderOutsideObject() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Cannot nextName at root
  final rRoot = JsonTokenReader.fromBytes(b('"hello": 123'));
  Expect.throwsFormatException(() => rRoot.nextName());

  // Cannot nextName in array
  final rArr = JsonTokenReader.fromBytes(b('["item": 123]'));
  rArr.beginArray();
  Expect.throwsFormatException(() => rArr.nextName());

  // Cannot nextName when waiting for value (afterName)
  final rObj = JsonTokenReader.fromBytes(b('{"a": "b": "c"}'));
  rObj.beginObject();
  Expect.equals('a', rObj.nextName());
  Expect.throwsFormatException(() => rObj.nextName());
}

void testTokenWriterMultipleRoots() {
  // Disallow multiple primitive root values
  final w1 = JsonTokenWriter.toSink(BytesBuilder());
  w1.writeInt(1);
  Expect.throwsStateError(() => w1.writeInt(2));

  // Disallow root value after container
  final w2 = JsonTokenWriter.toSink(BytesBuilder());
  w2.beginObject();
  w2.endObject();
  Expect.throwsStateError(() => w2.writeInt(1));

  // Disallow container after root value
  final w3 = JsonTokenWriter.toSink(BytesBuilder());
  w3.writeString('root');
  Expect.throwsStateError(() => w3.beginArray());
}

void testTokenReaderPeekWithCommas() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Peek across array comma
  final rArr = JsonTokenReader.fromBytes(b('[10, 20]'));
  rArr.beginArray();
  Expect.equals(10, rArr.readInt());
  Expect.equals(JsonTokenType.number, rArr.peek());
  final (s, e) = rArr.getTokenSpan();
  Expect.equals('20', utf8.decode(b('[10, 20]').sublist(s, e)));
  Expect.equals(20, rArr.readInt());
  Expect.equals(JsonTokenType.endArray, rArr.peek());
  rArr.endArray();

  // Peek across object comma
  final rObj = JsonTokenReader.fromBytes(b('{"a": 1, "b": 2}'));
  rObj.beginObject();
  Expect.equals('a', rObj.nextName());
  Expect.equals(1, rObj.readInt());
  Expect.equals(JsonTokenType.propertyName, rObj.peek());
  final (s2, e2) = rObj.getTokenSpan();
  Expect.equals('b', utf8.decode(b('{"a": 1, "b": 2}').sublist(s2, e2)));
  Expect.equals('b', rObj.nextName());
  Expect.equals(2, rObj.readInt());
  Expect.equals(JsonTokenType.endObject, rObj.peek());
  rObj.endObject();
}
