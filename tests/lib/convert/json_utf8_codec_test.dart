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
  testChunkedDecoderAllowMalformed();
  testCodecDecodeEncodeNamedParameters();
  testCanonicalLargeIntegers();
  testSplitChunkNetworkStreaming();
  testFusedCodecs();
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

void testChunkedDecoderAllowMalformed() {
  // 1. allowMalformed: true should replace invalid UTF-8 bytes with U+FFFD
  final malformedBytes = [0x22, 0x80, 0x22]; // '"\x80"'
  Object? result;
  final sinkTrue = JsonUtf8Decoder(null, true).startChunkedConversion(
    ChunkedConversionSink.withCallback((List<Object?> values) {
      result = values[0];
    }),
  );
  sinkTrue.add(malformedBytes);
  sinkTrue.close();
  Expect.equals('\uFFFD', result);

  // 2. allowMalformed: false should throw FormatException on invalid UTF-8 bytes
  final sinkFalse = JsonUtf8Decoder(null, false).startChunkedConversion(
    ChunkedConversionSink.withCallback((List<Object?> values) {
      result = values[0];
    }),
  );
  Expect.throwsFormatException(() {
    sinkFalse.add(malformedBytes);
    sinkFalse.close();
  });
}

void testCodecDecodeEncodeNamedParameters() {
  // 1. jsonUtf8.decode with reviver
  final bytes = Uint8List.fromList(utf8.encode('{"a": 10, "b": 20}'));
  final resReviver = jsonUtf8.decode(
    bytes,
    reviver: (key, value) {
      if (key == 'a') return (value as int) * 3;
      return value;
    },
  ) as Map<String, dynamic>;
  Expect.equals(30, resReviver['a']);
  Expect.equals(20, resReviver['b']);

  // 2. jsonUtf8.decode with allowMalformed: true / false
  final malformedBytes = Uint8List.fromList([0x22, 0x80, 0x22]); // '"\x80"'
  final resMalformed = jsonUtf8.decode(malformedBytes, allowMalformed: true);
  Expect.equals('\uFFFD', resMalformed);

  Expect.throwsFormatException(() {
    jsonUtf8.decode(malformedBytes, allowMalformed: false);
  });

  // 3. JsonUtf8Codec instance configuration overrides
  const strictCodec = JsonUtf8Codec(allowMalformed: false);
  final resStrictOverridden = strictCodec.decode(
    malformedBytes,
    allowMalformed: true,
  );
  Expect.equals('\uFFFD', resStrictOverridden);

  const lenientCodec = JsonUtf8Codec(allowMalformed: true);
  Expect.throwsFormatException(() {
    lenientCodec.decode(malformedBytes, allowMalformed: false);
  });

  // 4. jsonUtf8.encode with toEncodable
  final pt = _CustomPoint(5, 15);
  final Uint8List encRes = jsonUtf8.encode(
    pt,
    toEncodable: (o) => {'px': (o as _CustomPoint).x, 'py': o.y},
  );
  final decRes = jsonUtf8.decode(encRes) as Map<String, dynamic>;
  Expect.equals(5, decRes['px']);
  Expect.equals(15, decRes['py']);

  // 5. JsonUtf8Codec instance configuration overrides for toEncodable
  final codecWithEnc = JsonUtf8Codec(toEncodable: (o) => {'default': true});
  final Uint8List encOverride = codecWithEnc.encode(
    pt,
    toEncodable: (o) => {'overridden': true},
  );
  final decOverride = jsonUtf8.decode(encOverride) as Map<String, dynamic>;
  Expect.equals(true, decOverride['overridden']);
  Expect.isNull(decOverride['default']);

  // 6. JsonUtf8Codec instance reviver preservation when allowMalformed is overridden
  final codecWithRev = JsonUtf8Codec(
    reviver: (key, value) {
      if (key == 'tag') return 'revived_$value';
      return value;
    },
    allowMalformed: false,
  );

  final malformedWithTag = Uint8List.fromList([
    ...utf8.encode('{"tag":"val","bad":'),
    0x22,
    0x80,
    0x22, // '"\x80"'
    0x7D, // '}'
  ]);

  final resRevWithMalformed = codecWithRev.decode(
    malformedWithTag,
    allowMalformed: true,
  ) as Map<String, dynamic>;
  Expect.equals('revived_val', resRevWithMalformed['tag']);
  Expect.equals('\uFFFD', resRevWithMalformed['bad']);

  // Override reviver on instance that already has a reviver
  final resOverriddenRev = codecWithRev.decode(
    malformedWithTag,
    reviver: (k, v) => k == 'tag' ? 'override_$v' : v,
    allowMalformed: true,
  ) as Map<String, dynamic>;
  Expect.equals('override_val', resOverriddenRev['tag']);
  Expect.equals('\uFFFD', resOverriddenRev['bad']);

  // 7. Indent preservation when encoding with toEncodable
  const prettyCodec = JsonUtf8Codec(indent: '  ');
  final Uint8List encPretty = prettyCodec.encode(
    pt,
    toEncodable: (o) => {'px': (o as _CustomPoint).x},
  );
  final prettyString = utf8.decode(encPretty);
  Expect.isTrue(prettyString.contains('{\n  "px": 5\n}'));

  // 8. Return type guarantee (Uint8List)
  final Uint8List encodedDefault = jsonUtf8.encode({'x': 1});
  Expect.type<Uint8List>(encodedDefault);
}

void testCanonicalLargeIntegers() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // 1. Positive 64-bit integer overflow (2^63 = 9223372036854775808)
  final posStr = "9223372036854775808";
  final posBytes = b(posStr);

  // jsonUtf8Decode returns 9223372036854775808.0 (double) matching jsonDecode
  final posDecoded = jsonUtf8Decode(posBytes);
  Expect.type<double>(posDecoded);
  Expect.equals(9223372036854775808.0, posDecoded);
  Expect.equals(jsonDecode(posStr), posDecoded);

  // jsonUtf8.decode returns 9223372036854775808.0 (double)
  final posCodecDecoded = jsonUtf8.decode(posBytes);
  Expect.type<double>(posCodecDecoded);
  Expect.equals(9223372036854775808.0, posCodecDecoded);

  // JsonUtf8Decoder.parseInt throws FormatException on overflow
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseInt(posBytes, 0, posBytes.length),
  );

  // 2. Negative 64-bit integer overflow (-2^63 - 1 = -9223372036854775809)
  final negStr = "-9223372036854775809";
  final negBytes = b(negStr);

  final negDecoded = jsonUtf8Decode(negBytes);
  Expect.type<double>(negDecoded);
  Expect.equals(-9223372036854775809.0, negDecoded);
  Expect.equals(jsonDecode(negStr), negDecoded);

  final negCodecDecoded = jsonUtf8.decode(negBytes);
  Expect.type<double>(negCodecDecoded);
  Expect.equals(-9223372036854775809.0, negCodecDecoded);

  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseInt(negBytes, 0, negBytes.length),
  );

  // 3. Exact boundary cases from json_test.dart
  final boundaryCases = <String, Object?>{
    "9223372036854774784": 9223372036854774784,
    "-9223372036854775808": -9223372036854775808,
    "9223372036854775808": 9223372036854775808.0,
    "-9223372036854775809": -9223372036854775809.0,
    "9223372036854775808.0": 9223372036854775808.0,
    "9223372036854775810": 9223372036854775810.0,
    "18446744073709551616.0": 18446744073709551616.0,
  };

  for (final entry in boundaryCases.entries) {
    final bytes = b(entry.key);
    final expected = entry.value;
    final actual = jsonUtf8Decode(bytes);
    if (expected is double) {
      Expect.type<double>(actual);
    } else if (expected is int) {
      Expect.type<int>(actual);
    }
    Expect.equals(expected, actual);
    Expect.equals(jsonDecode(entry.key), actual);
  }

  // 4. Arrays of large integers
  final listJson =
      "[9223372036854774784, -9223372036854775808, 9223372036854775808, -9223372036854775809]";
  final listBytes = b(listJson);
  final listDecoded = jsonUtf8Decode(listBytes) as List<dynamic>;
  Expect.equals(9223372036854774784, listDecoded[0]);
  Expect.type<int>(listDecoded[0]);
  Expect.equals(-9223372036854775808, listDecoded[1]);
  Expect.type<int>(listDecoded[1]);
  Expect.equals(9223372036854775808.0, listDecoded[2]);
  Expect.type<double>(listDecoded[2]);
  Expect.equals(-9223372036854775809.0, listDecoded[3]);
  Expect.type<double>(listDecoded[3]);
}

void testSplitChunkNetworkStreaming() {
  // Helper to parse input byte-by-byte into a ChunkedConversionSink
  dynamic parse1ByteChunks(
    List<int> bytes, {
    bool allowMalformed = false,
    Object? Function(Object? key, Object? value)? reviver,
  }) {
    Object? result;
    var received = false;
    final sink = JsonUtf8Decoder(reviver, allowMalformed)
        .startChunkedConversion(
          ChunkedConversionSink.withCallback((List<Object?> values) {
            result = values[0];
            received = true;
          }),
        );
    for (var b in bytes) {
      sink.add([b]);
    }
    sink.close();
    Expect.isTrue(received);
    return result;
  }

  // 1. Astral emojis and ZWJ sequences across 1-byte chunks
  // Grinning face: 😀 (4 bytes: 0xF0, 0x9F, 0x98, 0x80)
  // Rocket: 🚀 (4 bytes: 0xF0, 0x9F, 0x9A, 0x80)
  // US Flag: 🇺🇸 (8 bytes)
  // Family: 👨‍👩‍👧‍👦 (ZWJ sequence: 18 UTF-8 bytes)
  final emojiJson =
      '{"emoji": "😀", "rocket": "🚀", "flag": "🇺🇸", "family": "👨‍👩‍👧‍👦"}';
  final emojiBytes = utf8.encode(emojiJson);
  final emojiDecoded = parse1ByteChunks(emojiBytes) as Map<String, dynamic>;
  Expect.equals('😀', emojiDecoded['emoji']);
  Expect.equals('🚀', emojiDecoded['rocket']);
  Expect.equals('🇺🇸', emojiDecoded['flag']);
  Expect.equals('👨‍👩‍👧‍👦', emojiDecoded['family']);

  // 2. Split escapes across 1-byte chunks
  final escapesJson =
      r'{"esc": "line1\nline2\ttab\"quote\\slash\u0000null\u20ACeuro\uD83D\uDE00surrogate"}';
  final escapesBytes = utf8.encode(escapesJson);
  final escapesDecoded = parse1ByteChunks(escapesBytes) as Map<String, dynamic>;
  Expect.equals(
    'line1\nline2\ttab"quote\\slash\x00null€euro😀surrogate',
    escapesDecoded['esc'],
  );

  // 3. Split numbers across 1-byte chunks
  final numbersJson =
      '{"ints": [0, -1, 42, 9223372036854775807, -9223372036854775808], "doubles": [0.0, -0.5, 3.14159265, 1.23e10, -4.56e-8, 1e-15]}';
  final numbersBytes = utf8.encode(numbersJson);
  final numbersDecoded = parse1ByteChunks(numbersBytes) as Map<String, dynamic>;
  Expect.equals(42, (numbersDecoded['ints'] as List)[2]);
  Expect.equals(9223372036854775807, (numbersDecoded['ints'] as List)[3]);
  Expect.equals(-9223372036854775808, (numbersDecoded['ints'] as List)[4]);
  Expect.equals(3.14159265, (numbersDecoded['doubles'] as List)[2]);
  Expect.equals(1.23e10, (numbersDecoded['doubles'] as List)[3]);
  Expect.equals(-4.56e-8, (numbersDecoded['doubles'] as List)[4]);

  // 4. Split chunk allowMalformed: true with partial / truncated multibyte UTF-8 sequences
  final malformedTruncated = [0x22, 0xF0, 0x9F, 0x22]; // '"\xF0\x9F"'
  final malformedDecoded = parse1ByteChunks(
    malformedTruncated,
    allowMalformed: true,
  );
  Expect.equals('\uFFFD', malformedDecoded);

  // Split chunk allowMalformed: false must throw FormatException
  Expect.throwsFormatException(() {
    parse1ByteChunks(malformedTruncated, allowMalformed: false);
  });
}

void testFusedCodecs() {
  // 1. utf8.decoder.fuse(json.decoder) returns JsonUtf8Decoder
  final fusedDecoder = utf8.decoder.fuse(json.decoder);
  Expect.type<JsonUtf8Decoder>(fusedDecoder);
  Expect.isFalse((fusedDecoder as JsonUtf8Decoder).allowMalformed);
  Expect.isNull(fusedDecoder.reviver);

  // 2. Decode UTF-8 bytes through fused decoder
  final jsonUtf8Bytes = Uint8List.fromList(
    utf8.encode('{"score": 98.5, "passed": true, "items": [1, 2, 3]}'),
  );
  final decoded = fusedDecoder.convert(jsonUtf8Bytes) as Map<String, dynamic>;
  Expect.equals(98.5, decoded['score']);
  Expect.equals(true, decoded['passed']);
  Expect.listEquals([1, 2, 3], decoded['items'] as List);

  // 3. Fusing with custom reviver
  final reviver = (Object? k, Object? v) => k == 'score' ? 100.0 : v;
  final fusedWithReviver = utf8.decoder.fuse(JsonDecoder(reviver));
  Expect.type<JsonUtf8Decoder>(fusedWithReviver);
  Expect.equals(reviver, (fusedWithReviver as JsonUtf8Decoder).reviver);
  final decodedReviver =
      fusedWithReviver.convert(jsonUtf8Bytes) as Map<String, dynamic>;
  Expect.equals(100.0, decodedReviver['score']);

  // 4. Fusing with allowMalformed: true
  final fusedMalformed =
      Utf8Decoder(allowMalformed: true).fuse(json.decoder) as JsonUtf8Decoder;
  Expect.isTrue(fusedMalformed.allowMalformed);
  final badBytes = Uint8List.fromList([0x22, 0x80, 0x22]); // '"\x80"'
  Expect.equals('\uFFFD', fusedMalformed.convert(badBytes));

  // 5. json.fuse(utf8) encoder and decoder
  final jsonToUtf8 = json.fuse(utf8);
  final encodedData = jsonToUtf8.encode({
    'name': 'fused',
    'values': [10, 20.5],
  });
  Expect.type<Uint8List>(encodedData);

  final decodedData = jsonToUtf8.decode(encodedData) as Map<String, dynamic>;
  Expect.equals('fused', decodedData['name']);
  Expect.listEquals([10, 20.5], decodedData['values'] as List);
}
