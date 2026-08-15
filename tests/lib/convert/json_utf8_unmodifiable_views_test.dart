// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testUnmodifiableViewsWriteString();
  testUnmodifiableViewsWriteDouble();
  testUnmodifiableViewsParseDouble();
  testWriteStringBoundsAndOverflow();
  testWriteDoubleBoundsAndOverflow();
  testUnmodifiableViewsTokenReader();
}

void testUnmodifiableViewsWriteString() {
  final backing = Uint8List(256);
  final unmodifiableViews = <Uint8List>[
    backing.asUnmodifiableView(),
    Uint8List.sublistView(backing.asUnmodifiableView(), 0, 128),
    Uint8List.sublistView(backing, 10, 100).asUnmodifiableView(),
  ];

  for (final unmodifiable in unmodifiableViews) {
    // 1. Empty string ("")
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer("", unmodifiable, 0),
      (e) => e is UnsupportedError,
    );

    // 2. Short ASCII string (<= 16 chars, pure ASCII)
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer("short", unmodifiable, 0),
      (e) => e is UnsupportedError,
    );

    // 3. Exactly 16 chars ASCII string
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer(
        "1234567890123456",
        unmodifiable,
        0,
      ),
      (e) => e is UnsupportedError,
    );

    // 4. Exactly 17 chars ASCII string (> 16 chars, triggers C++ SIMD native)
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer(
        "12345678901234567",
        unmodifiable,
        0,
      ),
      (e) => e is UnsupportedError,
    );

    // 5. Short string with escape characters (<= 16 chars)
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer('a\nb"c', unmodifiable, 0),
      (e) => e is UnsupportedError,
    );

    // 6. Long ASCII string (> 32 chars, SIMD unrolled loop)
    final longAscii =
        "this_is_a_long_ascii_string_exceeding_sixteen_characters_limit";
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer(longAscii, unmodifiable, 0),
      (e) => e is UnsupportedError,
    );

    // 7. Long string with escapes/Latin-1 (> 16 chars)
    final longEscaped =
        "this_is_a_long_string_with_escapes_\n_\t_\"_and_latin1_\u00E9_characters";
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer(longEscaped, unmodifiable, 0),
      (e) => e is UnsupportedError,
    );

    // 8. TwoByteString / Unicode (> 16 chars and <= 16 chars)
    final unicodeStr = "emoji_🚀_and_unicode_\u1234";
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer(unicodeStr, unmodifiable, 0),
      (e) => e is UnsupportedError,
    );
    final shortUnicode = "🚀_\u03A9";
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer(shortUnicode, unmodifiable, 0),
      (e) => e is UnsupportedError,
    );

    // 9. Isolated surrogates
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer("\uD800", unmodifiable, 0),
      (e) => e is UnsupportedError,
    );
    Expect.throws(
      () => JsonUtf8Encoder.writeStringToBuffer("\uDC00", unmodifiable, 0),
      (e) => e is UnsupportedError,
    );
  }

  // Verify that mutable buffer still works properly
  final mutableBuf = Uint8List(256);
  final written = JsonUtf8Encoder.writeStringToBuffer("hello", mutableBuf, 10);
  Expect.equals(7, written); // '"hello"' = 7 bytes
  Expect.equals('"hello"', utf8.decode(mutableBuf.sublist(10, 17)));

  // Verify empty string on mutable buffer
  final writtenEmpty = JsonUtf8Encoder.writeStringToBuffer("", mutableBuf, 0);
  Expect.equals(2, writtenEmpty);
  Expect.equals('""', utf8.decode(mutableBuf.sublist(0, 2)));

  // Verify isolated surrogates on mutable buffer
  final writtenHighSurrogate = JsonUtf8Encoder.writeStringToBuffer(
    "\uD800",
    mutableBuf,
    0,
  );
  Expect.equals(8, writtenHighSurrogate); // "\ud800"
  Expect.equals(r'"\ud800"', utf8.decode(mutableBuf.sublist(0, 8)));

  final writtenLowSurrogate = JsonUtf8Encoder.writeStringToBuffer(
    "\uDC00",
    mutableBuf,
    0,
  );
  Expect.equals(8, writtenLowSurrogate); // "\udc00"
  Expect.equals(r'"\udc00"', utf8.decode(mutableBuf.sublist(0, 8)));

  // Verify surrogate pair on mutable buffer
  final writtenSurrogatePair = JsonUtf8Encoder.writeStringToBuffer(
    "🚀",
    mutableBuf,
    0,
  );
  Expect.equals(6, writtenSurrogatePair); // '"' + 4-byte UTF-8 + '"'
  Expect.equals('"🚀"', utf8.decode(mutableBuf.sublist(0, 6)));
}

void testUnmodifiableViewsWriteDouble() {
  final backing = Uint8List(128);
  final unmodifiableViews = <Uint8List>[
    backing.asUnmodifiableView(),
    Uint8List.sublistView(backing.asUnmodifiableView(), 0, 64),
    Uint8List.sublistView(backing, 10, 50).asUnmodifiableView(),
  ];

  for (final unmodifiable in unmodifiableViews) {
    // 1. Fast-path float
    Expect.throws(
      () => JsonUtf8Encoder.writeDoubleToBuffer(3.14159, unmodifiable, 0),
      (e) => e is UnsupportedError,
    );

    // 2. Integer float
    Expect.throws(
      () => JsonUtf8Encoder.writeDoubleToBuffer(42.0, unmodifiable, 0),
      (e) => e is UnsupportedError,
    );

    // 3. Zero and Negative zero
    Expect.throws(
      () => JsonUtf8Encoder.writeDoubleToBuffer(0.0, unmodifiable, 0),
      (e) => e is UnsupportedError,
    );
    Expect.throws(
      () => JsonUtf8Encoder.writeDoubleToBuffer(-0.0, unmodifiable, 0),
      (e) => e is UnsupportedError,
    );

    // 4. Fallback path float (extreme exponent / Grisu2 C++ native)
    Expect.throws(
      () =>
          JsonUtf8Encoder.writeDoubleToBuffer(1.23456789e-30, unmodifiable, 0),
      (e) => e is UnsupportedError,
    );
    Expect.throws(
      () => JsonUtf8Encoder.writeDoubleToBuffer(1.23456789e30, unmodifiable, 0),
      (e) => e is UnsupportedError,
    );

    // 5. Non-finite doubles throw ArgumentError
    Expect.throws(
      () => JsonUtf8Encoder.writeDoubleToBuffer(double.nan, unmodifiable, 0),
      (e) => e is ArgumentError,
    );
    Expect.throws(
      () =>
          JsonUtf8Encoder.writeDoubleToBuffer(double.infinity, unmodifiable, 0),
      (e) => e is ArgumentError,
    );
  }

  // Verify that mutable buffer still works properly
  final mutableBuf = Uint8List(128);
  final written = JsonUtf8Encoder.writeDoubleToBuffer(3.14159, mutableBuf, 5);
  Expect.isTrue(written > 0);
  Expect.equals("3.14159", utf8.decode(mutableBuf.sublist(5, 5 + written)));

  // Negative zero
  final writtenNegZero = JsonUtf8Encoder.writeDoubleToBuffer(
    -0.0,
    mutableBuf,
    0,
  );
  Expect.equals(4, writtenNegZero);
  Expect.equals("-0.0", utf8.decode(mutableBuf.sublist(0, 4)));

  // Fallback extreme exponent on mutable buffer
  final writtenExtreme = JsonUtf8Encoder.writeDoubleToBuffer(
    1.23456789e-30,
    mutableBuf,
    0,
  );
  Expect.isTrue(writtenExtreme > 0);
  final strExtreme = utf8.decode(mutableBuf.sublist(0, writtenExtreme));
  Expect.equals(1.23456789e-30, double.parse(strExtreme));
}

void testUnmodifiableViewsParseDouble() {
  final rawBytes = Uint8List.fromList(utf8.encode("3.14159"));
  final unmodifiableViews = <Uint8List>[
    rawBytes.asUnmodifiableView(),
    Uint8List.sublistView(rawBytes.asUnmodifiableView(), 0, rawBytes.length),
    Uint8List.sublistView(rawBytes, 0, rawBytes.length).asUnmodifiableView(),
  ];

  for (final unmodifiable in unmodifiableViews) {
    // Reading / parsing from an unmodifiable view should succeed cleanly
    final parsed = JsonUtf8Decoder.parseDouble(
      unmodifiable,
      0,
      unmodifiable.length,
    );
    Expect.equals(3.14159, parsed);

    final tryParsed = JsonUtf8Decoder.tryParseDouble(
      unmodifiable,
      0,
      unmodifiable.length,
    );
    Expect.equals(3.14159, tryParsed);
  }
}

void testWriteStringBoundsAndOverflow() {
  final buf = Uint8List(32);

  // 1. Negative offset
  Expect.throws(
    () => JsonUtf8Encoder.writeStringToBuffer("test", buf, -1),
    (e) => e is RangeError,
  );

  // 2. Offset beyond buffer length
  Expect.throws(
    () => JsonUtf8Encoder.writeStringToBuffer("test", buf, 33),
    (e) => e is RangeError,
  );

  // 3. Short string exceeding remaining buffer space
  Expect.throws(
    () => JsonUtf8Encoder.writeStringToBuffer("hello", buf, 30),
    (e) => e is RangeError,
  );

  // 4. Exact space for short string: "hello" requires 7 bytes ("hello"), buf is 32, offset 25
  final writtenExact = JsonUtf8Encoder.writeStringToBuffer("hello", buf, 25);
  Expect.equals(7, writtenExact);
  Expect.equals('"hello"', utf8.decode(buf.sublist(25, 32)));

  // 5. Short string 1 byte over capacity: offset 26
  Expect.throws(
    () => JsonUtf8Encoder.writeStringToBuffer("hello", buf, 26),
    (e) => e is RangeError,
  );

  // 6. Long string exceeding remaining buffer space
  final longStr = "this_string_is_much_longer_than_thirty_two_bytes";
  Expect.throws(
    () => JsonUtf8Encoder.writeStringToBuffer(longStr, buf, 0),
    (e) => e is RangeError,
  );

  // 7. Long string with offset exceeding buffer
  Expect.throws(
    () => JsonUtf8Encoder.writeStringToBuffer(longStr, buf, 10),
    (e) => e is RangeError,
  );

  // 8. TwoByteString exceeding buffer space
  final twoByteStr = "unicode_\u1234_string_exceeding_capacity";
  Expect.throws(
    () => JsonUtf8Encoder.writeStringToBuffer(twoByteStr, buf, 10),
    (e) => e is RangeError,
  );

  // 9. Exact space for TwoByteString
  final twoByteBuf = Uint8List(64);
  final writtenTwoByte = JsonUtf8Encoder.writeStringToBuffer(
    twoByteStr,
    twoByteBuf,
    0,
  );
  Expect.isTrue(writtenTwoByte > 0);
  Expect.equals(
    '"$twoByteStr"',
    utf8.decode(twoByteBuf.sublist(0, writtenTwoByte)),
  );
}

void testWriteDoubleBoundsAndOverflow() {
  final buf = Uint8List(16);

  // 1. Negative offset
  Expect.throws(
    () => JsonUtf8Encoder.writeDoubleToBuffer(3.14, buf, -1),
    (e) => e is RangeError,
  );

  // 2. Offset beyond buffer
  Expect.throws(
    () => JsonUtf8Encoder.writeDoubleToBuffer(3.14, buf, 20),
    (e) => e is RangeError,
  );

  // 3. Offset near end leaving insufficient space for double literal
  Expect.throws(
    () => JsonUtf8Encoder.writeDoubleToBuffer(12345678.901234, buf, 12),
    (e) => e is RangeError,
  );

  // 4. Exact space: "3.14" requires 4 bytes, buf is 16, offset 12
  final writtenExact = JsonUtf8Encoder.writeDoubleToBuffer(3.14, buf, 12);
  Expect.equals(4, writtenExact);
  Expect.equals("3.14", utf8.decode(buf.sublist(12, 16)));

  // 5. 1 byte over capacity: offset 13
  Expect.throws(
    () => JsonUtf8Encoder.writeDoubleToBuffer(3.14, buf, 13),
    (e) => e is RangeError,
  );
}

void testUnmodifiableViewsTokenReader() {
  final jsonBytes = Uint8List.fromList(
    utf8.encode('{"key": "value", "num": 123.45, "arr": [true, null]}'),
  );
  final unmodifiableViews = <Uint8List>[
    jsonBytes.asUnmodifiableView(),
    Uint8List.sublistView(jsonBytes.asUnmodifiableView(), 0, jsonBytes.length),
    Uint8List.sublistView(jsonBytes, 0, jsonBytes.length).asUnmodifiableView(),
  ];

  for (final unmodifiable in unmodifiableViews) {
    final reader = JsonTokenReader.fromBytes(unmodifiable);
    reader.beginObject();
    Expect.equals("key", reader.nextName());
    Expect.equals("value", reader.readString());
    Expect.equals("num", reader.nextName());
    Expect.equals(123.45, reader.readDouble());
    Expect.equals("arr", reader.nextName());
    reader.beginArray();
    Expect.equals(true, reader.readBool());
    reader.readNull();
    reader.endArray();
    reader.endObject();
  }
}
