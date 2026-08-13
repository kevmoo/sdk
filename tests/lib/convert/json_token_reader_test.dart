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
  testTokenReaderUtf8Bom();
  testDeepObjectTrees();
  testTokenReaderNonDestructivePeek();
  testTokenReaderControlCharacters();
  testTokenReaderComplexNestingSkipValue();
  testContainerDelimiterSpans();
  testPeekMissingCommaError();
  testWriteNameBytesPreQuoted();
  testSkipValueMaxDepthLimit();
  testSelectNameEscapedKeys();
  testSelectStringEscapedEnums();
  testTokenReaderCursorRollbackOnFormatException();
  testAllowMalformedUtf8();
  testSelectNameSurrogatePairsAndNonAscii();
  testNextNameAndReadStringRollback();
  testAllowMalformedUtf8WithEscapes();
  testTrailingCommaPeekRejection();
  testTokenReaderMultipleRoots();
  testTokenReaderSkipValueControlChars();
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

void testTokenReaderUtf8Bom() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Leading BOM followed by JSON
  final withBom = Uint8List.fromList([
    0xEF,
    0xBB,
    0xBF,
    0x74,
    0x72,
    0x75,
    0x65,
  ]); // BOM + 'true'
  final r1 = JsonTokenReader.fromBytes(withBom);
  Expect.equals(JsonTokenType.boolean, r1.peek());
  Expect.isTrue(r1.readBool());

  // BOM followed by object
  final objWithBom = Uint8List.fromList([
    0xEF,
    0xBB,
    0xBF,
    ...utf8.encode('{"id": 42}'),
  ]);
  final r2 = JsonTokenReader.fromBytes(objWithBom);
  Expect.equals(JsonTokenType.beginObject, r2.peek());
  r2.beginObject();
  Expect.equals('id', r2.nextName());
  Expect.equals(42, r2.readInt());
  r2.endObject();

  // BOM in middle of document should return none for peek and throw on read
  final midBom = b('{"a": \xEF\xBB\xBF 1}');
  final r3 = JsonTokenReader.fromBytes(midBom);
  r3.beginObject();
  Expect.equals('a', r3.nextName());
  Expect.equals(JsonTokenType.none, r3.peek());
  Expect.throwsFormatException(() => r3.readInt());
}

void testDeepObjectTrees() {
  // Test depth up to 64
  var nested = '{"a": ' * 64 + '42' + '}' * 64;
  final bytes = Uint8List.fromList(utf8.encode(nested));
  final reader = JsonTokenReader.fromBytes(bytes);
  for (var i = 0; i < 64; i++) {
    reader.beginObject();
    Expect.equals('a', reader.nextName());
  }
  Expect.equals(42, reader.readInt());
  for (var i = 0; i < 64; i++) {
    reader.endObject();
  }

  // Test depth > 64 throws FormatException
  var deep = '{"a": ' * 65 + '42' + '}' * 65;
  final deepBytes = Uint8List.fromList(utf8.encode(deep));
  final deepReader = JsonTokenReader.fromBytes(deepBytes);
  Expect.throwsFormatException(() {
    for (var i = 0; i < 65; i++) {
      deepReader.beginObject();
      deepReader.nextName();
    }
  });
}

void testTokenReaderNonDestructivePeek() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // 1. Whitespace in front of value: peek() should not mutate _offset
  final bytes = b('   42');
  final reader = JsonTokenReader.fromBytes(bytes);
  Expect.equals(JsonTokenType.number, reader.peek());
  Expect.equals(JsonTokenType.number, reader.peek());
  Expect.equals(42, reader.readInt());

  // 2. Whitespace in front of object: peek() should not mutate _offset
  final objBytes = b('   {"k": 1}');
  final objReader = JsonTokenReader.fromBytes(objBytes);
  Expect.equals(JsonTokenType.beginObject, objReader.peek());
  Expect.equals(JsonTokenType.beginObject, objReader.peek());
  objReader.beginObject();
  Expect.equals(JsonTokenType.propertyName, objReader.peek());
  Expect.equals('k', objReader.nextName());
  Expect.equals(1, objReader.readInt());
  objReader.endObject();
}

void testTokenReaderControlCharacters() {
  // Unescaped control characters in strings must throw FormatException
  final bVal = Uint8List.fromList([0x22, 0x0A, 0x22]); // '"\n"'
  final rVal = JsonTokenReader.fromBytes(bVal);
  Expect.throwsFormatException(() => rVal.readString());

  final bName = Uint8List.fromList([
    0x7B,
    0x22,
    0x01,
    0x22,
    0x3A,
    0x31,
    0x7D,
  ]); // '{"\x01":1}'
  final rName = JsonTokenReader.fromBytes(bName);
  rName.beginObject();
  Expect.throwsFormatException(() => rName.nextName());

  final rSpan = JsonTokenReader.fromBytes(bVal);
  Expect.throwsFormatException(() => rSpan.getTokenSpan());
}

void testTokenReaderComplexNestingSkipValue() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final complexJson = b('{"skip": [{"a": [1, 2]}, {"b": [3, 4]}], "keep": 99}');
  final r = JsonTokenReader.fromBytes(complexJson);
  r.beginObject();
  Expect.equals('skip', r.nextName());
  r.skipValue();
  Expect.isTrue(r.hasNext());
  Expect.equals('keep', r.nextName());
  Expect.equals(99, r.readInt());
  r.endObject();

  // Nested array skipValue with inner objects
  final arrJson = b('[[{"x": [1, 2]}], 42]');
  final rArr = JsonTokenReader.fromBytes(arrJson);
  rArr.beginArray();
  rArr.skipValue(); // skips '[{"x": [1, 2]}]'
  Expect.isTrue(rArr.hasNext());
  Expect.equals(42, rArr.readInt());
  rArr.endArray();
}

void testContainerDelimiterSpans() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Single-byte delimiter spans for unspaced and spaced containers
  final unspacedObj = b('{"a":1}');
  final r1 = JsonTokenReader.fromBytes(unspacedObj);
  final (s1, e1) = r1.getTokenSpan();
  Expect.equals(0, s1);
  Expect.equals(1, e1);
  Expect.equals('{', utf8.decode(unspacedObj.sublist(s1, e1)));

  r1.beginObject();
  Expect.equals('a', r1.nextName());
  Expect.equals(1, r1.readInt());
  final (s1Close, e1Close) = r1.getTokenSpan();
  Expect.equals(6, s1Close);
  Expect.equals(7, e1Close);
  Expect.equals('}', utf8.decode(unspacedObj.sublist(s1Close, e1Close)));
  r1.endObject();

  final spacedObj = b('  {  "a"  :  1  }  ');
  final r2 = JsonTokenReader.fromBytes(spacedObj);
  final (s2, e2) = r2.getTokenSpan();
  Expect.equals(2, s2);
  Expect.equals(3, e2);
  Expect.equals('{', utf8.decode(spacedObj.sublist(s2, e2)));

  final unspacedArr = b('[1,2]');
  final r3 = JsonTokenReader.fromBytes(unspacedArr);
  final (s3, e3) = r3.getTokenSpan();
  Expect.equals(0, s3);
  Expect.equals(1, e3);
  Expect.equals('[', utf8.decode(unspacedArr.sublist(s3, e3)));

  r3.beginArray();
  Expect.equals(1, r3.readInt());
  Expect.equals(2, r3.readInt());
  final (s3Close, e3Close) = r3.getTokenSpan();
  Expect.equals(4, s3Close);
  Expect.equals(5, e3Close);
  Expect.equals(']', utf8.decode(unspacedArr.sublist(s3Close, e3Close)));
  r3.endArray();
}

void testPeekMissingCommaError() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // In an object, after reading a value, next must be comma or '}'.
  // If followed directly by another key without comma, peek() must return none.
  final rObj = JsonTokenReader.fromBytes(b('{"a": 1 "b": 2}'));
  rObj.beginObject();
  Expect.equals('a', rObj.nextName());
  Expect.equals(1, rObj.readInt());
  Expect.equals(JsonTokenType.none, rObj.peek());

  // In an array, after reading a value, next must be comma or ']'.
  // If followed directly by another element without comma, peek() must return none.
  final rArr = JsonTokenReader.fromBytes(b('[1 2]'));
  rArr.beginArray();
  Expect.equals(1, rArr.readInt());
  Expect.equals(JsonTokenType.none, rArr.peek());
}

void testWriteNameBytesPreQuoted() {
  // Pre-quoted key constant (Pattern B: utf8.encode('"x"'))
  final sink1 = BytesBuilder();
  final w1 = JsonTokenWriter.toSink(sink1);
  w1.beginObject();
  w1.writeNameBytes(Uint8List.fromList(utf8.encode('"key"')));
  w1.writeInt(42);
  w1.endObject();
  final out1 = utf8.decode(sink1.takeBytes());
  Expect.equals('{"key":42}', out1);

  // Raw unquoted key constant
  final sink2 = BytesBuilder();
  final w2 = JsonTokenWriter.toSink(sink2);
  w2.beginObject();
  w2.writeNameBytes(Uint8List.fromList(utf8.encode('key')));
  w2.writeInt(42);
  w2.endObject();
  final out2 = utf8.decode(sink2.takeBytes());
  Expect.equals('{"key":42}', out2);
}

void testSkipValueMaxDepthLimit() {
  // 65 levels of nested array
  final open = '[' * 65;
  final close = ']' * 65;
  final deepArray = Uint8List.fromList(utf8.encode('$open$close'));
  final r = JsonTokenReader.fromBytes(deepArray);
  Expect.throwsFormatException(() => r.skipValue());

  // 64 levels of nested array should succeed
  final okOpen = '[' * 64;
  final okClose = ']' * 64;
  final okArray = Uint8List.fromList(utf8.encode('$okOpen$okClose'));
  final rOk = JsonTokenReader.fromBytes(okArray);
  rOk.skipValue();

  // Mixed containers at depth 64: 32 objects containing arrays
  var mixed64 = '';
  for (var i = 0; i < 32; i++) {
    mixed64 += '{"k":[';
  }
  mixed64 += '42';
  for (var i = 0; i < 32; i++) {
    mixed64 += ']}';
  }
  final rMixed = JsonTokenReader.fromBytes(
    Uint8List.fromList(utf8.encode(mixed64)),
  );
  rMixed.skipValue();

  // Mixed containers at depth 65: exceeds limit
  var mixed65 = '';
  for (var i = 0; i < 32; i++) {
    mixed65 += '{"k":[';
  }
  mixed65 += '{"k": 42}';
  for (var i = 0; i < 32; i++) {
    mixed65 += ']}';
  }
  final rMixed65 = JsonTokenReader.fromBytes(
    Uint8List.fromList(utf8.encode(mixed65)),
  );
  Expect.throwsFormatException(() => rMixed65.skipValue());
}

void testSelectNameEscapedKeys() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final options = JsonKeyOptions.of(['id', 'title', 'active', r'a"b', r'c\d']);
  final reader = JsonTokenReader.fromBytes(
    b(
      r'{"\u0069\u0064": 42, "\u0074\u0069\u0074\u006c\u0065": "Dart 4", "active": true, "unknown_\u0031": 99, "a\"b": 100, "c\\d": 200}',
    ),
  );

  reader.beginObject();

  // "\u0069\u0064" -> matches 'id' (index 0)
  Expect.equals(0, reader.selectName(options));
  Expect.equals(42, reader.readInt());

  // "\u0074\u0069\u0074\u006c\u0065" -> matches 'title' (index 1)
  Expect.equals(1, reader.selectName(options));
  Expect.equals('Dart 4', reader.readString());

  // "active" -> verbatim ASCII match (index 2)
  Expect.equals(2, reader.selectName(options));
  Expect.isTrue(reader.readBool());

  // "unknown_\u0031" -> unknown key -> returns -1
  Expect.equals(-1, reader.selectName(options));
  reader.skipValue();

  // "a\"b" -> escaped quote -> index 3
  Expect.equals(3, reader.selectName(options));
  Expect.equals(100, reader.readInt());

  // "c\\d" -> escaped backslash -> index 4
  Expect.equals(4, reader.selectName(options));
  Expect.equals(200, reader.readInt());

  Expect.isFalse(reader.hasNext());
  reader.endObject();
}

void testSelectStringEscapedEnums() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final roleOptions = JsonKeyOptions.of(['admin', 'user', 'guest']);
  final reader = JsonTokenReader.fromBytes(
    b(
      r'["\u0061\u0064\u006d\u0069\u006e", "user", "\u0067\u0075\u0065\u0073\u0074", "\u006f\u0074\u0068\u0065\u0072"]',
    ),
  );

  reader.beginArray();

  // "\u0061\u0064\u006d\u0069\u006e" -> matches 'admin' (index 0)
  Expect.equals(0, reader.selectString(roleOptions));

  // "user" -> matches 'user' (index 1)
  Expect.equals(1, reader.selectString(roleOptions));

  // "\u0067\u0075\u0065\u0073\u0074" -> matches 'guest' (index 2)
  Expect.equals(2, reader.selectString(roleOptions));

  // "\u006f\u0074\u0068\u0065\u0072" -> "other" -> unmatched enum -> returns -1
  Expect.equals(-1, reader.selectString(roleOptions));

  Expect.isFalse(reader.hasNext());
  reader.endArray();
}

void testTokenReaderCursorRollbackOnFormatException() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Test rollback in object value on readInt
  {
    final reader = JsonTokenReader.fromBytes(
      b('{"key": "not_an_int", "other": 123}'),
    );
    reader.beginObject();
    Expect.equals('key', reader.nextName());

    // Expect FormatException when reading int on string literal
    Expect.throwsFormatException(() => reader.readInt());

    // After caught FormatException, cursor and container state must be preserved
    final (start, end) = reader.getTokenSpan();
    Expect.equals(
      'not_an_int',
      utf8.decode(b('{"key": "not_an_int", "other": 123}').sublist(start, end)),
    );
    Expect.equals('not_an_int', reader.readString());

    Expect.isTrue(reader.hasNext());
    Expect.equals('other', reader.nextName());
    Expect.equals(123, reader.readInt());
    Expect.isFalse(reader.hasNext());
    reader.endObject();
  }

  // Test rollback on readDouble, readBool, readNull in array
  {
    final raw = '[10, "abc", true, null, 30]';
    final bytes = b(raw);
    final reader = JsonTokenReader.fromBytes(bytes);
    reader.beginArray();
    Expect.equals(10, reader.readInt());

    // Attempt to read double on "abc" (throws FormatException)
    Expect.throwsFormatException(() => reader.readDouble());
    final (start1, end1) = reader.getTokenSpan();
    Expect.equals('abc', utf8.decode(bytes.sublist(start1, end1)));
    Expect.equals('abc', reader.readString());

    // Next element is `true`, attempt to readNull (throws FormatException)
    Expect.throwsFormatException(() => reader.readNull());
    final (start2, end2) = reader.getTokenSpan();
    Expect.equals('true', utf8.decode(bytes.sublist(start2, end2)));
    Expect.isTrue(reader.readBool());

    // Next element is `null`, attempt to readBool (throws FormatException)
    Expect.throwsFormatException(() => reader.readBool());
    final (start3, end3) = reader.getTokenSpan();
    Expect.equals('null', utf8.decode(bytes.sublist(start3, end3)));
    reader.readNull();

    // Next element in array
    Expect.isTrue(reader.hasNext());
    Expect.equals(30, reader.readInt());
    Expect.isFalse(reader.hasNext());
    reader.endArray();
  }
}

void testAllowMalformedUtf8() {
  // Invalid UTF-8 bytes: [0x22, 0xFF, 0xFE, 0x22] -> "\xFF\xFE" in string quotes
  final malformedBytes = Uint8List.fromList([0x22, 0xFF, 0xFE, 0x22]);

  // Default decoder (allowMalformed: false) throws FormatException
  Expect.throwsFormatException(() => jsonUtf8Decode(malformedBytes));
  Expect.throwsFormatException(
    () => JsonTokenReader.fromBytes(malformedBytes).readString(),
  );

  // allowMalformed: true replaces invalid bytes with \uFFFD
  final decoded = jsonUtf8Decode(malformedBytes, allowMalformed: true);
  Expect.equals('\uFFFD\uFFFD', decoded);

  final reader = JsonTokenReader.fromBytes(
    malformedBytes,
    allowMalformed: true,
  );
  Expect.equals('\uFFFD\uFFFD', reader.readString());
}

void testSelectNameSurrogatePairsAndNonAscii() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final options = JsonKeyOptions.of(['😀', 'é', 'café', 'regular']);
  // 1. Escaped surrogate pair: \uD83D\uDE00 -> 😀
  // 2. Escaped non-ASCII: \u00e9 -> é
  // 3. Raw non-ASCII UTF-8: café
  // 4. Verbatim ASCII: regular
  final reader = JsonTokenReader.fromBytes(
    b(r'{"\uD83D\uDE00": 1, "\u00e9": 2, "café": 3, "regular": 4}'),
  );

  reader.beginObject();

  Expect.equals(0, reader.selectName(options));
  Expect.equals(1, reader.readInt());

  Expect.equals(1, reader.selectName(options));
  Expect.equals(2, reader.readInt());

  Expect.equals(2, reader.selectName(options));
  Expect.equals(3, reader.readInt());

  Expect.equals(3, reader.selectName(options));
  Expect.equals(4, reader.readInt());

  Expect.isFalse(reader.hasNext());
  reader.endObject();
}

void testNextNameAndReadStringRollback() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // 1. Calling nextName when expecting value throws FormatException and rolls back
  {
    final reader = JsonTokenReader.fromBytes(b('{"a": 100}'));
    reader.beginObject();
    Expect.equals('a', reader.nextName());

    // Mistakenly call nextName again instead of reading value
    Expect.throwsFormatException(() => reader.nextName());

    // Reader state preserved: readInt succeeds
    Expect.equals(100, reader.readInt());
    Expect.isFalse(reader.hasNext());
    reader.endObject();
  }

  // 2. Calling readString on numeric token throws FormatException and rolls back
  {
    final reader = JsonTokenReader.fromBytes(b('[123, "abc"]'));
    reader.beginArray();

    Expect.throwsFormatException(() => reader.readString());

    // Reader state preserved: readInt succeeds
    Expect.equals(123, reader.readInt());

    Expect.isTrue(reader.hasNext());
    Expect.equals('abc', reader.readString());
    Expect.isFalse(reader.hasNext());
    reader.endArray();
  }
}

void testAllowMalformedUtf8WithEscapes() {
  // String containing both invalid UTF-8 bytes and unicode escape:
  // bytes: '"' + [0xFF, 0xFE] + '\u0061' + '"'
  final bytes = Uint8List.fromList([
    0x22,
    0xFF,
    0xFE,
    0x5C,
    0x75,
    0x30,
    0x30,
    0x36,
    0x31,
    0x22,
  ]);

  // allowMalformed: false throws FormatException
  Expect.throwsFormatException(() => jsonUtf8Decode(bytes));
  Expect.throwsFormatException(
    () => JsonTokenReader.fromBytes(bytes).readString(),
  );

  // allowMalformed: true replaces malformed bytes with \uFFFD and decodes escape
  final decoded = jsonUtf8Decode(bytes, allowMalformed: true);
  Expect.equals('\uFFFD\uFFFDa', decoded);

  final reader = JsonTokenReader.fromBytes(bytes, allowMalformed: true);
  Expect.equals('\uFFFD\uFFFDa', reader.readString());
}

void testTrailingCommaPeekRejection() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Trailing comma before '}' in object: peek() must return none
  {
    final r = JsonTokenReader.fromBytes(b('{"a": 1, }'));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.equals(1, r.readInt());
    Expect.equals(JsonTokenType.none, r.peek());
  }

  // Trailing comma with multiple properties
  {
    final r = JsonTokenReader.fromBytes(b('{"a": 1, "b": 2, }'));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.equals(1, r.readInt());
    Expect.equals('b', r.nextName());
    Expect.equals(2, r.readInt());
    Expect.equals(JsonTokenType.none, r.peek());
  }

  // Trailing comma before ']' in array: peek() must return none
  {
    final r = JsonTokenReader.fromBytes(b('[1, 2, ]'));
    r.beginArray();
    Expect.equals(1, r.readInt());
    Expect.equals(2, r.readInt());
    Expect.equals(JsonTokenType.none, r.peek());
  }

  // Single-element array with trailing comma
  {
    final r = JsonTokenReader.fromBytes(b('[true, ]'));
    r.beginArray();
    Expect.equals(true, r.readBool());
    Expect.equals(JsonTokenType.none, r.peek());
  }

  // Mismatched closing delimiter after comma in array: peek() must return none
  {
    final r = JsonTokenReader.fromBytes(b('[1, }'));
    r.beginArray();
    Expect.equals(1, r.readInt());
    Expect.equals(JsonTokenType.none, r.peek());
  }

  // Mismatched closing delimiter after comma in object: peek() must return none
  {
    final r = JsonTokenReader.fromBytes(b('{"a": 1, ]'));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.equals(1, r.readInt());
    Expect.equals(JsonTokenType.none, r.peek());
  }

  // Invalid value (non-string key) after comma in object: peek() must return none
  {
    final r = JsonTokenReader.fromBytes(b('{"a": 1, 2}'));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.equals(1, r.readInt());
    Expect.equals(JsonTokenType.none, r.peek());
  }

  // Invalid value (non-string key) at start of object: peek() must return none
  {
    final r = JsonTokenReader.fromBytes(b('{123}'));
    r.beginObject();
    Expect.equals(JsonTokenType.none, r.peek());
  }

  // Bare closing brackets or delimiters at root level: peek() must return none
  {
    Expect.equals(JsonTokenType.none, JsonTokenReader.fromBytes(b('}')).peek());
    Expect.equals(JsonTokenType.none, JsonTokenReader.fromBytes(b(']')).peek());
    Expect.equals(JsonTokenType.none, JsonTokenReader.fromBytes(b(',')).peek());
    Expect.equals(JsonTokenType.none, JsonTokenReader.fromBytes(b(':')).peek());
  }

  // hasNext() throws FormatException on mismatched delimiter after comma
  {
    final rArr = JsonTokenReader.fromBytes(b('[1, }'));
    rArr.beginArray();
    Expect.equals(1, rArr.readInt());
    Expect.throwsFormatException(() => rArr.hasNext());

    final rObj = JsonTokenReader.fromBytes(b('{"a": 1, ]'));
    rObj.beginObject();
    Expect.equals('a', rObj.nextName());
    Expect.equals(1, rObj.readInt());
    Expect.throwsFormatException(() => rObj.hasNext());
  }
}

void testTokenReaderMultipleRoots() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Disallow multiple primitive root values
  {
    final r1 = JsonTokenReader.fromBytes(b('1 2'));
    Expect.equals(1, r1.readInt());
    Expect.isFalse(r1.hasNext());
    Expect.equals(JsonTokenType.none, r1.peek());
    Expect.throwsFormatException(() => r1.readInt());
  }

  // Disallow root value after container
  {
    final r2 = JsonTokenReader.fromBytes(b('{"a": 1} 42'));
    r2.beginObject();
    Expect.equals('a', r2.nextName());
    Expect.equals(1, r2.readInt());
    r2.endObject();
    Expect.isFalse(r2.hasNext());
    Expect.equals(JsonTokenType.none, r2.peek());
    Expect.throwsFormatException(() => r2.readInt());
  }

  // Clean EOF after container: peek returns endOfDocument
  {
    final r = JsonTokenReader.fromBytes(b('{"a": 1}   '));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.equals(1, r.readInt());
    r.endObject();
    Expect.isFalse(r.hasNext());
    Expect.equals(JsonTokenType.endOfDocument, r.peek());
  }

  // Clean EOF after primitive: peek returns endOfDocument
  {
    final r = JsonTokenReader.fromBytes(b('100'));
    Expect.equals(100, r.readInt());
    Expect.isFalse(r.hasNext());
    Expect.equals(JsonTokenType.endOfDocument, r.peek());
  }

  // Disallow container after root value
  {
    final r3 = JsonTokenReader.fromBytes(b('"root" [1, 2]'));
    Expect.equals('root', r3.readString());
    Expect.isFalse(r3.hasNext());
    Expect.equals(JsonTokenType.none, r3.peek());
    Expect.throwsFormatException(() => r3.beginArray());
  }

  // Disallow container after container
  {
    final r4 = JsonTokenReader.fromBytes(b('{} {}'));
    r4.beginObject();
    r4.endObject();
    Expect.isFalse(r4.hasNext());
    Expect.equals(JsonTokenType.none, r4.peek());
    Expect.throwsFormatException(() => r4.beginObject());
  }

  // Disallow bool after bool
  {
    final r5 = JsonTokenReader.fromBytes(b('true false'));
    Expect.isTrue(r5.readBool());
    Expect.isFalse(r5.hasNext());
    Expect.equals(JsonTokenType.none, r5.peek());
    Expect.throwsFormatException(() => r5.readBool());
  }

  // Disallow null after null
  {
    final r6 = JsonTokenReader.fromBytes(b('null null'));
    r6.readNull();
    Expect.isFalse(r6.hasNext());
    Expect.equals(JsonTokenType.none, r6.peek());
    Expect.throwsFormatException(() => r6.readNull());
  }

  // Disallow skipValue after root value
  {
    final r7 = JsonTokenReader.fromBytes(b('[1, 2] 3'));
    r7.beginArray();
    Expect.equals(1, r7.readInt());
    Expect.equals(2, r7.readInt());
    r7.endArray();
    Expect.isFalse(r7.hasNext());
    Expect.equals(JsonTokenType.none, r7.peek());
    Expect.throwsFormatException(() => r7.skipValue());
  }

  // Disallow double reading after root double
  {
    final r8 = JsonTokenReader.fromBytes(b('0.123456789012345 3.14'));
    Expect.equals(0.123456789012345, r8.readDouble());
    Expect.isFalse(r8.hasNext());
    Expect.equals(JsonTokenType.none, r8.peek());
    Expect.throwsFormatException(() => r8.readDouble());
  }
}

void testTokenReaderSkipValueControlChars() {
  // Reject unescaped control char in nested string within skipValue
  {
    final bytes = Uint8List.fromList([
      123,
      0x22,
      0x61,
      0x22,
      58,
      0x22,
      0x0A,
      0x22,
      125, // {"a": "\n"} where \n is byte 0x0A
    ]);
    final r = JsonTokenReader.fromBytes(bytes);
    Expect.throwsFormatException(() => r.skipValue());
  }

  {
    final bytes = Uint8List.fromList([
      91, 0x22, 0x00, 0x22, 93, // ["\x00"]
    ]);
    final r = JsonTokenReader.fromBytes(bytes);
    Expect.throwsFormatException(() => r.skipValue());
  }
}
