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
  testSurrogateEncoding();
  testRfc8259NumberGrammar();
  testIntegerOverflowAndLimits();
  testNonFiniteDoubleRejection();
  testWhitespaceAndControlChars();
  testDecodeStringWithEscapesAndSurrogates();
  testSkipValueControlChars();
  testDoubleFastPathAndNegativeZero();
  testJsonKeyOptionsCollisionsAndDuplicates();
  testBufferOverflowAndBounds();
  testUnescapedControlCharsInStrings();
  testContainerSkippingNesting();
  testSkipValueMaxDepth();
  testWriteDoubleToBufferEdgeCases();
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
  // Must NOT be treated as pre-quoted; must be safely wrapped in quotes.
  final innerQuoteKey = Uint8List.fromList(utf8.encode('"a"b"'));
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    innerQuoteKey,
    isFirst: true,
  );
  Expect.equals('""a"b"":', utf8.decode(buffer.sublist(0, len)));

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

  // Empty key bytes: Uint8List(0)
  len = JsonUtf8Encoder.writePropertyPrefixToBuffer(
    buffer,
    0,
    Uint8List(0),
    isFirst: true,
  );
  Expect.equals('"":', utf8.decode(buffer.sublist(0, len)));
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

  // Control char \x00 should not be skipped as whitespace
  final withNul = b('\x00{"a": 1}');
  final skipNul = JsonUtf8Decoder.skipValue(withNul, 0);
  // It shouldn't skip past the object if it started on a non-whitespace control character
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

  // Trailing backslash in skipString
  final b8 = b('"hello\\');
  final skipOffset = JsonUtf8Decoder.skipString(b8, 0);
  Expect.isTrue(skipOffset <= b8.length);
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
