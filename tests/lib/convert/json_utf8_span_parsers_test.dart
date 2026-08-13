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
}

void testSurrogateEncoding() {
  final buf = Uint8List(64);
  // Isolated low surrogate: \uDC00
  final len1 = JsonUtf8Encoder.writeStringToBuffer('\uDC00', buf, 0);
  final decoded1 = utf8.decode(buf.sublist(0, len1));
  Expect.isTrue(decoded1 == '"\uFFFD"' || decoded1 == r'"\udc00"');

  // Isolated high surrogate: \uD800
  final len2 = JsonUtf8Encoder.writeStringToBuffer('\uD800', buf, 0);
  final decoded2 = utf8.decode(buf.sublist(0, len2));
  Expect.isTrue(decoded2 == '"\uFFFD"' || decoded2 == r'"\ud800"');
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
}
