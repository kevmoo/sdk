// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testTopLevelHelpers();
  testCodecProperties();
  testEncoderDecoderRoundtrips();
  testReviverAndToEncodable();
  testPrettyPrinting();
  testBitExactJsonCompatibility();
  testExactBufferCapacity();
  testReentrantSerialization();
}

void _expectDeepEquals(Object? expected, Object? actual) {
  if (expected is List && actual is List) {
    Expect.equals(expected.length, actual.length);
    for (var i = 0; i < expected.length; i++) {
      _expectDeepEquals(expected[i], actual[i]);
    }
  } else if (expected is Map && actual is Map) {
    Expect.equals(expected.length, actual.length);
    for (final key in expected.keys) {
      Expect.isTrue(actual.containsKey(key));
      _expectDeepEquals(expected[key], actual[key]);
    }
  } else {
    Expect.equals(expected, actual);
  }
}

void testTopLevelHelpers() {
  final data = {
    "id": 1,
    "name": "Dart 4",
    "tags": ["json", "utf8"],
    "active": true,
  };
  final encoded = jsonUtf8Encode(data);
  Expect.type<Uint8List>(encoded);

  final decoded = jsonUtf8Decode(encoded) as Map<String, dynamic>;
  Expect.equals(1, decoded['id']);
  Expect.equals('Dart 4', decoded['name']);
  Expect.equals(true, decoded['active']);
  Expect.listEquals(['json', 'utf8'], decoded['tags'] as List);
}

void testCodecProperties() {
  const codec = JsonUtf8Codec(indent: '  ', allowMalformed: true);
  Expect.equals('  ', codec.indent);
  Expect.isTrue(codec.allowMalformed);

  final enc = codec.encoder;
  final dec = codec.decoder;
  Expect.type<JsonUtf8Encoder>(enc);
  Expect.type<JsonUtf8Decoder>(dec);
  Expect.isTrue(dec.allowMalformed);
}

void testEncoderDecoderRoundtrips() {
  final cases = <Object?>[
    null,
    true,
    false,
    0,
    -1,
    42,
    123456789012345,
    3.14159,
    -0.5,
    "",
    "hello world",
    "special chars: \" \\ \n \r \t \b \f \u0000 \u001f",
    "unicode: 🚀 € 汉语 😀",
    <Object?>[],
    [1, 2, 3, "four", true, null],
    <String, Object?>{},
    {
      "int": 42,
      "double": 3.14,
      "string": "test",
      "bool": false,
      "null": null,
      "nested": {
        "list": [1, 2, 3],
      },
    },
  ];

  for (final item in cases) {
    final bytes = jsonUtf8.encode(item);
    final decoded = jsonUtf8.decode(bytes);
    _expectDeepEquals(item, decoded);
  }
}

class _CustomPoint {
  final int x;
  final int y;
  _CustomPoint(this.x, this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}

void testReviverAndToEncodable() {
  // toEncodable
  final point = _CustomPoint(10, 20);
  final codec = JsonUtf8Codec(
    toEncodable: (o) => (o as _CustomPoint).toJson(),
    reviver: (key, value) {
      if (key == 'x') return (value as int) * 2;
      return value;
    },
  );

  final bytes = codec.encode(point);
  final decoded = codec.decode(bytes) as Map<String, dynamic>;
  Expect.equals(20, decoded['x']); // 10 * 2 via reviver
  Expect.equals(20, decoded['y']);
}

void testPrettyPrinting() {
  final data = {
    'a': 1,
    'b': [2, 3],
  };
  final codec = JsonUtf8Codec(indent: '  ');
  final bytes = codec.encode(data);
  final str = utf8.decode(bytes);

  Expect.isTrue(str.contains('\n'));
  Expect.isTrue(str.contains('  "a": 1'));
  Expect.isTrue(str.contains('  "b": ['));
}

void testBitExactJsonCompatibility() {
  final complex = {
    "string": "The quick brown fox jumps over the lazy dog",
    "escapes": "\"quotes\" and \\backslashes\\ and \nnewlines",
    "unicode": "Dart 4.0 \u{1F680} is fast!",
    "integers": [0, -1, 1, 9223372036854775807, -9223372036854775808],
    "doubles": [0.0, 1.0, 3.141592653589793, 1e-15, 1e20],
    "booleans": [true, false],
    "nulls": [null, null],
    "nested": {
      "level1": {
        "level2": {
          "level3": ["deep", 42],
        },
      },
    },
  };

  final standardJson = jsonEncode(complex);
  final utf8Bytes = jsonUtf8Encode(complex);
  final jsonFromUtf8 = utf8.decode(utf8Bytes);

  // Decoded forms must be deeply equal
  final decoded1 = jsonDecode(standardJson) as Map;
  final decoded2 = jsonUtf8Decode(utf8Bytes) as Map;

  _expectDeepEquals(decoded1, decoded2);
}

void testExactBufferCapacity() {
  final cases = <Object?>[
    null,
    true,
    false,
    0,
    42,
    3.14,
    "",
    "hello",
    <Object?>[],
    [1, 2, 3],
    <String, Object?>{},
    {"a": 1},
    {"key": "value", "count": 100},
  ];

  for (final item in cases) {
    final encodedTopLevel = jsonUtf8Encode(item);
    Expect.equals(
      encodedTopLevel.length,
      encodedTopLevel.buffer.lengthInBytes,
      'jsonUtf8Encode buffer capacity mismatch for $item',
    );

    final encodedCodec = jsonUtf8.encode(item);
    Expect.equals(
      encodedCodec.length,
      (encodedCodec as Uint8List).buffer.lengthInBytes,
      'jsonUtf8.encode buffer capacity mismatch for $item',
    );

    final encodedEncoder = JsonUtf8Encoder().convert(item);
    Expect.equals(
      encodedEncoder.length,
      (encodedEncoder as Uint8List).buffer.lengthInBytes,
      'JsonUtf8Encoder.convert buffer capacity mismatch for $item',
    );

    final encodedIndented = JsonUtf8Encoder('  ').convert(item);
    Expect.equals(
      encodedIndented.length,
      (encodedIndented as Uint8List).buffer.lengthInBytes,
      'JsonUtf8Encoder(indent).convert buffer capacity mismatch for $item',
    );
  }

  // Large payload spanning multiple chunks (> 32 KB)
  final largeList = List.generate(5000, (i) => 'item_$i');
  final largeEncoded = jsonUtf8Encode(largeList);
  Expect.isTrue(largeEncoded.length > 32768);
  Expect.equals(
    largeEncoded.length,
    largeEncoded.buffer.lengthInBytes,
    'Large multi-chunk buffer capacity mismatch',
  );
}

class _ReentrantCustomObject {
  final double value;
  final String text;
  final _ReentrantCustomObject? child;
  _ReentrantCustomObject(this.value, this.text, [this.child]);

  Map<String, dynamic> toJson() {
    final b = BytesBuilder(copy: false);
    JsonUtf8Encoder.writeDouble(value, b);
    JsonUtf8Encoder.writeString(text, b);
    if (child != null) {
      final childJson = jsonUtf8Encode(child!.toJson());
      b.add(childJson);
    }
    return {'serialized': utf8.decode(b.takeBytes())};
  }
}

void testReentrantSerialization() {
  final obj = _ReentrantCustomObject(
    123.456,
    'nested',
    _ReentrantCustomObject(78.9, 'deep_child'),
  );
  final map = <String, dynamic>{
    'top_double': 99.5,
    'top_string': 'hello',
    'obj': obj,
  };
  final encoded = jsonUtf8Encode(map);
  final decoded = jsonUtf8Decode(encoded) as Map<String, dynamic>;
  Expect.equals(99.5, decoded['top_double']);
  Expect.equals('hello', decoded['top_string']);
  Expect.equals(
    '123.456"nested"{"serialized":"78.9\\"deep_child\\""}',
    (decoded['obj'] as Map)['serialized'],
  );
}
