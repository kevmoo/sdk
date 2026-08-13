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
