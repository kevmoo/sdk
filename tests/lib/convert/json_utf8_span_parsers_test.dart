// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testParseInt();
  testParseDouble();
  testParseBool();
  testIsNull();
  testEqualsAscii();
  testJsonKeyOptions();
  testDecodeString();
  testIsVerbatim();
  testSkipMethods();
  testEncoderBufferWriters();
  testWriteStringEscapeDensities();
  testSurrogateEncoding();
  testRfc8259NumberGrammar();
  testIntegerOverflowAndLimits();
  testNonFiniteDoubleRejection();
  testWhitespaceAndControlChars();
  testDecodeStringWithEscapesAndSurrogates();
  testSkipValueControlChars();
  testDoubleFastPathAndNegativeZero();
  testNegativeZeroPreservation();
  testMultiRootFormatException();
  testJsonKeyOptionsCollisionsAndDuplicates();
  testBufferOverflowAndBounds();
  testUnescapedControlCharsInStrings();
  testContainerSkippingNesting();
  testSkipValueMaxDepth();
  testWriteDoubleToBufferEdgeCases();
  testDecoderSkipValueScalarValidation();
  testDirectToSinkEncoderWriters();
  testPeekTrailingComma();
  testHasNextAtomicRollback();
  testBatchedSinkWriters();
  testUnterminatedStringSkipping();
  testDoubleNativeLinkageAndPrecision();
  testBufferPoolSinkWriters();
  testLeadingFractionalZerosPrecision();
  testReentrantSinkWriters();
  testDecoderSkipValue64LevelsMixedContainers();
  testZeroAllocationKeySlicing();
  testSkipValueInvalidEscapes();
  testWebSafeFnv1aHash();
  testWriteAsciiAndRawJsonBounds();
  testMatchKeyEscapedKeys();
  testDirectSinkFormatterStress();
  testWholeCodebaseBoundsAndSentinels();
  testTypedDataViewsNative();
  testJsonKeyOptionsStressAndCollisions();
  testMatchKeySurrogatesAndPathologicalKeys();
}

void testParseInt() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Happy paths
  Expect.equals(0, JsonUtf8Decoder.parseInt(b('0'), 0, 1));
  Expect.equals(42, JsonUtf8Decoder.parseInt(b('42'), 0, 2));
  Expect.equals(-42, JsonUtf8Decoder.parseInt(b('-42'), 0, 3));
  Expect.equals(123456789, JsonUtf8Decoder.parseInt(b('123456789'), 0, 9));
  Expect.equals(
    9223372036854775807,
    JsonUtf8Decoder.parseInt(b('9223372036854775807'), 0, 19),
  );
  Expect.equals(
    -9223372036854775808,
    JsonUtf8Decoder.parseInt(b('-9223372036854775808'), 0, 20),
  );

  // Whitespace trimming
  Expect.equals(100, JsonUtf8Decoder.parseInt(b('  100  '), 0, 7));

  // tryParseInt
  Expect.equals(42, JsonUtf8Decoder.tryParseInt(b('42'), 0, 2));
  Expect.isNull(JsonUtf8Decoder.tryParseInt(b('abc'), 0, 3));
  Expect.isNull(JsonUtf8Decoder.tryParseInt(b(''), 0, 0));
  Expect.isNull(JsonUtf8Decoder.tryParseInt(b('  '), 0, 2));

  // Invalid throws
  Expect.throwsFormatException(() => JsonUtf8Decoder.parseInt(b('abc'), 0, 3));
  Expect.throwsFormatException(() => JsonUtf8Decoder.parseInt(b(''), 0, 0));
}

void testParseDouble() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Basic floats
  Expect.equals(0.0, JsonUtf8Decoder.parseDouble(b('0.0'), 0, 3));
  Expect.equals(3.14159, JsonUtf8Decoder.parseDouble(b('3.14159'), 0, 7));
  Expect.equals(-3.14159, JsonUtf8Decoder.parseDouble(b('-3.14159'), 0, 8));
  Expect.equals(123.0, JsonUtf8Decoder.parseDouble(b('123'), 0, 3));
  Expect.equals(-123.0, JsonUtf8Decoder.parseDouble(b('-123'), 0, 4));

  // Exponents
  Expect.equals(1e10, JsonUtf8Decoder.parseDouble(b('1e10'), 0, 4));
  Expect.equals(1e-10, JsonUtf8Decoder.parseDouble(b('1e-10'), 0, 5));
  Expect.equals(1.5e3, JsonUtf8Decoder.parseDouble(b('1.5e3'), 0, 5));
  Expect.equals(-2.5e-2, JsonUtf8Decoder.parseDouble(b('-2.5e-2'), 0, 7));

  // Floats within 2^53 mantissa limit
  final bigFloat = 9007199254740991.0;
  Expect.equals(
    bigFloat,
    JsonUtf8Decoder.parseDouble(b('9007199254740991'), 0, 16),
  );

  // Whitespace handling
  Expect.equals(42.5, JsonUtf8Decoder.parseDouble(b('  42.5  '), 0, 8));

  // tryParseDouble
  Expect.equals(1.23, JsonUtf8Decoder.tryParseDouble(b('1.23'), 0, 4));
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('not_a_num'), 0, 9));
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b(''), 0, 0));

  // Errors
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('xyz'), 0, 3),
  );
  Expect.throwsFormatException(() => JsonUtf8Decoder.parseDouble(b(''), 0, 0));
}

void testParseBool() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  Expect.isTrue(JsonUtf8Decoder.parseBool(b('true'), 0, 4));
  Expect.isFalse(JsonUtf8Decoder.parseBool(b('false'), 0, 5));

  Expect.isTrue(JsonUtf8Decoder.tryParseBool(b('true'), 0, 4)!);
  Expect.isFalse(JsonUtf8Decoder.tryParseBool(b('false'), 0, 5)!);
  Expect.isNull(JsonUtf8Decoder.tryParseBool(b('tru'), 0, 3));
  Expect.isNull(JsonUtf8Decoder.tryParseBool(b('fals'), 0, 4));
  Expect.isNull(JsonUtf8Decoder.tryParseBool(b('null'), 0, 4));

  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseBool(b('invalid'), 0, 7),
  );
}

void testIsNull() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  Expect.isTrue(JsonUtf8Decoder.isNull(b('null'), 0, 4));
  Expect.isFalse(JsonUtf8Decoder.isNull(b('nul'), 0, 3));
  Expect.isFalse(JsonUtf8Decoder.isNull(b('true'), 0, 4));
  Expect.isFalse(JsonUtf8Decoder.isNull(b('0'), 0, 1));
}

void testEqualsAscii() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final bytes = b('hello world');
  Expect.isTrue(JsonUtf8Decoder.equalsAscii(bytes, 0, 5, 'hello'));
  Expect.isTrue(JsonUtf8Decoder.equalsAscii(bytes, 6, 11, 'world'));
  Expect.isFalse(JsonUtf8Decoder.equalsAscii(bytes, 0, 5, 'world'));
  Expect.isFalse(JsonUtf8Decoder.equalsAscii(bytes, 0, 4, 'hello'));

  // Non-ASCII candidate string must return false (not match raw Latin-1 byte)
  final latin1Bytes = Uint8List.fromList([0xE9]);
  Expect.isFalse(JsonUtf8Decoder.equalsAscii(latin1Bytes, 0, 1, 'é'));
  final utf8Bytes = Uint8List.fromList(utf8.encode('café'));
  Expect.isFalse(
    JsonUtf8Decoder.equalsAscii(utf8Bytes, 0, utf8Bytes.length, 'café'),
  );

  // Emojis, Cyrillic, and Greek
  Expect.isFalse(JsonUtf8Decoder.equalsAscii(b('😀'), 0, 4, '😀'));
  Expect.isFalse(JsonUtf8Decoder.equalsAscii(b('привет'), 0, 12, 'привет'));
  Expect.isFalse(JsonUtf8Decoder.equalsAscii(b('αβγ'), 0, 6, 'αβγ'));
}

void testJsonKeyOptions() {
  final options = JsonKeyOptions.of([
    'id',
    'name',
    'latitude',
    'longitude',
    'type',
  ]);
  Expect.equals(5, options.length);

  // Immutability checks: buffers must be unmodifiable
  Expect.throws<UnsupportedError>(() => options.encodedKeys[0] = 0);
  Expect.throws<UnsupportedError>(() => options.offsets[0] = 0);
  Expect.throws<UnsupportedError>(() => options.lengths[0] = 0);

  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final src = b('{"id": 1, "name": "test", "latitude": 37.77}');
  Expect.equals(0, JsonUtf8Decoder.matchKey(src, 2, 4, options)); // 'id'
  Expect.equals(1, JsonUtf8Decoder.matchKey(src, 11, 15, options)); // 'name'
  Expect.equals(
    2,
    JsonUtf8Decoder.matchKey(src, 27, 35, options),
  ); // 'latitude'
  Expect.equals(-1, JsonUtf8Decoder.matchKey(src, 0, 1, options)); // '{'
}

void testDecodeString() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Verbatim ASCII
  Expect.equals('hello', JsonUtf8Decoder.decodeString(b('hello'), 0, 5));
  Expect.equals('', JsonUtf8Decoder.decodeString(b(''), 0, 0));

  // Escapes
  Expect.equals(
    'hello "world"',
    JsonUtf8Decoder.decodeString(b(r'hello \"world\"'), 0, 15),
  );
  Expect.equals(
    'line1\nline2\ttab',
    JsonUtf8Decoder.decodeString(b(r'line1\nline2\ttab'), 0, 17),
  );
  Expect.equals(
    'back\\slash',
    JsonUtf8Decoder.decodeString(b(r'back\\slash'), 0, 11),
  );

  // Unicode \uXXXX
  Expect.equals(
    'Euro: \u20AC',
    JsonUtf8Decoder.decodeString(b(r'Euro: \u20AC'), 0, 12),
  );

  // UTF-16 Surrogate pair \uD83D\uDE00 (Grinning Face emoji 😀)
  Expect.equals('😀', JsonUtf8Decoder.decodeString(b(r'\uD83D\uDE00'), 0, 12));

  // Multi-byte UTF-8 bytes directly
  final utf8Bytes = Uint8List.fromList([0xE2, 0x82, 0xAC]); // €
  Expect.equals('€', JsonUtf8Decoder.decodeString(utf8Bytes, 0, 3));
}

void testIsVerbatim() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  Expect.isTrue(JsonUtf8Decoder.isVerbatim(b('hello world'), 0, 11));
  Expect.isFalse(JsonUtf8Decoder.isVerbatim(b(r'hello \"world\"'), 0, 15));

  // Must reject multi-byte UTF-8 sequences (€, emojis)
  final euroBytes = Uint8List.fromList([0xE2, 0x82, 0xAC]); // €
  Expect.isFalse(JsonUtf8Decoder.isVerbatim(euroBytes, 0, 3));
  final emojiBytes = Uint8List.fromList([0xF0, 0x9F, 0x98, 0x80]); // 😀
  Expect.isFalse(JsonUtf8Decoder.isVerbatim(emojiBytes, 0, 4));

  // Must reject raw unescaped quotes
  Expect.isFalse(JsonUtf8Decoder.isVerbatim(b('hello"world'), 0, 11));

  // Must reject control characters and DEL
  Expect.isFalse(JsonUtf8Decoder.isVerbatim(Uint8List.fromList([0x00]), 0, 1));
  Expect.isFalse(JsonUtf8Decoder.isVerbatim(Uint8List.fromList([0x1F]), 0, 1));
  Expect.isFalse(JsonUtf8Decoder.isVerbatim(Uint8List.fromList([0x7F]), 0, 1));
}

void testSkipMethods() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final json = b('  {"key": [1, 2, 3], "nested": {"a": "b"}}, "after"');
  final afterWs = JsonUtf8Decoder.skipWhitespace(json, 0);
  Expect.equals(2, afterWs); // starts at '{'

  final afterObj = JsonUtf8Decoder.skipValue(json, afterWs);
  // Skipped entire object
  Expect.equals(42, afterObj);

  final str = b('"hello world" rest');
  final afterStr = JsonUtf8Decoder.skipString(str, 0);
  Expect.equals(13, afterStr);
}

void testEncoderBufferWriters() {
  final buffer = Uint8List(256);

  // writeStringToBuffer
  var len = JsonUtf8Encoder.writeStringToBuffer('hello "world"', buffer, 0);
  Expect.equals('"hello \\"world\\""', utf8.decode(buffer.sublist(0, len)));

  // writeDoubleToBuffer
  len = JsonUtf8Encoder.writeDoubleToBuffer(3.14159, buffer, 0);
  Expect.equals('3.14159', utf8.decode(buffer.sublist(0, len)));

  // writeIntToBuffer
  len = JsonUtf8Encoder.writeIntToBuffer(12345, buffer, 0);
  Expect.equals('12345', utf8.decode(buffer.sublist(0, len)));

  // writeBoolToBuffer
  len = JsonUtf8Encoder.writeBoolToBuffer(true, buffer, 0);
  Expect.equals('true', utf8.decode(buffer.sublist(0, len)));
  len = JsonUtf8Encoder.writeBoolToBuffer(false, buffer, 0);
  Expect.equals('false', utf8.decode(buffer.sublist(0, len)));

  // writeNullToBuffer
  len = JsonUtf8Encoder.writeNullToBuffer(buffer, 0);
  Expect.equals('null', utf8.decode(buffer.sublist(0, len)));

  // writePropertyPrefixToBuffer
  final key = Uint8List.fromList(utf8.encode('"id"'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    key,
    isFirst: true,
  );
  Expect.equals('"id":', utf8.decode(buffer.sublist(0, len)));

  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    key,
    isFirst: false,
  );
  Expect.equals(',"id":', utf8.decode(buffer.sublist(0, len)));

  // Raw unquoted key: utf8.encode('name')
  final rawKey = Uint8List.fromList(utf8.encode('name'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    rawKey,
    isFirst: true,
  );
  Expect.equals('"name":', utf8.decode(buffer.sublist(0, len)));

  // Multibyte UTF-8 key: utf8.encode('clé')
  final utf8Key = Uint8List.fromList(utf8.encode('clé'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    utf8Key,
    isFirst: true,
  );
  Expect.equals('"clé":', utf8.decode(buffer.sublist(0, len)));

  // Pre-quoted multibyte UTF-8 key: utf8.encode('"clé"')
  final quotedUtf8Key = Uint8List.fromList(utf8.encode('"clé"'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    quotedUtf8Key,
    isFirst: false,
  );
  Expect.equals(',"clé":', utf8.decode(buffer.sublist(0, len)));

  // Key with inner unescaped quotes: utf8.encode('"a"b"')
  // Must NOT be treated as pre-quoted; must safely escape unquoted inner quotes.
  final innerQuoteKey = Uint8List.fromList(utf8.encode('"a"b"'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    innerQuoteKey,
    isFirst: true,
  );
  Expect.equals(r'"\"a\"b\"":', utf8.decode(buffer.sublist(0, len)));

  // Raw key with inner quote: utf8.encode('a"b')
  final rawInnerQuoteKey = Uint8List.fromList(utf8.encode('a"b'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    rawInnerQuoteKey,
    isFirst: true,
  );
  Expect.equals(r'"a\"b":', utf8.decode(buffer.sublist(0, len)));

  // Key with escaped inner quotes: utf8.encode(r'"a\"b"')
  // IS a valid pre-quoted string; must not be double quoted.
  final escapedQuoteKey = Uint8List.fromList(utf8.encode(r'"a\"b"'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    escapedQuoteKey,
    isFirst: true,
  );
  Expect.equals(r'"a\"b":', utf8.decode(buffer.sublist(0, len)));

  // Key with pre-quoted escaped backslash: utf8.encode(r'"\\"')
  final escapedBackslashKey = Uint8List.fromList(utf8.encode(r'"\\"'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    escapedBackslashKey,
    isFirst: true,
  );
  Expect.equals(r'"\\":', utf8.decode(buffer.sublist(0, len)));

  // Key with invalid escape \z: utf8.encode(r'"a\zb"') -> must escape safely
  final invalidEscapeKey = Uint8List.fromList(utf8.encode(r'"a\zb"'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    invalidEscapeKey,
    isFirst: true,
  );
  Expect.equals(r'"\"a\\zb\"":', utf8.decode(buffer.sublist(0, len)));

  // Key with truncated unicode escape: utf8.encode(r'"a\u12"') -> must escape safely
  final truncatedUnicodeKey = Uint8List.fromList(utf8.encode(r'"a\u12"'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    truncatedUnicodeKey,
    isFirst: true,
  );
  Expect.equals(r'"\"a\\u12\"":', utf8.decode(buffer.sublist(0, len)));

  // Key with unescaped newline inside quotes: [0x22, 0x0A, 0x22] -> must escape safely
  final unescapedCtrlKey = Uint8List.fromList([0x22, 0x0A, 0x22]);
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    unescapedCtrlKey,
    isFirst: true,
  );
  Expect.equals(r'"\"\u000a\"":', utf8.decode(buffer.sublist(0, len)));

  // Empty key bytes: Uint8List(0)
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    Uint8List(0),
    isFirst: true,
  );
  Expect.equals('"":', utf8.decode(buffer.sublist(0, len)));

  // Pre-encoded colon-terminated keys: utf8.encode('"id":')
  final colonKey = Uint8List.fromList(utf8.encode('"id":'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    colonKey,
    isFirst: true,
  );
  Expect.equals('"id":', utf8.decode(buffer.sublist(0, len)));

  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    colonKey,
    isFirst: false,
  );
  Expect.equals(',"id":', utf8.decode(buffer.sublist(0, len)));

  // Pre-encoded colon-terminated empty key: utf8.encode('"":')
  final emptyColonKey = Uint8List.fromList(utf8.encode('"":'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    emptyColonKey,
    isFirst: true,
  );
  Expect.equals('"":', utf8.decode(buffer.sublist(0, len)));

  // Pre-encoded colon-terminated key with escaped quotes: utf8.encode(r'"k\"ey":')
  final colonEscapedQuoteKey = Uint8List.fromList(utf8.encode(r'"k\"ey":'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    colonEscapedQuoteKey,
    isFirst: true,
  );
  Expect.equals(r'"k\"ey":', utf8.decode(buffer.sublist(0, len)));

  // Pre-encoded colon-terminated key with escaped backslash: utf8.encode(r'"k\\":')
  final colonEscapedBackslashKey = Uint8List.fromList(utf8.encode(r'"k\\":'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    colonEscapedBackslashKey,
    isFirst: false,
  );
  Expect.equals(r',"k\\":', utf8.decode(buffer.sublist(0, len)));
}

/// [JsonUtf8Encoder.writeString] sizes its scratch buffer for the common case
/// of three bytes per code unit and re-sizes to the six-byte worst case only
/// when the string is escape heavy. Both paths must produce identical output,
/// so exercise strings on either side of that boundary.
void testWriteStringEscapeDensities() {
  String encode(String value, {required bool copy}) {
    final sink = BytesBuilder(copy: copy);
    JsonUtf8Encoder.writeString(value, sink);
    return utf8.decode(sink.takeBytes());
  }

  final samples = <String>[
    "",
    "a",
    "id",
    "plain ascii text",
    "café €",
    "中文测试", // 3 bytes per code unit
    "\u{1F680}\u{1F600}", // surrogate pairs, 4 bytes per pair
    '"', "\\", "\b\f\n\r\t",
    "\u0000\u0001\u001f", // 6 bytes per code unit: forces the re-size
    "mix \u0001 \"q\" \u{1F680} 中",
    "\u0001" * 1000, // wholly escape heavy
    "a" * 1000,
    "中" * 1000,
    "\u{1F680}" * 500,
    String.fromCharCode(0xD800), // isolated high surrogate
    String.fromCharCode(0xDC00), // isolated low surrogate
    "before${String.fromCharCode(0xD800)}after",
  ];

  for (final value in samples) {
    for (final copy in [false, true]) {
      final actual = encode(value, copy: copy);
      Expect.equals(
        json.encode(value),
        actual,
        'writeString("${value.length}", copy: $copy)',
      );

      // The token writer routes its string and name output through the same
      // helper, so it must agree byte for byte.
      final sink = BytesBuilder(copy: copy);
      JsonTokenWriter.toSink(sink)
        ..beginObject()
        ..writeName("k")
        ..writeString(value)
        ..endObject();
      Expect.equals(
        json.encode({"k": value}),
        utf8.decode(sink.takeBytes()),
        'JsonTokenWriter round trip for a ${value.length} code unit string (copy: $copy)',
      );
    }
  }
}

void testSurrogateEncoding() {
  final buf = Uint8List(128);
  // Isolated low surrogate: \uDC00
  var len = JsonUtf8Encoder.writeStringToBuffer('\uDC00', buf, 0);
  Expect.equals(r'"\udc00"', utf8.decode(buf.sublist(0, len)));

  // Isolated high surrogate: \uD800
  len = JsonUtf8Encoder.writeStringToBuffer('\uD800', buf, 0);
  Expect.equals(r'"\ud800"', utf8.decode(buf.sublist(0, len)));

  // High surrogate followed by ASCII: \uD800A
  len = JsonUtf8Encoder.writeStringToBuffer('\uD800A', buf, 0);
  Expect.equals(r'"\ud800A"', utf8.decode(buf.sublist(0, len)));

  // ASCII followed by high surrogate: A\uD800
  len = JsonUtf8Encoder.writeStringToBuffer('A\uD800', buf, 0);
  Expect.equals(r'"A\ud800"', utf8.decode(buf.sublist(0, len)));

  // Two consecutive isolated high surrogates: \uD800\uD800
  len = JsonUtf8Encoder.writeStringToBuffer('\uD800\uD800', buf, 0);
  Expect.equals(r'"\ud800\ud800"', utf8.decode(buf.sublist(0, len)));

  // Two consecutive isolated low surrogates: \uDC00\uDC00
  len = JsonUtf8Encoder.writeStringToBuffer('\uDC00\uDC00', buf, 0);
  Expect.equals(r'"\udc00\udc00"', utf8.decode(buf.sublist(0, len)));

  // Low surrogate followed by high surrogate: \uDC00\uD800
  len = JsonUtf8Encoder.writeStringToBuffer('\uDC00\uD800', buf, 0);
  Expect.equals(r'"\udc00\ud800"', utf8.decode(buf.sublist(0, len)));

  // Valid surrogate pair: \uD83D\uDE00 (Grinning Face emoji 😀)
  len = JsonUtf8Encoder.writeStringToBuffer('\uD83D\uDE00', buf, 0);
  Expect.equals('"😀"', utf8.decode(buf.sublist(0, len)));

  // Valid surrogate pair followed by isolated surrogate: 😀\uD800
  len = JsonUtf8Encoder.writeStringToBuffer('😀\uD800', buf, 0);
  Expect.equals(r'"😀\ud800"', utf8.decode(buf.sublist(0, len)));

  // Isolated surrogate followed by valid surrogate pair: \uDC00😀
  len = JsonUtf8Encoder.writeStringToBuffer('\uDC00😀', buf, 0);
  Expect.equals(r'"\udc00😀"', utf8.decode(buf.sublist(0, len)));

  // Stringifier & top-level encoder consistency on isolated surrogates
  Expect.equals(r'"\ud800"', utf8.decode(jsonUtf8Encode('\uD800')));
  Expect.equals(r'"\udc00"', utf8.decode(jsonUtf8Encode('\uDC00')));
  Expect.equals(r'"a\ud800b"', utf8.decode(jsonUtf8Encode('a\uD800b')));
  Expect.equals('"\u{10000}"', utf8.decode(jsonUtf8Encode('\uD800\uDC00')));
  Expect.equals(r'"\udc00\ud800"', utf8.decode(jsonUtf8Encode('\uDC00\uD800')));

  final enc = JsonUtf8Encoder();
  Expect.equals(r'"\ud800"', utf8.decode(enc.convert('\uD800')));
  Expect.equals(r'"\udc00"', utf8.decode(enc.convert('\uDC00')));

  final sb = BytesBuilder();
  JsonUtf8Encoder.writeString('\uD800', sb);
  Expect.equals(r'"\ud800"', utf8.decode(sb.takeBytes()));
}

void testRfc8259NumberGrammar() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Reject leading +
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('+1.0'), 0, 4));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('+1.0'), 0, 4),
  );
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('+42'), 0, 3));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('+42'), 0, 3),
  );

  // Reject leading zeros
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('0123'), 0, 4));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('0123'), 0, 4),
  );
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('-0123'), 0, 5));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('-0123'), 0, 5),
  );
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('00'), 0, 2));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('00'), 0, 2),
  );

  // Reject missing integer digit (.5, -.5)
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('.5'), 0, 2));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('.5'), 0, 2),
  );
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('-.5'), 0, 3));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('-.5'), 0, 3),
  );

  // Reject missing fraction digit (5., 0.)
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('5.'), 0, 2));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('5.'), 0, 2),
  );
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('0.'), 0, 2));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('0.'), 0, 2),
  );

  // Reject NaN / Infinity
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('NaN'), 0, 3));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('NaN'), 0, 3),
  );
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('Infinity'), 0, 8));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('Infinity'), 0, 8),
  );
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('-Infinity'), 0, 9));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('-Infinity'), 0, 9),
  );

  // Reject malformed exponents
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('1e'), 0, 2));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('1e'), 0, 2),
  );
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('1e+'), 0, 3));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('1e+'), 0, 3),
  );

  // Reject hex numbers
  Expect.isNull(JsonUtf8Decoder.tryParseDouble(b('0x12'), 0, 4));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('0x12'), 0, 4),
  );

  // Valid numbers
  Expect.equals(0.0, JsonUtf8Decoder.parseDouble(b('0'), 0, 1));
  Expect.equals(-0.0, JsonUtf8Decoder.parseDouble(b('-0'), 0, 2));
  Expect.equals(0.5, JsonUtf8Decoder.parseDouble(b('0.5'), 0, 3));
  Expect.equals(-0.5, JsonUtf8Decoder.parseDouble(b('-0.5'), 0, 4));
  Expect.equals(100.0, JsonUtf8Decoder.parseDouble(b('100'), 0, 3));
  Expect.equals(1e5, JsonUtf8Decoder.parseDouble(b('1e5'), 0, 3));
  Expect.equals(1e-5, JsonUtf8Decoder.parseDouble(b('1e-5'), 0, 4));
  Expect.equals(1e+5, JsonUtf8Decoder.parseDouble(b('1e+5'), 0, 4));
}

void testIntegerOverflowAndLimits() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Reject > int64 max
  Expect.isNull(JsonUtf8Decoder.tryParseInt(b('9223372036854775808'), 0, 19));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseInt(b('9223372036854775808'), 0, 19),
  );
  Expect.isNull(
    JsonUtf8Decoder.tryParseInt(b('9999999999999999999999999'), 0, 25),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseInt(b('9999999999999999999999999'), 0, 25),
  );

  // Reject < int64 min
  Expect.isNull(JsonUtf8Decoder.tryParseInt(b('-9223372036854775809'), 0, 20));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseInt(b('-9223372036854775809'), 0, 20),
  );
  Expect.isNull(
    JsonUtf8Decoder.tryParseInt(b('-9999999999999999999999999'), 0, 26),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseInt(b('-9999999999999999999999999'), 0, 26),
  );

  // Reject leading +
  Expect.isNull(JsonUtf8Decoder.tryParseInt(b('+123'), 0, 4));
  Expect.throwsFormatException(() => JsonUtf8Decoder.parseInt(b('+123'), 0, 4));

  // Reject leading zeros
  Expect.isNull(JsonUtf8Decoder.tryParseInt(b('0123'), 0, 4));
  Expect.throwsFormatException(() => JsonUtf8Decoder.parseInt(b('0123'), 0, 4));
  Expect.isNull(JsonUtf8Decoder.tryParseInt(b('-0123'), 0, 5));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseInt(b('-0123'), 0, 5),
  );
  Expect.isNull(JsonUtf8Decoder.tryParseInt(b('00'), 0, 2));
  Expect.throwsFormatException(() => JsonUtf8Decoder.parseInt(b('00'), 0, 2));

  // Valid 64-bit limits
  Expect.equals(
    9223372036854775807,
    JsonUtf8Decoder.parseInt(b('9223372036854775807'), 0, 19),
  );
  Expect.equals(
    -9223372036854775808,
    JsonUtf8Decoder.parseInt(b('-9223372036854775808'), 0, 20),
  );
  Expect.equals(0, JsonUtf8Decoder.parseInt(b('0'), 0, 1));
  // -0 is a valid integer (matching int.parse("-0") == 0)
  Expect.equals(0, JsonUtf8Decoder.tryParseInt(b('-0'), 0, 2));
  Expect.equals(0, JsonUtf8Decoder.parseInt(b('-0'), 0, 2));
}

void testNonFiniteDoubleRejection() {
  final buf = Uint8List(64);
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDoubleToBuffer(double.nan, buf, 0),
  );
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDoubleToBuffer(double.infinity, buf, 0),
  );
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDoubleToBuffer(double.negativeInfinity, buf, 0),
  );

  final sink = BytesBuilder();
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDouble(double.nan, sink),
  );
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDouble(double.infinity, sink),
  );
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDouble(double.negativeInfinity, sink),
  );
}

void testWhitespaceAndControlChars() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  Expect.equals(4, JsonUtf8Decoder.skipWhitespace(b(' \t\r\n42'), 0));
  Expect.equals(0, JsonUtf8Decoder.skipWhitespace(b('\x0042'), 0));
  Expect.equals(0, JsonUtf8Decoder.skipWhitespace(b('\x1f42'), 0));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseDouble(b('\x0042'), 0, 3),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.parseInt(b('\x0042'), 0, 3),
  );
}

void testDecodeStringWithEscapesAndSurrogates() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Escapes with surrounding non-ASCII UTF-8
  final text = 'café \\"au lait\\" €';
  final bytes = b(text);
  Expect.equals(
    'café "au lait" €',
    JsonUtf8Decoder.decodeString(bytes, 0, bytes.length),
  );

  // Truncated escape
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.decodeString(b(r'hello\'), 0, 6),
  );

  // Invalid escape char
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.decodeString(b(r'hello\x41'), 0, 8),
  );

  // Incomplete unicode escape
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.decodeString(b(r'hello\u12'), 0, 9),
  );

  // Invalid hex in unicode escape
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.decodeString(b(r'hello\u12G4'), 0, 11),
  );
}

void testSkipValueControlChars() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Control char \x00 should not be skipped as whitespace, and skipValue must reject it
  final withNul = b('\x00{"a": 1}');
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(withNul, 0));
  Expect.equals(0, JsonUtf8Decoder.skipWhitespace(withNul, 0));

  // Unescaped control characters in strings within skipValue must throw FormatException
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(Uint8List.fromList([0x22, 0x0A, 0x22]), 0),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(
      Uint8List.fromList([123, 0x22, 0x61, 0x22, 58, 0x22, 0x00, 0x22, 125]),
      0,
    ),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(
      Uint8List.fromList([91, 0x22, 0x09, 0x22, 93]),
      0,
    ),
  );

  // skipString must throw FormatException on unescaped control characters
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipString(Uint8List.fromList([0x22, 0x00, 0x22]), 0),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipString(Uint8List.fromList([0x22, 0x1F, 0x22]), 0),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipString(Uint8List.fromList([0x22, 0x0A, 0x22]), 0),
  );

  // Invalid scalar tokens starting characters (@#$%, undefined) must throw FormatException
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b(r'{"skip": @#$%^&*!, "keep": 1}'), 9),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('{"skip": undefined}'), 9),
  );
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b(r'@#$%'), 0));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('undefined'), 0),
  );

  // JsonTokenReader.skipValue() must also throw on invalid scalar tokens
  final tr1 = JsonTokenReader.fromBytes(b(r'{"skip": @#$%^&*!, "keep": 1}'));
  tr1.beginObject();
  Expect.equals('skip', tr1.nextName());
  Expect.throwsFormatException(() => tr1.skipValue());

  final tr2 = JsonTokenReader.fromBytes(b('{"skip": undefined}'));
  tr2.beginObject();
  Expect.equals('skip', tr2.nextName());
  Expect.throwsFormatException(() => tr2.skipValue());

  final tr3 = JsonTokenReader.fromBytes(b('undefined'));
  Expect.throwsFormatException(() => tr3.skipValue());
}

void testDoubleFastPathAndNegativeZero() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Pure Dart fast path values
  Expect.equals(0.0, JsonUtf8Decoder.parseDouble(b('0'), 0, 1));
  Expect.equals(0.0, JsonUtf8Decoder.parseDouble(b('0.0'), 0, 3));
  Expect.equals(-0.0, JsonUtf8Decoder.parseDouble(b('-0'), 0, 2));
  Expect.equals(-0.0, JsonUtf8Decoder.parseDouble(b('-0.0'), 0, 4));
  Expect.isTrue(JsonUtf8Decoder.parseDouble(b('-0.0'), 0, 4).isNegative);
  Expect.isTrue(JsonUtf8Decoder.parseDouble(b('-0'), 0, 2).isNegative);

  // Exact coordinates
  Expect.equals(37.7749, JsonUtf8Decoder.parseDouble(b('37.7749'), 0, 7));
  Expect.equals(-122.4194, JsonUtf8Decoder.parseDouble(b('-122.4194'), 0, 9));

  // 15-digit fractional floats (excluding leading zero from digit count)
  Expect.equals(
    0.123456789012345,
    JsonUtf8Decoder.parseDouble(b('0.123456789012345'), 0, 17),
  );
  Expect.equals(
    0.00000000000001,
    JsonUtf8Decoder.parseDouble(b('0.00000000000001'), 0, 16),
  );
  Expect.equals(
    -0.123456789012345,
    JsonUtf8Decoder.parseDouble(b('-0.123456789012345'), 0, 18),
  );
  Expect.equals(
    0.987654321098765,
    JsonUtf8Decoder.parseDouble(b('0.987654321098765'), 0, 17),
  );

  // Exponent formats in fast path
  Expect.equals(1500.0, JsonUtf8Decoder.parseDouble(b('1.5e3'), 0, 5));
  Expect.equals(0.0015, JsonUtf8Decoder.parseDouble(b('1.5e-3'), 0, 6));
}

void testNegativeZeroPreservation() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // tryParseInt and parseInt must parse -0 as integer 0
  Expect.equals(0, JsonUtf8Decoder.tryParseInt(b('-0'), 0, 2));
  Expect.equals(0, JsonUtf8Decoder.tryParseInt(b('  -0  '), 0, 6));
  Expect.equals(0, JsonUtf8Decoder.parseInt(b('-0'), 0, 2));
  Expect.equals(0, JsonUtf8Decoder.parseInt(b('  -0  '), 0, 6));

  // JsonTokenReader.readInt() on -0 must return integer 0
  final intReader = JsonTokenReader.fromBytes(b('-0'));
  Expect.equals(0, intReader.readInt());

  // JsonTokenReader.readNum() on -0 must return integer 0 (aligning with jsonDecode)
  final reader = JsonTokenReader.fromBytes(b('-0'));
  final numVal = reader.readNum();
  Expect.type<int>(numVal);
  Expect.equals(0, numVal);

  // jsonUtf8Decode on -0 must return integer 0
  final topDecoded = jsonUtf8Decode(b('-0'));
  Expect.type<int>(topDecoded);
  Expect.equals(0, topDecoded);

  // JsonTokenReader.readDouble() on -0 continues to return -0.0 (double)
  final dblReader = JsonTokenReader.fromBytes(b('-0'));
  final dblVal = dblReader.readDouble();
  Expect.type<double>(dblVal);
  Expect.equals(-0.0, dblVal);
  Expect.isTrue(dblVal.isNegative);
  Expect.equals(double.negativeInfinity, 1 / dblVal);

  // Array containing [-0, 0]
  final arrayReader = JsonTokenReader.fromBytes(b('[-0, 0]'));
  arrayReader.beginArray();
  final v1 = arrayReader.readNum();
  Expect.type<int>(v1);
  Expect.equals(0, v1);

  final v2 = arrayReader.readNum();
  Expect.type<int>(v2);
  Expect.equals(0, v2);
  arrayReader.endArray();
}

void testMultiRootFormatException() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final reader = JsonTokenReader.fromBytes(b('{"a": 1} 42'));
  reader.beginObject();
  Expect.equals('a', reader.nextName());
  Expect.equals(1, reader.readInt());
  reader.endObject();

  // Reading another root token after document root must throw FormatException (not StateError)
  Expect.throws<FormatException>(() => reader.readNum());
}

void testJsonKeyOptionsCollisionsAndDuplicates() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Duplicate keys in list - should keep first index
  final dupOptions = JsonKeyOptions.of(['duplicate', 'unique', 'duplicate']);
  Expect.equals(3, dupOptions.length);
  final dupBytes = b('"duplicate"');
  Expect.equals(0, dupOptions.selectKey(dupBytes, 1, 10));

  // Single key
  final single = JsonKeyOptions.of(['single']);
  Expect.equals(1, single.length);
  Expect.equals(0, single.selectKey(b('single'), 0, 6));
  Expect.equals(-1, single.selectKey(b('other'), 0, 5));

  // Large key set (>50 keys) to test hash table linear probing and table resizing
  final manyKeys = List.generate(100, (i) => 'key_schema_field_$i');
  final manyOptions = JsonKeyOptions.of(manyKeys);
  for (var i = 0; i < 100; i++) {
    final kb = b(manyKeys[i]);
    Expect.equals(i, manyOptions.selectKey(kb, 0, kb.length));
  }
  final missing = b('key_schema_field_999');
  Expect.equals(-1, manyOptions.selectKey(missing, 0, missing.length));

  // Multibyte UTF-8 keys in JsonKeyOptions
  final utf8Options = JsonKeyOptions.of(['id', 'clé', '😀', 'active']);
  Expect.equals(4, utf8Options.length);
  final cleBytes = b('clé');
  Expect.equals(1, utf8Options.selectKey(cleBytes, 0, cleBytes.length));
  final emojiBytes = b('😀');
  Expect.equals(2, utf8Options.selectKey(emojiBytes, 0, emojiBytes.length));
  final activeBytes = b('active');
  Expect.equals(3, utf8Options.selectKey(activeBytes, 0, activeBytes.length));
}

void testBufferOverflowAndBounds() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // writeDoubleToBuffer exact fit -> Succeeds
  final exactDoubleBuf = Uint8List(7);
  final dLen = JsonUtf8Encoder.writeDoubleToBuffer(3.14159, exactDoubleBuf, 0);
  Expect.equals(7, dLen);
  Expect.equals('3.14159', utf8.decode(exactDoubleBuf));

  // writeDoubleToBuffer exact boundary fit at offset -> Succeeds
  final offsetDoubleBuf = Uint8List(10);
  final dLen2 = JsonUtf8Encoder.writeDoubleToBuffer(
    3.14159,
    offsetDoubleBuf,
    3,
  );
  Expect.equals(7, dLen2);
  Expect.equals('3.14159', utf8.decode(offsetDoubleBuf.sublist(3, 10)));

  // writeDoubleToBuffer undersized buffer -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeDoubleToBuffer(3.14159, Uint8List(2), 0),
  );

  // writeDoubleToBuffer negative offset -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeDoubleToBuffer(3.14159, Uint8List(16), -1),
  );

  // writeDoubleToBuffer offset out of bounds -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeDoubleToBuffer(3.14159, Uint8List(16), 14),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeDoubleToBuffer(3.14159, Uint8List(16), 1000),
  );

  // writeStringToBuffer exact fit -> Succeeds
  final exactStrBuf = Uint8List(7);
  final sLen = JsonUtf8Encoder.writeStringToBuffer('hello', exactStrBuf, 0);
  Expect.equals(7, sLen);
  Expect.equals('"hello"', utf8.decode(exactStrBuf));

  // writeStringToBuffer exact boundary fit at offset -> Succeeds
  final offsetStrBuf = Uint8List(10);
  final sLen2 = JsonUtf8Encoder.writeStringToBuffer('hello', offsetStrBuf, 3);
  Expect.equals(7, sLen2);
  Expect.equals('"hello"', utf8.decode(offsetStrBuf.sublist(3, 10)));

  // writeStringToBuffer undersized buffer -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeStringToBuffer('hello world', Uint8List(4), 0),
  );

  // writeStringToBuffer negative offset -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeStringToBuffer('hello', Uint8List(16), -1),
  );

  // writeStringToBuffer offset out of bounds -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeStringToBuffer('hello', Uint8List(16), 14),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeStringToBuffer('hello', Uint8List(16), 1000),
  );

  // writeBoolToBuffer exact fit -> Succeeds
  final exactBoolTrueBuf = Uint8List(4);
  final bTrueLen = JsonUtf8Encoder.writeBoolToBuffer(true, exactBoolTrueBuf, 0);
  Expect.equals(4, bTrueLen);
  Expect.equals('true', utf8.decode(exactBoolTrueBuf));

  final exactBoolFalseBuf = Uint8List(5);
  final bFalseLen = JsonUtf8Encoder.writeBoolToBuffer(
    false,
    exactBoolFalseBuf,
    0,
  );
  Expect.equals(5, bFalseLen);
  Expect.equals('false', utf8.decode(exactBoolFalseBuf));

  // writeBoolToBuffer exact boundary fit at offset -> Succeeds
  final offsetBoolBuf = Uint8List(10);
  final bTrueLen2 = JsonUtf8Encoder.writeBoolToBuffer(true, offsetBoolBuf, 6);
  Expect.equals(4, bTrueLen2);
  Expect.equals('true', utf8.decode(offsetBoolBuf.sublist(6, 10)));

  final bFalseLen2 = JsonUtf8Encoder.writeBoolToBuffer(false, offsetBoolBuf, 5);
  Expect.equals(5, bFalseLen2);
  Expect.equals('false', utf8.decode(offsetBoolBuf.sublist(5, 10)));

  // writeBoolToBuffer undersized buffer -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(true, Uint8List(0), 0),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(false, Uint8List(0), 0),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(true, Uint8List(3), 0),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(false, Uint8List(4), 0),
  );

  // writeBoolToBuffer negative offset -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(true, Uint8List(16), -1),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(false, Uint8List(16), -1),
  );

  // writeBoolToBuffer offset out of bounds -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(true, Uint8List(16), 13),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(false, Uint8List(16), 12),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(true, Uint8List(16), 1000),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(false, Uint8List(16), 1000),
  );

  // In-place buffer non-corruption test for writeBoolToBuffer:
  final boolBufTrue = Uint8List.fromList([1, 2, 3, 4, 5]);
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(true, boolBufTrue, 3),
  );
  Expect.listEquals([1, 2, 3, 4, 5], boolBufTrue);

  final boolBufFalse = Uint8List.fromList([1, 2, 3, 4, 5]);
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeBoolToBuffer(false, boolBufFalse, 2),
  );
  Expect.listEquals([1, 2, 3, 4, 5], boolBufFalse);

  // writeNullToBuffer exact fit -> Succeeds
  final exactNullBuf = Uint8List(4);
  final nLen = JsonUtf8Encoder.writeNullToBuffer(exactNullBuf, 0);
  Expect.equals(4, nLen);
  Expect.equals('null', utf8.decode(exactNullBuf));

  // writeNullToBuffer exact boundary fit at offset -> Succeeds
  final offsetNullBuf = Uint8List(10);
  final nLen2 = JsonUtf8Encoder.writeNullToBuffer(offsetNullBuf, 6);
  Expect.equals(4, nLen2);
  Expect.equals('null', utf8.decode(offsetNullBuf.sublist(6, 10)));

  // writeNullToBuffer undersized buffer -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeNullToBuffer(Uint8List(0), 0),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeNullToBuffer(Uint8List(3), 0),
  );

  // writeNullToBuffer negative offset -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeNullToBuffer(Uint8List(16), -1),
  );

  // writeNullToBuffer offset out of bounds -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeNullToBuffer(Uint8List(16), 13),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeNullToBuffer(Uint8List(16), 1000),
  );

  // In-place buffer non-corruption test for writeNullToBuffer:
  final nullBuf = Uint8List.fromList([1, 2, 3, 4, 5]);
  Expect.throwsRangeError(() => JsonUtf8Encoder.writeNullToBuffer(nullBuf, 3));
  Expect.listEquals([1, 2, 3, 4, 5], nullBuf);

  // In-place buffer rollback / non-corruption test:
  final buf = Uint8List.fromList([1, 2, 3, 4, 5]);
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeStringToBuffer('long_string_overflow', buf, 0),
  );
  Expect.listEquals([1, 2, 3, 4, 5], buf);
}

void testUnescapedControlCharsInStrings() {
  // Test that all unescaped control chars (0x00 to 0x1F) throw FormatException
  for (var c = 0; c < 0x20; c++) {
    final bytes = Uint8List.fromList([0x22, c, 0x22]); // '"<ctrl>"'
    Expect.throwsFormatException(
      () => JsonUtf8Decoder.decodeString(bytes, 1, 2),
    );
    Expect.isFalse(JsonUtf8Decoder.isVerbatim(bytes, 1, 2));
    Expect.throwsFormatException(() => jsonUtf8Decode(bytes));
  }

  // Also test with mixed content containing control character
  final withNewline = Uint8List.fromList(utf8.encode('hello\nworld'));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.decodeString(withNewline, 0, withNewline.length),
  );
  Expect.isFalse(
    JsonUtf8Decoder.isVerbatim(withNewline, 0, withNewline.length),
  );
  Expect.throwsFormatException(
    () => jsonUtf8Decode(Uint8List.fromList([0x22, ...withNewline, 0x22])),
  );
}

void testContainerSkippingNesting() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Array containing nested object with inner arrays
  final b1 = b('[{"a": [1, 2]}] rest');
  Expect.equals(15, JsonUtf8Decoder.skipValue(b1, 0));

  // Array with multiple objects having nested arrays
  final b2 = b('[{"a": [1, 2]}, {"b": [3, [4, 5]]}, 42] rest');
  Expect.equals(39, JsonUtf8Decoder.skipValue(b2, 0));

  // Object containing array with nested objects
  final b3 = b('{"a": [{"b": 1, "c": [2, 3]}], "d": 100} rest');
  Expect.equals(40, JsonUtf8Decoder.skipValue(b3, 0));

  // Deep multi-level container skipping (10 levels)
  final bDeep = b('[{"l1": [{"l2": [{"l3": [1, {"l4": 2}]}]}]}] rest');
  Expect.equals(44, JsonUtf8Decoder.skipValue(bDeep, 0));

  // Strings containing escaped brackets and quotes inside containers
  final bEsc = b('[ "{\\\"x\\\": [1, 2]}", "]" ] rest');
  Expect.equals(26, JsonUtf8Decoder.skipValue(bEsc, 0));

  // Mismatched container errors
  final b4 = b('[{"a": 1]');
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b4, 0));

  final b5 = b('{"a": [1, 2}');
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b5, 0));

  final b6 = b('[1, 2}');
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b6, 0));

  final b7 = b('{"a": 1]');
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b7, 0));

  // Unclosed container errors
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('{"a": [1, 2'), 0),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('[{"a": 1}'), 0),
  );

  // Trailing backslash in skipString is an unterminated string and must throw
  final b8 = b('"hello\\');
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipString(b8, 0));
}

void testSkipValueMaxDepth() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // 65 levels of nested array must throw FormatException
  final open = '[' * 65;
  final close = ']' * 65;
  final deepArray = b('$open$close');
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(deepArray, 0));

  // 64 levels of nested array should succeed
  final okOpen = '[' * 64;
  final okClose = ']' * 64;
  final okArray = b('$okOpen$okClose');
  final okOffset = JsonUtf8Decoder.skipValue(okArray, 0);
  Expect.equals(128, okOffset);

  // Mixed container nesting at depth 64
  var mixed64 = '';
  for (var i = 0; i < 32; i++) {
    mixed64 += '{"k":[';
  }
  mixed64 += '42';
  for (var i = 0; i < 32; i++) {
    mixed64 += ']}';
  }
  final mixedBytes = b(mixed64);
  final mixedOffset = JsonUtf8Decoder.skipValue(mixedBytes, 0);
  Expect.equals(mixedBytes.length, mixedOffset);

  // Mixed container nesting at depth 65 must throw
  var mixed65 = '';
  for (var i = 0; i < 32; i++) {
    mixed65 += '{"k":[';
  }
  mixed65 += '{"k": 42}';
  for (var i = 0; i < 32; i++) {
    mixed65 += ']}';
  }
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b(mixed65), 0));
}

void testWriteDoubleToBufferEdgeCases() {
  final buf = Uint8List(128);

  void check(double value, String expected) {
    final len = JsonUtf8Encoder.writeDoubleToBuffer(value, buf, 0);
    final actual = utf8.decode(buf.sublist(0, len));
    Expect.equals(expected, actual);
    final parsed = double.parse(actual);
    Expect.equals(value, parsed);
    if (value == 0.0) {
      Expect.equals(value.isNegative, parsed.isNegative);
    }
  }

  // Zeros
  check(0.0, '0.0');
  check(-0.0, '-0.0');

  // Exact integers
  check(1.0, '1.0');
  check(-1.0, '-1.0');
  check(42.0, '42.0');
  check(-42.0, '-42.0');
  check(100.0, '100.0');
  check(1000000.0, '1000000.0');

  // Exact fractions
  check(0.5, '0.5');
  check(-0.5, '-0.5');
  check(0.05, '0.05');
  check(-0.05, '-0.05');
  check(0.005, '0.005');
  check(-0.005, '-0.005');
  check(0.0005, '0.0005');
  check(-0.0005, '-0.0005');
  check(0.00005, '0.00005');
  check(-0.00005, '-0.00005');
  check(0.000005, '0.000005');
  check(-0.000005, '-0.000005');

  // Coordinates
  check(37.7749, '37.7749');
  check(-122.4194, '-122.4194');
  check(3.14159, '3.14159');
  check(-3.14159, '-3.14159');

  // Exact 53-bit boundary integers
  check(9007199254740991.0, '9007199254740991.0');
  check(-9007199254740991.0, '-9007199254740991.0');

  // Fallback paths (Grisu2 / native or toString fallback)
  void checkRoundtrip(double value) {
    final len = JsonUtf8Encoder.writeDoubleToBuffer(value, buf, 0);
    final actual = utf8.decode(buf.sublist(0, len));
    final parsed = double.parse(actual);
    Expect.equals(value, parsed);
  }

  checkRoundtrip(1.0 / 3.0);
  checkRoundtrip(0.1 + 0.2);
  checkRoundtrip(1e10);
  checkRoundtrip(-1e10);
  checkRoundtrip(1e-10);
  checkRoundtrip(-1e-10);
  checkRoundtrip(1e20);
  checkRoundtrip(-1e20);
  checkRoundtrip(1e21);
  checkRoundtrip(-1e21);
  checkRoundtrip(1e-25);
  checkRoundtrip(-1e-25);
  checkRoundtrip(9007199254740992.0);
  checkRoundtrip(-9007199254740992.0);
  checkRoundtrip(double.minPositive);
  checkRoundtrip(double.maxFinite);
  checkRoundtrip(-double.maxFinite);
}

void testDecoderSkipValueScalarValidation() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Invalid boolean tails
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('true_junk'), 0),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('false_alarm'), 0),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('nullify'), 0),
  );

  // Invalid number tails and malformed numbers
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('123abc456'), 0),
  );
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('-xyz'), 0));
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('-'), 0));
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('0123'), 0));
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('+123'), 0));
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('1.e2'), 0));
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('1e'), 0));
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('1e+'), 0));
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('1.0e-'), 0));
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('1.'), 0));
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('-.5'), 0));
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('-0123'), 0));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('123:456'), 0),
  );
}

void testDirectToSinkEncoderWriters() {
  // Test writeString directly into BytesBuilder
  void checkString(String input, String expectedJson) {
    final sink = BytesBuilder();
    JsonUtf8Encoder.writeString(input, sink);
    final actual = utf8.decode(sink.takeBytes());
    Expect.equals(expectedJson, actual);
  }

  checkString('hello', '"hello"');
  checkString('', '""');
  checkString('a"b\\c', r'"a\"b\\c"');
  checkString('line\nbreak', r'"line\nbreak"');
  checkString('tab\tchar', r'"tab\tchar"');
  checkString('ctrl\x00char', r'"ctrl\u0000char"');
  checkString('café', '"café"');
  checkString('日本語', '"日本語"');
  checkString('🚀', '"🚀"');
  checkString('\uD83D\uDE80', '"🚀"');
  checkString('isolated \uD800 high', r'"isolated \ud800 high"');
  checkString('isolated \uDC00 low', r'"isolated \udc00 low"');

  // Test writeInt directly into BytesBuilder
  void checkInt(int input, String expected) {
    final sink = BytesBuilder();
    JsonUtf8Encoder.writeInt(input, sink);
    final actual = utf8.decode(sink.takeBytes());
    Expect.equals(expected, actual);
  }

  checkInt(0, '0');
  checkInt(1, '1');
  checkInt(-1, '-1');
  checkInt(42, '42');
  checkInt(-42, '-42');
  checkInt(100, '100');
  checkInt(-100, '-100');
  checkInt(123456789, '123456789');
  checkInt(-123456789, '-123456789');
  checkInt(9223372036854775807, '9223372036854775807');
  checkInt(-9223372036854775808, '-9223372036854775808');
}

void testPeekTrailingComma() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Array with trailing comma: peek() must throw FormatException
  {
    final r = JsonTokenReader.fromBytes(b('[1, ]'));
    r.beginArray();
    Expect.equals(1, r.readInt());
    Expect.throwsFormatException(() => r.peek());
  }

  // Array with multiple elements and trailing comma
  {
    final r = JsonTokenReader.fromBytes(b('[1, 2,  \n ]'));
    r.beginArray();
    Expect.equals(1, r.readInt());
    Expect.equals(2, r.readInt());
    Expect.throwsFormatException(() => r.peek());
  }

  // Object with trailing comma: peek() must throw FormatException
  {
    final r = JsonTokenReader.fromBytes(b('{"a": 1, }'));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.equals(1, r.readInt());
    Expect.throwsFormatException(() => r.peek());
  }

  // Object with multiple elements and trailing comma
  {
    final r = JsonTokenReader.fromBytes(b('{"a": 1, "b": 2, \t\r\n }'));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.equals(1, r.readInt());
    Expect.equals('b', r.nextName());
    Expect.equals(2, r.readInt());
    Expect.throwsFormatException(() => r.peek());
  }

  // Mismatched closing delimiter after comma in array
  {
    final r = JsonTokenReader.fromBytes(b('[1, }'));
    r.beginArray();
    Expect.equals(1, r.readInt());
    Expect.throwsFormatException(() => r.peek());
  }

  // Mismatched closing delimiter after comma in object
  {
    final r = JsonTokenReader.fromBytes(b('{"a": 1, ]'));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.equals(1, r.readInt());
    Expect.throwsFormatException(() => r.peek());
  }
}

void testHasNextAtomicRollback() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Truncated array ending on comma
  {
    final r = JsonTokenReader.fromBytes(b('[1,'));
    r.beginArray();
    Expect.equals(1, r.readInt());
    Expect.throwsFormatException(() => r.hasNext());
    Expect.throwsFormatException(() => r.peek());
  }

  // Truncated object ending on comma
  {
    final r = JsonTokenReader.fromBytes(b('{"a": 1,'));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.equals(1, r.readInt());
    Expect.throwsFormatException(() => r.hasNext());
    Expect.throwsFormatException(() => r.peek());
  }

  // Trailing comma in array before ]
  {
    final r = JsonTokenReader.fromBytes(b('[1, ]'));
    r.beginArray();
    Expect.equals(1, r.readInt());
    Expect.throwsFormatException(() => r.hasNext());
    Expect.throwsFormatException(() => r.peek());
  }

  // Trailing comma in object before }
  {
    final r = JsonTokenReader.fromBytes(b('{"a": 1, }'));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.equals(1, r.readInt());
    Expect.throwsFormatException(() => r.hasNext());
    Expect.throwsFormatException(() => r.peek());
  }
}

void testBatchedSinkWriters() {
  // Test writeString with large strings and multiple UTF-8 categories
  final largeStr = 'Hello World! ' * 1000;
  final sink1 = BytesBuilder();
  JsonUtf8Encoder.writeString(largeStr, sink1);
  final actual1 = utf8.decode(sink1.takeBytes());
  Expect.equals(jsonEncode(largeStr), actual1);

  final complexStr =
      'Emoji 🚀, Greek \u03B1\u03B2\u03B3, CJK 日本語, Escapes "\n\r\t\b\f\\", Controls \x01\x1F';
  final sink2 = BytesBuilder();
  JsonUtf8Encoder.writeString(complexStr, sink2);
  final actual2 = utf8.decode(sink2.takeBytes());
  Expect.equals(jsonEncode(complexStr), actual2);

  // Test writeDouble batch writes
  final doubles = <double>[
    0.0,
    -0.0,
    1.0,
    -1.0,
    3.141592653589793,
    -3.141592653589793,
    1e10,
    -1e10,
    1e-10,
    -1e-10,
    double.minPositive,
    double.maxFinite,
    -double.maxFinite,
    9007199254740991.0,
    -9007199254740991.0,
  ];
  for (final d in doubles) {
    final sink = BytesBuilder();
    JsonUtf8Encoder.writeDouble(d, sink);
    final str = utf8.decode(sink.takeBytes());
    final parsed = double.parse(str);
    Expect.equals(d, parsed);
    if (d == 0.0) {
      Expect.equals(d.isNegative, parsed.isNegative);
    }
  }

  // Non-finite doubles must throw ArgumentError
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDouble(double.nan, BytesBuilder()),
  );
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDouble(double.infinity, BytesBuilder()),
  );
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDouble(double.negativeInfinity, BytesBuilder()),
  );
}

void testUnterminatedStringSkipping() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Top-level unclosed string in skipValue
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('"unterminated'), 0),
  );
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b('"'), 0));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b(r'"escape at end \'), 0),
  );

  // Top-level unclosed string in skipString
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipString(b('"unterminated'), 0),
  );
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipString(b('"'), 0));
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipString(b(r'"escape at end \'), 0),
  );

  // Unclosed string inside container in skipValue
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('{"unclosed'), 0),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b('["unclosed'), 0),
  );

  // Unclosed string in JsonTokenReader.skipValue
  {
    final r = JsonTokenReader.fromBytes(b('{"a": "unclosed'));
    r.beginObject();
    Expect.equals('a', r.nextName());
    Expect.throwsFormatException(() => r.skipValue());
  }
}

void testDoubleNativeLinkageAndPrecision() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Basic floating-point parsing (fast-path)
  Expect.equals(0.0, JsonUtf8Decoder.parseDouble(b('0.0'), 0, 3));
  Expect.equals(0.0, JsonUtf8Decoder.tryParseDouble(b('0.0'), 0, 3));
  Expect.equals(3.14159, JsonUtf8Decoder.parseDouble(b('3.14159'), 0, 7));
  Expect.equals(3.14159, JsonUtf8Decoder.tryParseDouble(b('3.14159'), 0, 7));
  Expect.equals(0.12345, JsonUtf8Decoder.parseDouble(b('0.12345'), 0, 7));
  Expect.equals(0.12345, JsonUtf8Decoder.tryParseDouble(b('0.12345'), 0, 7));
  Expect.equals(100.5, JsonUtf8Decoder.parseDouble(b('100.5'), 0, 5));
  Expect.equals(100.5, JsonUtf8Decoder.tryParseDouble(b('100.5'), 0, 5));

  // Fast-path exponents
  Expect.equals(1e10, JsonUtf8Decoder.parseDouble(b('1e10'), 0, 4));
  Expect.equals(1e10, JsonUtf8Decoder.tryParseDouble(b('1e10'), 0, 4));
  Expect.equals(1e-10, JsonUtf8Decoder.parseDouble(b('1e-10'), 0, 5));
  Expect.equals(1e-10, JsonUtf8Decoder.tryParseDouble(b('1e-10'), 0, 5));
  Expect.equals(1.5e3, JsonUtf8Decoder.parseDouble(b('1.5e3'), 0, 5));
  Expect.equals(1.5e3, JsonUtf8Decoder.tryParseDouble(b('1.5e3'), 0, 5));
  Expect.equals(-2.5e-2, JsonUtf8Decoder.parseDouble(b('-2.5e-2'), 0, 7));
  Expect.equals(-2.5e-2, JsonUtf8Decoder.tryParseDouble(b('-2.5e-2'), 0, 7));
  Expect.equals(
    1.234567e15,
    JsonUtf8Decoder.parseDouble(b('1.234567e15'), 0, 11),
  );
  Expect.equals(
    1.234567e15,
    JsonUtf8Decoder.tryParseDouble(b('1.234567e15'), 0, 11),
  );

  // Subnormal double & boundary floats
  Expect.equals(
    double.minPositive,
    JsonUtf8Decoder.parseDouble(
      b('${double.minPositive}'),
      0,
      '${double.minPositive}'.length,
    ),
  );
  Expect.equals(
    double.minPositive,
    JsonUtf8Decoder.tryParseDouble(
      b('${double.minPositive}'),
      0,
      '${double.minPositive}'.length,
    ),
  );
  // Min positive subnormal (4.9e-324)
  Expect.equals(4.9e-324, JsonUtf8Decoder.parseDouble(b('4.9e-324'), 0, 8));
  Expect.equals(4.9e-324, JsonUtf8Decoder.tryParseDouble(b('4.9e-324'), 0, 8));
  // Min positive normal (2.2250738585072014e-308)
  const minNormalStr = '2.2250738585072014e-308';
  Expect.equals(
    double.parse(minNormalStr),
    JsonUtf8Decoder.parseDouble(b(minNormalStr), 0, minNormalStr.length),
  );
  Expect.equals(
    double.parse(minNormalStr),
    JsonUtf8Decoder.tryParseDouble(b(minNormalStr), 0, minNormalStr.length),
  );
  // Max finite double (1.7976931348623157e+308)
  const maxDoubleStr = '1.7976931348623157e+308';
  Expect.equals(
    double.maxFinite,
    JsonUtf8Decoder.parseDouble(b(maxDoubleStr), 0, maxDoubleStr.length),
  );
  Expect.equals(
    double.maxFinite,
    JsonUtf8Decoder.tryParseDouble(b(maxDoubleStr), 0, maxDoubleStr.length),
  );

  // Large / complex exponents (native fallback)
  Expect.equals(1e300, JsonUtf8Decoder.parseDouble(b('1e300'), 0, 5));
  Expect.equals(1e300, JsonUtf8Decoder.tryParseDouble(b('1e300'), 0, 5));
  Expect.equals(1e-300, JsonUtf8Decoder.parseDouble(b('1e-300'), 0, 6));
  Expect.equals(1e-300, JsonUtf8Decoder.tryParseDouble(b('1e-300'), 0, 6));
  Expect.equals(1e308, JsonUtf8Decoder.parseDouble(b('1e308'), 0, 5));
  Expect.equals(1e308, JsonUtf8Decoder.tryParseDouble(b('1e308'), 0, 5));
  Expect.equals(1e-308, JsonUtf8Decoder.parseDouble(b('1e-308'), 0, 6));
  Expect.equals(1e-308, JsonUtf8Decoder.tryParseDouble(b('1e-308'), 0, 6));

  // Exact 17-digit precision double
  const preciseStr = '0.12345678901234567';
  Expect.equals(
    double.parse(preciseStr),
    JsonUtf8Decoder.parseDouble(b(preciseStr), 0, preciseStr.length),
  );
  Expect.equals(
    double.parse(preciseStr),
    JsonUtf8Decoder.tryParseDouble(b(preciseStr), 0, preciseStr.length),
  );

  // Negative zero
  final negZero = JsonUtf8Decoder.parseDouble(b('-0.0'), 0, 4);
  Expect.equals(0.0, negZero);
  Expect.isTrue(negZero.isNegative);
  final negZeroTry = JsonUtf8Decoder.tryParseDouble(b('-0.0'), 0, 4);
  Expect.isNotNull(negZeroTry);
  Expect.equals(0.0, negZeroTry!);
  Expect.isTrue(negZeroTry.isNegative);

  final negZeroInt = JsonUtf8Decoder.parseDouble(b('-0'), 0, 2);
  Expect.equals(0.0, negZeroInt);
  Expect.isTrue(negZeroInt.isNegative);
  final negZeroIntTry = JsonUtf8Decoder.tryParseDouble(b('-0'), 0, 2);
  Expect.isNotNull(negZeroIntTry);
  Expect.equals(0.0, negZeroIntTry!);
  Expect.isTrue(negZeroIntTry.isNegative);

  // Whitespace around double in byte span
  Expect.equals(42.5, JsonUtf8Decoder.parseDouble(b('  42.5  '), 0, 8));
  Expect.equals(42.5, JsonUtf8Decoder.tryParseDouble(b('  42.5  '), 0, 8));

  // Subslice bounds
  final containerBytes = b('{"key": 3.14159, "other": 100}');
  Expect.equals(3.14159, JsonUtf8Decoder.parseDouble(containerBytes, 8, 15));
  Expect.equals(3.14159, JsonUtf8Decoder.tryParseDouble(containerBytes, 8, 15));

  // Invalid doubles
  const invalidDoubles = [
    'abc',
    '',
    '  ',
    '1.',
    '.5',
    '+1.0',
    '--1.0',
    '1e',
    '1e+',
    '1e-',
    '0123',
    'NaN',
    'Infinity',
    '-Infinity',
  ];
  for (final inv in invalidDoubles) {
    Expect.isNull(
      JsonUtf8Decoder.tryParseDouble(b(inv), 0, inv.length),
      'Expected tryParseDouble to return null for $inv',
    );
    Expect.throwsFormatException(
      () => JsonUtf8Decoder.parseDouble(b(inv), 0, inv.length),
      'Expected parseDouble to throw FormatException for $inv',
    );
  }
}

void testBufferPoolSinkWriters() {
  // Short string <= 64 bytes
  final shortSink = BytesBuilder();
  JsonUtf8Encoder.writeString('hello world', shortSink);
  Expect.equals('"hello world"', utf8.decode(shortSink.takeBytes()));

  // Medium string <= 256 bytes
  final medSink = BytesBuilder();
  final medStr = 'a' * 100;
  JsonUtf8Encoder.writeString(medStr, medSink);
  Expect.equals('"$medStr"', utf8.decode(medSink.takeBytes()));

  // Large string > 256 bytes
  final largeSink = BytesBuilder();
  final largeStr = 'b' * 1000;
  JsonUtf8Encoder.writeString(largeStr, largeSink);
  Expect.equals('"$largeStr"', utf8.decode(largeSink.takeBytes()));

  // Double formatting into sink
  final dSink = BytesBuilder();
  JsonUtf8Encoder.writeDouble(123.456, dSink);
  Expect.equals('123.456', utf8.decode(dSink.takeBytes()));

  // Non-copying builder (BytesBuilder(copy: false)) multiple writes
  {
    final nonCopySink = BytesBuilder(copy: false);
    JsonUtf8Encoder.writeString('alpha', nonCopySink);
    JsonUtf8Encoder.writeString('beta', nonCopySink);
    JsonUtf8Encoder.writeDouble(1.25, nonCopySink);
    JsonUtf8Encoder.writeDouble(99.5, nonCopySink);
    final combined = utf8.decode(nonCopySink.takeBytes());
    Expect.equals('"alpha""beta"1.2599.5', combined);
  }

  // Non-copying builder single write and subsequent mutation check
  {
    final nonCopySink1 = BytesBuilder(copy: false);
    JsonUtf8Encoder.writeString('first', nonCopySink1);
    final bytes1 = nonCopySink1.takeBytes();
    Expect.equals('"first"', utf8.decode(bytes1));

    // A second write to another sink or same sink must not mutate bytes1
    final nonCopySink2 = BytesBuilder(copy: false);
    JsonUtf8Encoder.writeString('second_longer_string', nonCopySink2);
    Expect.equals('"first"', utf8.decode(bytes1));
  }
}

void testLeadingFractionalZerosPrecision() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Numbers with many leading fractional zeros
  final testCases = <String, double>{
    '0.0000000000000000123': 1.23e-17,
    '0.000000000000000123': 1.23e-16,
    '0.000000000000000000123': 1.23e-19,
    '0.00000123456789': 0.00000123456789,
    '0.000000000000001': 1e-15,
    '0.0000000000000001': 1e-16,
    '0.00000000000000001': 1e-17,
    '-0.0000000000000000123': -1.23e-17,
    '0.0000000000000000000001': 1e-22,
    '0.00000000000000000000001': 1e-23,
    '0.0000000000000000123e2': 1.23e-15,
    '0.0000000000000000123e-2': 1.23e-19,
    '0.000000000000000000000000000001': 1e-30,
    '0.000000000000000000000000000000': 0.0,
    '-0.000000000000000000000000000000': -0.0,
    '0.00000000000000001234567890123456789e-200': 1.2345678901234568e-217,
    '0.000000000000000000000000000000e50': 0.0,
    '10.0000000000000000123': 10.0000000000000000123,
    '1.000000000000000000000000000001': 1.0,
  };

  for (final entry in testCases.entries) {
    final bytes = b(entry.key);
    final expected = entry.value;
    final parsed = JsonUtf8Decoder.parseDouble(bytes, 0, bytes.length);
    Expect.equals(expected, parsed, 'parseDouble failed for ${entry.key}');
    final tryParsed = JsonUtf8Decoder.tryParseDouble(bytes, 0, bytes.length);
    Expect.isNotNull(
      tryParsed,
      'tryParseDouble returned null for ${entry.key}',
    );
    Expect.equals(
      expected,
      tryParsed!,
      'tryParseDouble failed for ${entry.key}',
    );

    // Negative zero sign bit check
    if (expected == 0.0 && expected.isNegative) {
      Expect.isTrue(
        parsed.isNegative,
        'parseDouble sign bit mismatch for ${entry.key}',
      );
      Expect.isTrue(
        tryParsed.isNegative,
        'tryParseDouble sign bit mismatch for ${entry.key}',
      );
    }

    // Full JSON decode
    final jsonDoc = b('{"val": ${entry.key}}');
    final decoded = jsonUtf8Decode(jsonDoc) as Map<String, dynamic>;
    Expect.equals(
      expected,
      decoded['val'] as double,
      'jsonUtf8Decode failed for ${entry.key}',
    );
  }
}

void testReentrantSinkWriters() {
  final outerSink = BytesBuilder(copy: false);
  final innerSink = BytesBuilder(copy: false);

  JsonUtf8Encoder.writeString('outer_start', outerSink);
  JsonUtf8Encoder.writeString('inner_string', innerSink);
  JsonUtf8Encoder.writeDouble(42.5, innerSink);
  JsonUtf8Encoder.writeDouble(100.125, outerSink);

  Expect.equals('"outer_start"100.125', utf8.decode(outerSink.takeBytes()));
  Expect.equals('"inner_string"42.5', utf8.decode(innerSink.takeBytes()));

  // Interleaved writeDouble calls on separate non-copying sinks
  final sinks = List.generate(5, (_) => BytesBuilder(copy: false));
  for (var i = 0; i < 5; i++) {
    JsonUtf8Encoder.writeDouble(i * 1.5 + 0.25, sinks[i]);
  }
  for (var i = 0; i < 5; i++) {
    Expect.equals('${i * 1.5 + 0.25}', utf8.decode(sinks[i].takeBytes()));
  }

  // Nested recursive multi-level writes
  final b1 = BytesBuilder(copy: false);
  JsonUtf8Encoder.writeString('level1', b1);
  final b2 = BytesBuilder(copy: false);
  JsonUtf8Encoder.writeString('level2', b2);
  JsonUtf8Encoder.writeDouble(2.5, b2);
  final b3 = BytesBuilder(copy: false);
  JsonUtf8Encoder.writeString('level3', b3);
  JsonUtf8Encoder.writeDouble(3.75, b3);

  JsonUtf8Encoder.writeDouble(1.25, b1);
  b1.add(b2.takeBytes());
  b1.add(b3.takeBytes());

  Expect.equals(
    '"level1"1.25"level2"2.5"level3"3.75',
    utf8.decode(b1.takeBytes()),
  );
}

void testDecoderSkipValue64LevelsMixedContainers() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // 1. Exact 31-level nested containers: {"a":[{"b":...}]}
  var json31 = '';
  for (var i = 0; i < 15; i++) {
    json31 += '{"k":[';
  }
  json31 += '{"k": 1}'; // 31 levels
  for (var i = 0; i < 15; i++) {
    json31 += ']}';
  }
  final bytes31 = b(json31);
  Expect.equals(bytes31.length, JsonUtf8Decoder.skipValue(bytes31, 0));

  // 2. Exact 32-level nested containers: 16 pairs of {"k":[
  var json32 = '';
  for (var i = 0; i < 16; i++) {
    json32 += '{"k":[';
  }
  json32 += '42';
  for (var i = 0; i < 16; i++) {
    json32 += ']}';
  }
  final bytes32 = b(json32);
  Expect.equals(bytes32.length, JsonUtf8Decoder.skipValue(bytes32, 0));

  // 3. Exact 33-level nested containers
  var json33 = '';
  for (var i = 0; i < 16; i++) {
    json33 += '{"k":[';
  }
  json33 += '{"k": 1}'; // 33 levels
  for (var i = 0; i < 16; i++) {
    json33 += ']}';
  }
  final bytes33 = b(json33);
  Expect.equals(bytes33.length, JsonUtf8Decoder.skipValue(bytes33, 0));

  // 4. Exact 63-level nested containers
  var json63 = '';
  for (var i = 0; i < 31; i++) {
    json63 += '{"k":[';
  }
  json63 += '{"k": 1}'; // 63 levels
  for (var i = 0; i < 31; i++) {
    json63 += ']}';
  }
  final bytes63 = b(json63);
  Expect.equals(bytes63.length, JsonUtf8Decoder.skipValue(bytes63, 0));

  // 5. 64-level alternating objects and arrays: {"a":[{"b":[{"c":...}]}]}
  var deepJson = '';
  for (var i = 0; i < 32; i++) {
    deepJson += '{"k":[';
  }
  deepJson += '42';
  for (var i = 0; i < 32; i++) {
    deepJson += ']}';
  }
  final deepBytes = b(deepJson);
  final endOffset = JsonUtf8Decoder.skipValue(deepBytes, 0);
  Expect.equals(deepBytes.length, endOffset);

  // 6. Mismatched closing brace '}' at depth 31 (closing an array)
  var mismatch31 = '';
  for (var i = 0; i < 15; i++) {
    mismatch31 += '{"k":['; // 30 levels
  }
  mismatch31 += '['; // 31st level: array
  mismatch31 += '}'; // Wrong delimiter '}'
  for (var i = 0; i < 15; i++) {
    mismatch31 += ']}';
  }
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b(mismatch31), 0),
  );

  // 7. Mismatched closing brace '}' at depth 32 (closing an array)
  var mismatch32 = '';
  for (var i = 0; i < 15; i++) {
    mismatch32 += '{"k":['; // 30 levels
  }
  mismatch32 += '{"k":['; // 32nd level: array
  mismatch32 += '}'; // Wrong delimiter '}'
  for (var i = 0; i < 15; i++) {
    mismatch32 += ']}';
  }
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b(mismatch32), 0),
  );

  // 8. Mismatched closing brace '}' at depth 33 (closing an array)
  var mismatch33 = '';
  for (var i = 0; i < 16; i++) {
    mismatch33 += '{"k":['; // 32 levels
  }
  mismatch33 += '['; // 33rd level: array
  mismatch33 += '}'; // Wrong delimiter '}'
  for (var i = 0; i < 16; i++) {
    mismatch33 += ']}';
  }
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b(mismatch33), 0),
  );

  // 9. Mismatched closing bracket ']' at depth 33 (closing an object)
  var mismatch34 = '';
  for (var i = 0; i < 16; i++) {
    mismatch34 += '{"k":['; // 32 levels
  }
  mismatch34 += '{"k": 1]'; // 33rd level object closed with ']'
  for (var i = 0; i < 16; i++) {
    mismatch34 += ']}';
  }
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(b(mismatch34), 0),
  );

  // 10. Depth 65 exceeds max depth limit
  var deep65 = '';
  for (var i = 0; i < 32; i++) {
    deep65 += '{"k":[';
  }
  deep65 += '{"k": 1}'; // 65th level
  for (var i = 0; i < 32; i++) {
    deep65 += ']}';
  }
  Expect.throwsFormatException(() => JsonUtf8Decoder.skipValue(b(deep65), 0));
}

void testZeroAllocationKeySlicing() {
  final buf = Uint8List(128);

  // 1. Colon-terminated pre-quoted key: '"id":'
  final key1 = Uint8List.fromList(utf8.encode('"id":'));
  var len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buf,
    0,
    key1,
    isFirst: true,
  );
  Expect.equals(5, len);
  Expect.equals('"id":', utf8.decode(buf.sublist(0, len)));

  // Not first property: comma prepended
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buf,
    0,
    key1,
    isFirst: false,
  );
  Expect.equals(6, len);
  Expect.equals(',"id":', utf8.decode(buf.sublist(0, len)));

  // 2. Colon-terminated empty string key: '"":'
  final keyEmpty = Uint8List.fromList(utf8.encode('"":'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buf,
    0,
    keyEmpty,
    isFirst: true,
  );
  Expect.equals(3, len);
  Expect.equals('"":', utf8.decode(buf.sublist(0, len)));

  // 3. Colon-terminated key with escape sequence: '"escaped\\nfield":'
  final keyEsc = Uint8List.fromList(utf8.encode(r'"escaped\nfield":'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buf,
    0,
    keyEsc,
    isFirst: true,
  );
  Expect.equals(keyEsc.length, len);
  Expect.equals(r'"escaped\nfield":', utf8.decode(buf.sublist(0, len)));

  // 4. Colon-terminated key with unicode escape: '"\u0020":'
  final keyUnicode = Uint8List.fromList(utf8.encode(r'"\u0020":'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buf,
    0,
    keyUnicode,
    isFirst: true,
  );
  Expect.equals(keyUnicode.length, len);
  Expect.equals(r'"\u0020":', utf8.decode(buf.sublist(0, len)));

  // 5. Colon-terminated key with escaped quote: '"\"":'
  final keyQuote = Uint8List.fromList(utf8.encode(r'"\"":'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buf,
    0,
    keyQuote,
    isFirst: true,
  );
  Expect.equals(keyQuote.length, len);
  Expect.equals(r'"\"":', utf8.decode(buf.sublist(0, len)));

  // 6. Pre-quoted key without colon: '"id"' -> quotes preserved, colon appended
  final keyNoColon = Uint8List.fromList(utf8.encode('"id"'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buf,
    0,
    keyNoColon,
    isFirst: true,
  );
  Expect.equals(5, len);
  Expect.equals('"id":', utf8.decode(buf.sublist(0, len)));

  // 7. Raw unquoted key: 'id' -> quotes added, colon appended
  final keyRaw = Uint8List.fromList(utf8.encode('id'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buf,
    0,
    keyRaw,
    isFirst: true,
  );
  Expect.equals(5, len);
  Expect.equals('"id":', utf8.decode(buf.sublist(0, len)));
}

void testSkipValueInvalidEscapes() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Valid escapes should succeed
  final valid = [
    r'"\""',
    r'"\\"',
    r'"\/"',
    r'"\b"',
    r'"\f"',
    r'"\n"',
    r'"\r"',
    r'"\t"',
    r'"\u0000"',
    r'"\uFFFF"',
    r'"\u12ab"',
    r'"\uCDEF"',
    r'"hello \n world \t \" \\ \/ \b \f \r \u1234 done"',
  ];
  for (final s in valid) {
    final bytes = b(s);
    Expect.equals(bytes.length, JsonUtf8Decoder.skipString(bytes, 0));
    Expect.equals(bytes.length, JsonUtf8Decoder.skipValue(bytes, 0));
  }

  // Invalid escapes in skipString
  final invalidStrings = [
    r'"\z"',
    r'"\0"',
    r'"\a"',
    r'"\1"',
    r'"\x20"',
    r'"\u12"',
    r'"\u"',
    r'"\u123"',
    r'"\u12g4"',
    r'"\u123Z"',
    r'"\u12 4"',
  ];
  for (final s in invalidStrings) {
    final bytes = b(s);
    Expect.throwsFormatException(
      () => JsonUtf8Decoder.skipString(bytes, 0),
      'skipString should reject $s',
    );
    Expect.throwsFormatException(
      () => JsonUtf8Decoder.skipValue(bytes, 0),
      'skipValue should reject scalar string $s',
    );
  }

  // Unterminated backslash at EOF in skipString and skipValue
  final unterminatedEscape = Uint8List.fromList([0x22, 0x5C]); // '"\'
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipString(unterminatedEscape, 0),
  );
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(unterminatedEscape, 0),
  );

  // Invalid escapes inside objects and arrays for skipValue
  final invalidContainers = [
    r'{"key": "\z"}',
    r'{"k\z": 1}',
    r'{"a": "\u12"}',
    r'{"a": "\u12g4"}',
    r'{"a": "\0"}',
    r'["\z"]',
    r'["\0"]',
    r'["\a"]',
    r'["\u12"]',
    r'["\u123G"]',
    r'[1, 2, {"nested": ["valid", "\z"]}]',
  ];
  for (final c in invalidContainers) {
    final bytes = b(c);
    Expect.throwsFormatException(
      () => JsonUtf8Decoder.skipValue(bytes, 0),
      'skipValue should reject invalid escape in container $c',
    );
  }

  // Unterminated backslash at EOF in container
  final unterminatedInArray = Uint8List.fromList([0x5B, 0x22, 0x5C]); // '["\'
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(unterminatedInArray, 0),
  );
  final unterminatedInObject = Uint8List.fromList([0x7B, 0x22, 0x5C]); // '{"\'
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.skipValue(unterminatedInObject, 0),
  );
}

void testWebSafeFnv1aHash() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // Reference 16-bit split multiplication producing web-safe 31-bit FNV-1a hash
  int imul32(int a, int b) {
    final aLo = a & 0xffff;
    final aHi = (a >> 16) & 0xffff;
    final bLo = b & 0xffff;
    final bHi = (b >> 16) & 0xffff;
    final lo = aLo * bLo;
    final hi = aLo * bHi + aHi * bLo;
    return ((lo + ((hi & 0xffff) << 16)) & 0x7fffffff);
  }

  // 1. Verify exact 32-bit integer arithmetic behavior on edge cases
  // Multiplications that exceed JS Number.MAX_SAFE_INTEGER (9,007,199,254,740,991)
  Expect.equals(0, imul32(0, 0x01000193));
  Expect.equals(0x01000193, imul32(1, 0x01000193));
  // 0x811c9dc5 * 0x01000193 = 36,342,609,075,723,551 (exceeds 2^53 - 1)
  // Low 32 bits = 0x050c5d1f = 84696351
  Expect.equals(0x050c5d1f, imul32(0x811c9dc5, 0x01000193));

  // 2. Test JsonKeyOptions lookup with various key patterns
  final keyList = [
    'id',
    'type',
    'title',
    'description',
    'active',
    'count',
    'latitude',
    'longitude',
    'created_at',
    'updated_at',
    'user_id',
    'payload',
    'metadata',
    'schema_version',
    'alpha',
    'beta',
    'gamma',
    'delta',
    'epsilon',
    'zeta',
  ];
  final options = JsonKeyOptions.of(keyList);
  Expect.equals(keyList.length, options.length);

  for (var i = 0; i < keyList.length; i++) {
    final keyBytes = b(keyList[i]);
    final matchedIndex = options.selectKey(keyBytes, 0, keyBytes.length);
    Expect.equals(i, matchedIndex, 'Expected key ${keyList[i]} at index $i');
  }

  // Missing keys return -1
  final nonExistent = ['non_existent', 'missing', 'id_extended', 'typ'];
  for (final k in nonExistent) {
    final kb = b(k);
    Expect.equals(-1, options.selectKey(kb, 0, kb.length));
  }

  // 3. Multi-byte and special character keys
  final unicodeKeys = [
    'café',
    'résumé',
    'naïve',
    'über',
    '東京',
    '日本語',
    '🎉',
    '🚀',
    '🔥',
    '🌟',
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
  ];
  final unicodeOptions = JsonKeyOptions.of(unicodeKeys);
  for (var i = 0; i < unicodeKeys.length; i++) {
    final kb = b(unicodeKeys[i]);
    Expect.equals(i, unicodeOptions.selectKey(kb, 0, kb.length));
  }

  // 4. Sublist / offset spans in larger buffers
  final buffer = b('{"title":"test","user_id":123}');
  // "title" starts at index 2, length 5 (indices 2..7)
  Expect.equals(2, options.selectKey(buffer, 2, 7));
  // "user_id" starts at index 17, length 7 (indices 17..24)
  Expect.equals(10, options.selectKey(buffer, 17, 24));
}

void testWriteAsciiAndRawJsonBounds() {
  // 1. writeAsciiLiteralToBuffer
  // Exact fit
  final exactAsciiBuf = Uint8List(3);
  final aLen = JsonUtf8Encoder.writeAsciiLiteralToBuffer(
    Uint8List.fromList([65, 66, 67]),
    exactAsciiBuf,
    0,
  );
  Expect.equals(3, aLen);
  Expect.listEquals([65, 66, 67], exactAsciiBuf);

  // Exact fit at offset
  final offAsciiBuf = Uint8List(10);
  final aLen2 = JsonUtf8Encoder.writeAsciiLiteralToBuffer(
    Uint8List.fromList([65, 66, 67]),
    offAsciiBuf,
    7,
  );
  Expect.equals(3, aLen2);
  Expect.listEquals([65, 66, 67], offAsciiBuf.sublist(7, 10));

  // Negative offset -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeAsciiLiteralToBuffer(
      Uint8List.fromList([65, 66]),
      Uint8List(16),
      -1,
    ),
  );

  // Overflow offset -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeAsciiLiteralToBuffer(
      Uint8List.fromList([65, 66]),
      Uint8List(16),
      15,
    ),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeAsciiLiteralToBuffer(
      Uint8List.fromList([65, 66]),
      Uint8List(16),
      1000,
    ),
  );

  // Undersized and zero-length buffers -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeAsciiLiteralToBuffer(
      Uint8List.fromList([65, 66]),
      Uint8List(0),
      0,
    ),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeAsciiLiteralToBuffer(
      Uint8List.fromList([65, 66, 67]),
      Uint8List(2),
      0,
    ),
  );

  // In-place buffer non-corruption test:
  final asciiBuf = Uint8List.fromList([1, 2, 3, 4, 5]);
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeAsciiLiteralToBuffer(
      Uint8List.fromList([65, 66, 67]),
      asciiBuf,
      3,
    ),
  );
  Expect.listEquals([1, 2, 3, 4, 5], asciiBuf);

  // Empty ascii byte slices:
  final emptyAsciiBuf = Uint8List(5);
  Expect.equals(
    0,
    JsonUtf8Encoder.writeAsciiLiteralToBuffer(Uint8List(0), emptyAsciiBuf, 0),
  );
  Expect.equals(
    0,
    JsonUtf8Encoder.writeAsciiLiteralToBuffer(Uint8List(0), emptyAsciiBuf, 5),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeAsciiLiteralToBuffer(
      Uint8List(0),
      emptyAsciiBuf,
      6,
    ),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeAsciiLiteralToBuffer(
      Uint8List(0),
      emptyAsciiBuf,
      -1,
    ),
  );

  // 2. writeRawJsonToBuffer
  // Exact fit
  final exactRawBuf = Uint8List(3);
  final rLen = JsonUtf8Encoder.writeRawJsonToBuffer(
    Uint8List.fromList([65, 66, 67]),
    exactRawBuf,
    0,
  );
  Expect.equals(3, rLen);
  Expect.listEquals([65, 66, 67], exactRawBuf);

  // Exact fit at offset
  final offRawBuf = Uint8List(10);
  final rLen2 = JsonUtf8Encoder.writeRawJsonToBuffer(
    Uint8List.fromList([65, 66, 67]),
    offRawBuf,
    7,
  );
  Expect.equals(3, rLen2);
  Expect.listEquals([65, 66, 67], offRawBuf.sublist(7, 10));

  // Negative offset -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeRawJsonToBuffer(
      Uint8List.fromList([65, 66]),
      Uint8List(16),
      -1,
    ),
  );

  // Overflow offset -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeRawJsonToBuffer(
      Uint8List.fromList([65, 66]),
      Uint8List(16),
      15,
    ),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeRawJsonToBuffer(
      Uint8List.fromList([65, 66]),
      Uint8List(16),
      1000,
    ),
  );

  // Undersized and zero-length buffers -> RangeError
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeRawJsonToBuffer(
      Uint8List.fromList([65, 66]),
      Uint8List(0),
      0,
    ),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeRawJsonToBuffer(
      Uint8List.fromList([65, 66, 67]),
      Uint8List(2),
      0,
    ),
  );

  // In-place buffer non-corruption test:
  final rawBuf = Uint8List.fromList([1, 2, 3, 4, 5]);
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeRawJsonToBuffer(
      Uint8List.fromList([65, 66, 67]),
      rawBuf,
      3,
    ),
  );
  Expect.listEquals([1, 2, 3, 4, 5], rawBuf);

  // Empty raw byte slices:
  final emptyRawBuf = Uint8List(5);
  Expect.equals(
    0,
    JsonUtf8Encoder.writeRawJsonToBuffer(Uint8List(0), emptyRawBuf, 0),
  );
  Expect.equals(
    0,
    JsonUtf8Encoder.writeRawJsonToBuffer(Uint8List(0), emptyRawBuf, 5),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeRawJsonToBuffer(Uint8List(0), emptyRawBuf, 6),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeRawJsonToBuffer(Uint8List(0), emptyRawBuf, -1),
  );
}

void testMatchKeyEscapedKeys() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final options = JsonKeyOptions.of([
    'id',
    'name',
    'latitude',
    'longitude',
    'type',
    'a"b',
    'café',
    '😀',
  ]);

  // 1. Escaped unicode key: \u0069\u0064 -> 'id' (index 0)
  final escapedId = b(r'{"\u0069\u0064": 1}');
  Expect.equals(0, JsonUtf8Decoder.matchKey(escapedId, 2, 14, options));

  // 2. Escaped unicode key: n\u0061me -> 'name' (index 1)
  final escapedName = b(r'{"n\u0061me": "test"}');
  Expect.equals(1, JsonUtf8Decoder.matchKey(escapedName, 2, 11, options));

  // 3. Escaped quote: a\"b -> 'a"b' (index 5)
  final escapedQuote = b(r'{"a\"b": 100}');
  Expect.equals(5, JsonUtf8Decoder.matchKey(escapedQuote, 2, 6, options));

  // 4. Escaped multi-byte UTF-8: caf\u00e9 -> 'café' (index 6)
  final escapedCafe = b(r'{"caf\u00e9": 200}');
  Expect.equals(6, JsonUtf8Decoder.matchKey(escapedCafe, 2, 11, options));

  // 5. Escaped type: \u0074\u0079\u0070\u0065 -> 'type' (index 4)
  final escapedType = b(r'{"\u0074\u0079\u0070\u0065": "item"}');
  Expect.equals(4, JsonUtf8Decoder.matchKey(escapedType, 2, 26, options));

  // 6. Unknown escaped key: \u0075\u006e\u006b\u006e\u006f\u0077\u006e -> 'unknown' -> returns -1
  final escapedUnknown = b(
    r'{"\u0075\u006e\u006b\u006e\u006f\u0077\u006e": true}',
  );
  Expect.equals(-1, JsonUtf8Decoder.matchKey(escapedUnknown, 2, 44, options));

  // 7. Surrogate pair escaped key: \uD83D\uDE00 -> '😀' (index 7)
  final escapedEmoji = b(r'{"\uD83D\uDE00": 300}');
  Expect.equals(7, JsonUtf8Decoder.matchKey(escapedEmoji, 2, 14, options));

  // 8. Verbatim ASCII keys still match correctly
  final verbatimSrc = b('{"id": 1, "name": "test", "latitude": 37.77}');
  Expect.equals(0, JsonUtf8Decoder.matchKey(verbatimSrc, 2, 4, options));
  Expect.equals(1, JsonUtf8Decoder.matchKey(verbatimSrc, 11, 15, options));
  Expect.equals(2, JsonUtf8Decoder.matchKey(verbatimSrc, 27, 35, options));

  // 9. Unescaped multi-byte UTF-8 key ('café') matches correctly
  final utf8Cafe = b('{"café": 200}');
  Expect.equals(6, JsonUtf8Decoder.matchKey(utf8Cafe, 2, 7, options));

  // 10. Malformed UTF-8 byte span throws FormatException
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.matchKey(Uint8List.fromList([0xFF]), 0, 1, options),
  );

  // 11. Invalid escape sequence throws FormatException
  Expect.throwsFormatException(
    () => JsonUtf8Decoder.matchKey(b(r'\u123z'), 0, 6, options),
  );
}

void testDirectSinkFormatterStress() {
  // 1. Stress test writeDouble across varied float types into BytesBuilder
  final doubleSink = BytesBuilder();
  final testDoubles = [
    0.0,
    -0.0,
    1.0,
    -1.0,
    123.456,
    -987.654,
    3.141592653589793,
    1e10,
    -1e10,
    1.23456789e-20,
    2.2250738585072014e-308,
    1.7976931348623157e308,
  ];

  for (final d in testDoubles) {
    final singleSink = BytesBuilder();
    JsonUtf8Encoder.writeDouble(d, singleSink);
    final expected = utf8.encode(jsonEncode(d));
    Expect.listEquals(
      expected,
      singleSink.takeBytes(),
      'Mismatch formatting double $d',
    );
  }

  for (var i = 0; i < 1000; i++) {
    for (final d in testDoubles) {
      JsonUtf8Encoder.writeDouble(d, doubleSink);
      doubleSink.addByte(0x0A); // '\n'
    }
  }
  final doubleLines = utf8.decode(doubleSink.takeBytes()).trim().split('\n');
  Expect.equals(1000 * testDoubles.length, doubleLines.length);

  // 2. Stress test writeString across varied strings into BytesBuilder
  final strSink = BytesBuilder();
  final testStrings = [
    '',
    'a',
    'hello world',
    'escaped "quotes" and \\backslashes\\',
    'ctrl\x00\x01\x1fchars',
    'line\nbreak\ttab\rreturn\fform\bback',
    'café résumé naïve über',
    '東京 日本語 中文 한국어 €',
    '🚀 😀 🎉 🐱‍👤',
    'isolated \uD800 high',
    'isolated \uDC00 low',
    'paired \uD83D\uDE00 emoji',
    'a' * 500,
    'é' * 200,
  ];

  for (final s in testStrings) {
    final singleSink = BytesBuilder();
    JsonUtf8Encoder.writeString(s, singleSink);
    final expected = utf8.encode(jsonEncode(s));
    Expect.listEquals(
      expected,
      singleSink.takeBytes(),
      'Mismatch formatting string: $s',
    );
  }

  // Also verify with BytesBuilder(copy: false)
  final noCopySink = BytesBuilder(copy: false);
  for (final s in testStrings) {
    JsonUtf8Encoder.writeString(s, noCopySink);
    noCopySink.addByte(0x0A);
  }
  final noCopyLines = utf8.decode(noCopySink.takeBytes()).trim().split('\n');
  Expect.equals(testStrings.length, noCopyLines.length);

  for (var i = 0; i < 500; i++) {
    for (final s in testStrings) {
      JsonUtf8Encoder.writeString(s, strSink);
      strSink.addByte(0x0A); // '\n'
    }
  }
  final strLines = utf8.decode(strSink.takeBytes()).trim().split('\n');
  Expect.equals(500 * testStrings.length, strLines.length);

  // 3. Verify non-finite doubles throw ArgumentError in writeDouble
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDouble(double.nan, BytesBuilder()),
  );
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDouble(double.infinity, BytesBuilder()),
  );
  Expect.throwsArgumentError(
    () => JsonUtf8Encoder.writeDouble(double.negativeInfinity, BytesBuilder()),
  );

  // 4. Verify JsonKeyOptions web-safe FNV-1a hash matching
  final testKeys = [
    'a',
    'b',
    'c',
    'id',
    'name',
    'value',
    'type',
    'status',
    'created_at',
    'updated_at',
    'deleted_at',
    'café',
    'résumé',
    '東京',
    '🚀',
    'key_with_many_characters_to_test_hash_accumulation_over_32_bits_0123456789',
  ];
  final opt = JsonKeyOptions.of(testKeys);
  for (var i = 0; i < testKeys.length; i++) {
    final keyBytes = Uint8List.fromList(utf8.encode(testKeys[i]));
    Expect.equals(i, opt.selectKey(keyBytes, 0, keyBytes.length));
  }

  // Out of bounds queries to selectKey
  final sampleBytes = Uint8List.fromList(utf8.encode('created_at'));
  Expect.equals(-1, opt.selectKey(sampleBytes, -1, 5));
  Expect.equals(-1, opt.selectKey(sampleBytes, 5, 4));
  Expect.equals(-1, opt.selectKey(sampleBytes, 0, 100));
}

void testWholeCodebaseBoundsAndSentinels() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  final sample = b('{"key": [1, 2, 3], "nested": {"a": "b"}}');
  final options = JsonKeyOptions.of(['key', 'nested', 'a', 'b']);

  // 1. JsonUtf8Decoder.skipWhitespace bounds
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipWhitespace(sample, -1));
  Expect.throwsRangeError(
    () => JsonUtf8Decoder.skipWhitespace(sample, sample.length + 1),
  );
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipWhitespace(sample, 100));
  Expect.equals(
    sample.length,
    JsonUtf8Decoder.skipWhitespace(sample, sample.length),
  );

  final empty = Uint8List(0);
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipWhitespace(empty, -1));
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipWhitespace(empty, 1));
  Expect.equals(0, JsonUtf8Decoder.skipWhitespace(empty, 0));

  // 2. JsonUtf8Decoder.skipString bounds
  final strBytes = b('"hello world" rest');
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipString(strBytes, -1));
  Expect.throwsRangeError(
    () => JsonUtf8Decoder.skipString(strBytes, strBytes.length),
  );
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipString(strBytes, 100));
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipString(empty, 0));

  // 3. JsonUtf8Decoder.skipValue bounds
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipValue(sample, -1));
  Expect.throwsRangeError(
    () => JsonUtf8Decoder.skipValue(sample, sample.length + 1),
  );
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipValue(sample, 100));
  Expect.equals(
    sample.length,
    JsonUtf8Decoder.skipValue(sample, sample.length),
  );
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipValue(empty, -1));
  Expect.throwsRangeError(() => JsonUtf8Decoder.skipValue(empty, 1));
  Expect.equals(0, JsonUtf8Decoder.skipValue(empty, 0));

  // 4. JsonUtf8Decoder.matchKey bounds & sentinels
  Expect.equals(-1, JsonUtf8Decoder.matchKey(sample, -1, 5, options));
  Expect.equals(-1, JsonUtf8Decoder.matchKey(sample, 5, 2, options));
  Expect.equals(-1, JsonUtf8Decoder.matchKey(sample, 0, 100, options));
  Expect.equals(-1, JsonUtf8Decoder.matchKey(sample, -5, -2, options));
  Expect.equals(
    -1,
    JsonUtf8Decoder.matchKey(sample, 2, sample.length + 10, options),
  );
  Expect.equals(0, JsonUtf8Decoder.matchKey(sample, 2, 5, options)); // 'key'

  // 5. JsonUtf8Decoder.decodeString bounds & empty slice precedence
  Expect.throwsRangeError(() => JsonUtf8Decoder.decodeString(sample, -1, -1));
  Expect.throwsRangeError(() => JsonUtf8Decoder.decodeString(sample, 100, 100));
  Expect.throwsRangeError(() => JsonUtf8Decoder.decodeString(sample, -5, -2));
  Expect.throwsRangeError(() => JsonUtf8Decoder.decodeString(sample, 5, 2));
  Expect.throwsRangeError(() => JsonUtf8Decoder.decodeString(sample, 0, 100));
  Expect.equals('', JsonUtf8Decoder.decodeString(sample, 0, 0));
  Expect.equals('', JsonUtf8Decoder.decodeString(sample, 2, 2));
  Expect.equals(
    '',
    JsonUtf8Decoder.decodeString(sample, sample.length, sample.length),
  );

  // 6. JsonUtf8Encoder.writeDoubleToBuffer bounds
  final buf = Uint8List(20);
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeDoubleToBuffer(3.14159, buf, -1),
  );
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeDoubleToBuffer(3.14159, buf, 100),
  );
  // Complex float fallback path (subnormal / extreme exponent)
  Expect.throwsRangeError(
    () => JsonUtf8Encoder.writeDoubleToBuffer(1.2345678901234567e-100, buf, -1),
  );
  Expect.throwsRangeError(
    () =>
        JsonUtf8Encoder.writeDoubleToBuffer(1.2345678901234567e-100, buf, 100),
  );
}

void testTypedDataViewsNative() {
  // 1. JsonUtf8Decoder.parseDouble with Uint8List.view and sublistView
  // (Fast-path number)
  final rawBytes = utf8.encode('   {"val": 3.14159265, "extra": 42}   ');
  final byteBuffer = Uint8List.fromList(rawBytes).buffer;
  final view = Uint8List.view(
    byteBuffer,
    3,
    27,
  ); // '{"val": 3.14159265, "extra": 42}'
  final parsed = JsonUtf8Decoder.parseDouble(view, 8, 18);
  Expect.equals(3.14159265, parsed);

  final subview = Uint8List.sublistView(Uint8List.fromList(rawBytes), 3, 30);
  final parsedSub = JsonUtf8Decoder.parseDouble(subview, 8, 18);
  Expect.equals(3.14159265, parsedSub);

  // (C++ Native Fallback: extreme exponents and > 15 decimal digits)
  final extremeBytes = utf8.encode(
    '{"exp": 1.2345678901234567e-30, "max": 1.7976931348623157e+308}',
  );
  final extremeBuf = Uint8List.fromList(extremeBytes).buffer;
  // Unaligned byte offset (3) for view
  final unalignedView = Uint8List.view(extremeBuf, 3, extremeBytes.length - 3);
  // '1.2345678901234567e-30' is at index 5 in unalignedView (index 8 in extremeBytes)
  final parsedExtreme = JsonUtf8Decoder.parseDouble(unalignedView, 5, 27);
  Expect.equals(1.2345678901234567e-30, parsedExtreme);

  final parsedMax = JsonUtf8Decoder.parseDouble(unalignedView, 36, 59);
  Expect.equals(1.7976931348623157e+308, parsedMax);

  // 2. JsonUtf8Encoder.writeDoubleToBuffer with Uint8List.view and sublistView
  final backingBuffer = Uint8List(128).buffer;
  final destView = Uint8List.view(backingBuffer, 32, 64);
  final writtenLen = JsonUtf8Encoder.writeDoubleToBuffer(
    2.718281828,
    destView,
    10,
  );
  Expect.isTrue(writtenLen > 0);
  Expect.equals(
    '2.718281828',
    utf8.decode(destView.sublist(10, 10 + writtenLen)),
  );

  // C++ Native Fallback with unaligned offset in view
  final unalignedDest = Uint8List.view(backingBuffer, 3, 90);
  final writtenLenFallback = JsonUtf8Encoder.writeDoubleToBuffer(
    1.2345678901234567e-100,
    unalignedDest,
    5,
  );
  Expect.isTrue(writtenLenFallback > 0);
  final decodedFallback = double.parse(
    utf8.decode(unalignedDest.sublist(5, 5 + writtenLenFallback)),
  );
  Expect.equals(1.2345678901234567e-100, decodedFallback);

  final destSubView = Uint8List.sublistView(Uint8List(128), 16, 80);
  final writtenLenSub = JsonUtf8Encoder.writeDoubleToBuffer(
    2.718281828,
    destSubView,
    8,
  );
  Expect.isTrue(writtenLenSub > 0);
  Expect.equals(
    '2.718281828',
    utf8.decode(destSubView.sublist(8, 8 + writtenLenSub)),
  );

  // 3. JsonUtf8Encoder.writeStringToBuffer with Uint8List.view and sublistView
  final strBacking = Uint8List(512).buffer;
  final strView = Uint8List.view(strBacking, 32, 256);
  // Short string fast path (<= 16 chars)
  final sLen1 = JsonUtf8Encoder.writeStringToBuffer('hello_view', strView, 5);
  Expect.equals(12, sLen1); // '"hello_view"' = 12 bytes
  Expect.equals('"hello_view"', utf8.decode(strView.sublist(5, 5 + sLen1)));

  // Long string SIMD path (> 16 chars)
  final longStr =
      'this_is_a_very_long_string_designed_to_hit_the_native_simd_code_path';
  final sLen2 = JsonUtf8Encoder.writeStringToBuffer(longStr, strView, 20);
  Expect.equals(longStr.length + 2, sLen2);
  Expect.equals('"$longStr"', utf8.decode(strView.sublist(20, 20 + sLen2)));

  // Non-ASCII and Escaped Unicode string on unaligned view (C++ TwoByteString native path)
  final unalignedStrView = Uint8List.view(strBacking, 7, 300);
  final unicodeStr = 'hello "world" \n \u0000 \u20AC 🚀';
  final sLenUnicode = JsonUtf8Encoder.writeStringToBuffer(
    unicodeStr,
    unalignedStrView,
    11,
  );
  Expect.isTrue(sLenUnicode > 0);
  final decodedUnicodeJson = jsonDecode(
    utf8.decode(unalignedStrView.sublist(11, 11 + sLenUnicode)),
  );
  Expect.equals(unicodeStr, decodedUnicodeJson);

  // Sliced sublistView
  final strSubView = Uint8List.sublistView(Uint8List(256), 16, 160);
  final sLenSub = JsonUtf8Encoder.writeStringToBuffer(longStr, strSubView, 10);
  Expect.equals(longStr.length + 2, sLenSub);
  Expect.equals(
    '"$longStr"',
    utf8.decode(strSubView.sublist(10, 10 + sLenSub)),
  );
}

void testJsonKeyOptionsStressAndCollisions() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // 1. 1000+ keys scaling and collision stress
  final thousandKeys = List.generate(1200, (i) => 'stress_test_field_key_$i');
  final thousandOptions = JsonKeyOptions.of(thousandKeys);
  Expect.equals(1200, thousandOptions.length);
  for (var i = 0; i < 1200; i++) {
    final kb = b(thousandKeys[i]);
    Expect.equals(i, thousandOptions.selectKey(kb, 0, kb.length));
  }
  // Verify missing key in large set
  final notPresent = b('stress_test_field_key_9999');
  Expect.equals(
    -1,
    thousandOptions.selectKey(notPresent, 0, notPresent.length),
  );

  // 2. Prefix collision chains (e.g. "p", "pr", "pre", "pref", "prefix", ...)
  final prefixKeys = [
    'p',
    'pr',
    'pre',
    'pref',
    'prefi',
    'prefix',
    'prefix_',
    'prefix_k',
    'prefix_ke',
    'prefix_key',
    'prefix_key_1',
    'prefix_key_12',
    'prefix_key_123',
  ];
  final prefixOptions = JsonKeyOptions.of(prefixKeys);
  for (var i = 0; i < prefixKeys.length; i++) {
    final pk = b(prefixKeys[i]);
    Expect.equals(i, prefixOptions.selectKey(pk, 0, pk.length));
  }
  // Prefix not in set
  final prefixMissing = b('prefix_key_1234');
  Expect.equals(
    -1,
    prefixOptions.selectKey(prefixMissing, 0, prefixMissing.length),
  );

  // 3. Similar keys with differing single characters
  final similarKeys = [
    'test_var_alpha',
    'test_var_alphb',
    'test_var_alphc',
    'west_var_alpha',
    'zest_var_alpha',
    'test_bar_alpha',
    'test_car_alpha',
  ];
  final similarOptions = JsonKeyOptions.of(similarKeys);
  for (var i = 0; i < similarKeys.length; i++) {
    final sk = b(similarKeys[i]);
    Expect.equals(i, similarOptions.selectKey(sk, 0, sk.length));
  }
}

void testMatchKeySurrogatesAndPathologicalKeys() {
  Uint8List b(String s) => Uint8List.fromList(utf8.encode(s));

  // 1. Surrogate pair unescaping in matchKey
  final emojiOptions = JsonKeyOptions.of(['id', '😀', 'rocket_🚀', 'simple']);
  // UTF-8 payload containing literal emoji
  final literalPayload = b('{"😀": 123}');
  Expect.equals(
    1,
    JsonUtf8Decoder.matchKey(literalPayload, 2, 6, emojiOptions),
  );

  // JSON payload containing escaped surrogate pair \uD83D\uDE00
  final escapedPayload = b(r'{"\uD83D\uDE00": 123}');
  Expect.equals(
    1,
    JsonUtf8Decoder.matchKey(escapedPayload, 2, 14, emojiOptions),
  );

  // Escaped rocket emoji \uD83D\uDE80
  final rocketEscaped = b(r'{"rocket_\uD83D\uDE80": 456}');
  Expect.equals(
    2,
    JsonUtf8Decoder.matchKey(rocketEscaped, 2, 21, emojiOptions),
  );

  // 2. Standard escape sequences in keys
  final escapeOptions = JsonKeyOptions.of([
    'hello "world"',
    'key\nwith\nnewlines',
    'key\twith\ttabs',
    'path/with/slash',
    'path\\with\\backslash',
  ]);
  final srcEscapes = b(
    r'{"hello \"world\"": 1, "key\nwith\nnewlines": 2, "key\twith\ttabs": 3, "path\/with\/slash": 4, "path\\with\\backslash": 5}',
  );
  final r = JsonTokenReader.fromBytes(srcEscapes);
  r.beginObject();
  var count = 0;
  while (r.hasNext()) {
    final name = r.nextName();
    final idx = escapeOptions.selectKey(b(name), 0, utf8.encode(name).length);
    Expect.equals(count, idx);
    r.skipValue();
    count++;
  }
  r.endObject();
  Expect.equals(5, count);

  // 3. Pathological and boundary keys
  final pathOptions = JsonKeyOptions.of([
    '',
    ' ',
    '  ',
    '\x00',
    'null',
    'true',
    'false',
    '0',
    '-1',
  ]);
  Expect.equals(9, pathOptions.length);
  Expect.equals(0, pathOptions.selectKey(b(''), 0, 0));
  Expect.equals(1, pathOptions.selectKey(b(' '), 0, 1));
  Expect.equals(2, pathOptions.selectKey(b('  '), 0, 2));
  Expect.equals(3, pathOptions.selectKey(Uint8List.fromList([0x00]), 0, 1));
  Expect.equals(4, pathOptions.selectKey(b('null'), 0, 4));
  Expect.equals(5, pathOptions.selectKey(b('true'), 0, 4));
  Expect.equals(6, pathOptions.selectKey(b('false'), 0, 5));
  Expect.equals(7, pathOptions.selectKey(b('0'), 0, 1));
  Expect.equals(8, pathOptions.selectKey(b('-1'), 0, 2));
}
