// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testShortKeyLengths1Through8();
  testTailKeysNearBufferBoundary();
  testSlicedSublistViewBuffers();
  testMultiByteUtf8Keys();
  test8ByteUtf8KeyWithHighBit();
  test8BytePrefixCollisions();
  testEscapedKeys();
  testMultiPropertyModelOutOfOrderAndMissing();
  testSelectStringShortEnums();
  testMatchKeyDirectSpanParsing();
  testDuplicateKeysPreserveFirst();
  testEmptyKeyHandling();
}

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

void test8ByteUtf8KeyWithHighBit() {
  // 'abcdef' (6 bytes) + '\u00e9' (2 bytes [0xC3, 0xA9]) = exactly 8 UTF-8 bytes!
  // Byte 7 is 0xA9 (bit 7 set = 1).
  // '12345' (5 bytes) + '\u4e2d' (3 bytes [0xE4, 0xB8, 0xAD]) = exactly 8 UTF-8 bytes!
  // Byte 7 is 0xAD (bit 7 set = 1).
  final key1 = 'abcdef\u00e9';
  final key2 = '12345\u4e2d';
  Expect.equals(8, utf8.encode(key1).length);
  Expect.equals(8, utf8.encode(key2).length);

  final options = JsonKeyOptions.of([key1, key2, 'regular8']);
  final jsonStr = '{"abcdef\\u00e9": 100, "12345中": 200, "regular8": 300}';
  final reader = JsonTokenReader.fromBytes(_b(jsonStr));

  reader.beginObject();
  Expect.equals(0, reader.selectName(options));
  Expect.equals(100, reader.readInt());

  Expect.equals(1, reader.selectName(options));
  Expect.equals(200, reader.readInt());

  Expect.equals(2, reader.selectName(options));
  Expect.equals(300, reader.readInt());
  reader.endObject();
}

void test8BytePrefixCollisions() {
  // Test collisions where one key is 8 bytes and another is 9+ bytes sharing same 8-byte prefix
  final options = JsonKeyOptions.of([
    'venueCod', // 8 bytes
    'venueCode', // 9 bytes
    'latitude', // 8 bytes
    'latitudes', // 9 bytes
  ]);

  final jsonStr =
      '{"venueCode": 1, "venueCod": 2, "latitudes": 3, "latitude": 4}';
  final reader = JsonTokenReader.fromBytes(_b(jsonStr));

  reader.beginObject();
  Expect.equals(1, reader.selectName(options));
  Expect.equals(1, reader.readInt());

  Expect.equals(0, reader.selectName(options));
  Expect.equals(2, reader.readInt());

  Expect.equals(3, reader.selectName(options));
  Expect.equals(3, reader.readInt());

  Expect.equals(2, reader.selectName(options));
  Expect.equals(4, reader.readInt());
  reader.endObject();
}

void testShortKeyLengths1Through8() {
  final keys = [
    'a', // 1 byte
    'id', // 2 bytes
    'lat', // 3 bytes
    'type', // 4 bytes
    'topic', // 5 bytes
    'blocks', // 6 bytes
    'eventId', // 7 bytes
    'venueCod', // 8 bytes
    'description', // 11 bytes (> 8 bytes)
  ];

  final options = JsonKeyOptions.of(keys);
  Expect.equals(9, options.length);

  for (var i = 0; i < keys.length; i++) {
    final jsonStr = '{"${keys[i]}": 12345}';
    final reader = JsonTokenReader.fromBytes(_b(jsonStr));
    reader.beginObject();
    Expect.isTrue(reader.hasNext());
    final idx = reader.selectName(options);
    Expect.equals(i, idx);
    Expect.equals(12345, reader.readInt());
    Expect.isFalse(reader.hasNext());
    reader.endObject();
  }

  // Test non-matching short key
  final reader = JsonTokenReader.fromBytes(_b('{"foo": 1}'));
  reader.beginObject();
  Expect.equals(-1, reader.selectName(options));
  reader.skipValue();
  reader.endObject();
}

void testTailKeysNearBufferBoundary() {
  // Test tail keys located at the very end of the JSON buffer where start + 8 > buffer.length
  final tailPayloads = <String, (String, int)>{
    '{"a":1}': ('a', 0), // len = 7, key 'a' at idx 2, start+8=10 > 7
    '{"id":0}': ('id', 1), // len = 8, key 'id' at idx 2, start+8=10 > 8
    '{"lat":9}': ('lat', 2), // len = 9, key 'lat' at idx 2, start+8=10 > 9
    '{"type":1}': (
      'type',
      3,
    ), // len = 10, key 'type' at idx 2, start+8=10 == 10
  };

  final options = JsonKeyOptions.of(['a', 'id', 'lat', 'type']);

  for (final entry in tailPayloads.entries) {
    final bytes = _b(entry.key);
    final reader = JsonTokenReader.fromBytes(bytes);
    reader.beginObject();
    Expect.isTrue(reader.hasNext());
    final idx = reader.selectName(options);
    Expect.equals(entry.value.$2, idx);
    Expect.isTrue(reader.readInt() >= 0);
    Expect.isFalse(reader.hasNext());
    reader.endObject();
  }
}

void testSlicedSublistViewBuffers() {
  // Create a parent buffer with non-zero offset
  final prefix = List.filled(128, 0xAA);
  final jsonBytes = utf8.encode('{"eventId": 42, "id": 100}');
  final suffix = List.filled(128, 0xBB);
  final fullList = <int>[...prefix, ...jsonBytes, ...suffix];
  final parentUint8 = Uint8List.fromList(fullList);

  final sliced = Uint8List.sublistView(
    parentUint8,
    128,
    128 + jsonBytes.length,
  );
  Expect.equals(128, sliced.offsetInBytes);
  Expect.equals(jsonBytes.length, sliced.length);

  final options = JsonKeyOptions.of(['id', 'eventId']);
  final reader = JsonTokenReader.fromBytes(sliced);

  reader.beginObject();
  Expect.isTrue(reader.hasNext());
  Expect.equals(1, reader.selectName(options)); // eventId
  Expect.equals(42, reader.readInt());

  Expect.isTrue(reader.hasNext());
  Expect.equals(0, reader.selectName(options)); // id
  Expect.equals(100, reader.readInt());

  Expect.isFalse(reader.hasNext());
  reader.endObject();
}

void testMultiByteUtf8Keys() {
  // Chinese characters: each is 3 UTF-8 bytes.
  // "用户" is 2 UTF-16 code units, but 6 UTF-8 bytes (<= 8 bytes SWAR candidate!)
  // "用户数据" is 4 UTF-16 code units, but 12 UTF-8 bytes (> 8 bytes)
  // Emoji "🎯" is 4 UTF-8 bytes (<= 8 bytes)
  final keys = ['用户', '用户数据', '🎯', 'latin'];
  final options = JsonKeyOptions.of(keys);

  final jsonStr = '{"用户": 1, "🎯": 2, "用户数据": 3, "latin": 4}';
  final reader = JsonTokenReader.fromBytes(_b(jsonStr));

  reader.beginObject();
  Expect.equals(0, reader.selectName(options));
  Expect.equals(1, reader.readInt());

  Expect.equals(2, reader.selectName(options));
  Expect.equals(2, reader.readInt());

  Expect.equals(1, reader.selectName(options));
  Expect.equals(3, reader.readInt());

  Expect.equals(3, reader.selectName(options));
  Expect.equals(4, reader.readInt());

  reader.endObject();
}

void testEscapedKeys() {
  final options = JsonKeyOptions.of(['id', 'name', 'quoted"key']);

  // Escaped ASCII: "\u0069\u0064" -> "id", "\"quoted\\\"key\""
  final jsonStr = '{"\\u0069\\u0064": 99, "quoted\\"key": 100}';
  final reader = JsonTokenReader.fromBytes(_b(jsonStr));

  reader.beginObject();
  Expect.equals(
    0,
    reader.selectName(options),
  ); // unescaped \u0069\u0064 == 'id'
  Expect.equals(99, reader.readInt());

  Expect.equals(2, reader.selectName(options)); // unescaped quoted"key
  Expect.equals(100, reader.readInt());

  reader.endObject();
}

void testMultiPropertyModelOutOfOrderAndMissing() {
  final options = JsonKeyOptions.of([
    'id',
    'name',
    'lat',
    'lon',
    'active',
    'topicIds',
    'extra',
  ]);

  final jsonStr = '''{
    "lat": 37.7749,
    "extra": "ignored",
    "id": 101,
    "active": true
  }''';

  final reader = JsonTokenReader.fromBytes(_b(jsonStr));
  int? id;
  double? lat;
  bool? active;

  reader.beginObject();
  while (reader.hasNext()) {
    switch (reader.selectName(options)) {
      case 0:
        id = reader.readInt();
        break;
      case 2:
        lat = reader.readDouble();
        break;
      case 4:
        active = reader.readBool();
        break;
      default:
        reader.skipValue();
        break;
    }
  }
  reader.endObject();

  Expect.equals(101, id);
  Expect.equals(37.7749, lat);
  Expect.equals(true, active);
}

void testSelectStringShortEnums() {
  final roleOptions = JsonKeyOptions.of([
    'admin',
    'user',
    'moderator',
    'guest',
  ]);

  final jsonStr = '["admin", "guest", "user", "other", "moderator"]';
  final reader = JsonTokenReader.fromBytes(_b(jsonStr));

  reader.beginArray();
  Expect.equals(0, reader.selectString(roleOptions));
  Expect.equals(3, reader.selectString(roleOptions));
  Expect.equals(1, reader.selectString(roleOptions));
  Expect.equals(-1, reader.selectString(roleOptions)); // 'other'
  Expect.equals(2, reader.selectString(roleOptions));
  reader.endArray();
}

void testMatchKeyDirectSpanParsing() {
  final options = JsonKeyOptions.of(['id', 'latitude', 'longitude', 'name']);
  final bytes = _b('"latitude": 100, "id": 200');

  // Span [1, 9) is 'latitude' (8 bytes)
  Expect.equals(1, JsonUtf8Decoder.matchKey(bytes, 1, 9, options));

  // Span [18, 20) is 'id' (2 bytes)
  Expect.equals(0, JsonUtf8Decoder.matchKey(bytes, 18, 20, options));

  // Unknown span
  Expect.equals(-1, JsonUtf8Decoder.matchKey(bytes, 0, 5, options));
}

void testDuplicateKeysPreserveFirst() {
  final options = JsonKeyOptions.of(['id', 'name', 'id']);
  Expect.equals(3, options.length);

  final jsonStr = '{"id": 42}';
  final reader = JsonTokenReader.fromBytes(_b(jsonStr));
  reader.beginObject();
  Expect.equals(
    0,
    reader.selectName(options),
  ); // First 'id' index (0) preserved
  Expect.equals(42, reader.readInt());
  reader.endObject();
}

void testEmptyKeyHandling() {
  final options = JsonKeyOptions.of(['', 'id', 'name']);
  final jsonStr = '{"": 10, "id": 20}';
  final reader = JsonTokenReader.fromBytes(_b(jsonStr));

  reader.beginObject();
  Expect.equals(0, reader.selectName(options)); // Empty key index 0
  Expect.equals(10, reader.readInt());

  Expect.equals(1, reader.selectName(options));
  Expect.equals(20, reader.readInt());
  reader.endObject();
}
