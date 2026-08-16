// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testEncodeLargeWebIntegers();
  testJsonTokenWriterLargeIntegers();
  testWriteIntToBufferLargeIntegers();
  testDecodeLargeIntegersPrecision();
  testDecodeCorrectlyRoundedLargeIntegers();
  testEncodeIntegersAbove2Pow53();
  testTokenReaderLargeIntegers();
}

/// Values that reach the decoder's unsigned 64-bit range checks.
///
/// On the web `int` is a double and bitwise operators are evaluated with
/// 32-bit semantics, so an `x ^ 0x8000000000000000` sign-flip comparison
/// silently degenerates to comparing the low 32 bits. When that check is wrong
/// the digit-accumulation shortcut is taken for values it cannot represent and
/// the result is off by one or more ulp from the correctly rounded value that
/// `json.decode` produces.
void testDecodeCorrectlyRoundedLargeIntegers() {
  const cases = [
    "9308364126768071717",
    "-9308364126768071717",
    "9095156293722702342",
    "-9095156293722702342",
    "8925238349618745892",
    "-8925238349618745892",
    "68323050187018705",
    "-68323050187018705",
    "999999999999999999",
    "-999999999999999999",
    "1234567890123456789",
    "-1234567890123456789",
    "9999999999999999999", // > int64 max: decoded as a double
    "-9999999999999999999",
    "9223372036854775807", // int64 max
    "-9223372036854775808", // int64 min
  ];

  for (final s in cases) {
    final bytes = Uint8List.fromList(utf8.encode(s));
    Expect.equals(
      json.decode(s),
      jsonUtf8.decode(bytes),
      'Not correctly rounded: "$s"',
    );
    Expect.equals(
      double.parse(s),
      JsonUtf8Decoder.parseDouble(bytes, 0, bytes.length),
      'parseDouble not correctly rounded: "$s"',
    );
    final reader = JsonTokenReader.fromBytes(bytes);
    Expect.equals(
      double.parse(s),
      reader.readDouble(),
      'readDouble not correctly rounded: "$s"',
    );
  }
}

/// Integers between 2^53 and 1e19 are ordinary `int` values on every platform,
/// but on the web `int` is a double, so `~/` and `*` in the digit-pair
/// formatter stop being exact. An overshooting quotient drives the pair
/// remainder negative, which either indexes outside the digit table or emits
/// well-formed but wrong digits.
void testEncodeIntegersAbove2Pow53() {
  final values = <int>[
    9007199254740991, // 2^53 - 1, last exact value
    9007199254740992, // 2^53
    60592972518337896,
    42845701759940776,
    68323050187018704,
    1000000000000000000, // 1e18
    4611686018427387904, // 2^62
  ];

  // A deterministic sweep of the binades in between.
  var seed = 0x51ed270b;
  var power = 9007199254740992; // 2^53
  for (var binade = 0; binade < 9; binade++) {
    for (var i = 0; i < 40; i++) {
      seed = (seed * 1103515245 + 12345) & 0x3FFFFFFF;
      values.add(power + (seed % 1000) * 97);
    }
    power *= 2;
  }

  final buffer = Uint8List(64);
  for (final magnitude in values) {
    for (final value in [magnitude, -magnitude]) {
      final expected = value.toString();

      final written = JsonUtf8Encoder.writeIntToBuffer(value, buffer, 4);
      Expect.equals(
        expected,
        utf8.decode(Uint8List.sublistView(buffer, 4, 4 + written)),
        'writeIntToBuffer disagrees with toString for $value',
      );

      final sink = BytesBuilder(copy: false);
      JsonUtf8Encoder.writeInt(value, sink);
      Expect.equals(
        expected,
        utf8.decode(sink.takeBytes()),
        'writeInt disagrees with toString for $value',
      );

      Expect.equals(
        json.encode(value),
        utf8.decode(jsonUtf8.encode(value)),
        'jsonUtf8.encode disagrees with json.encode for $value',
      );
    }
  }
}

/// Verifies that jsonUtf8.encode on numbers >= 20 digits does not corrupt
/// preceding bytes or step backward past the buffer cursor.
void testEncodeLargeWebIntegers() {
  // 1. [5, 1e19] must produce '[5,10000000000000000000]' on Web without corrupting '5,'
  final res1e19 = jsonUtf8.encode([5, 1e19]);
  final str1e19 = utf8.decode(res1e19);
  Expect.equals(json.encode([5, 1e19]), str1e19);
  Expect.isTrue(str1e19.startsWith('[5,'), 'Expected [5,... but got: $str1e19');

  // 2. Negative [5, -1e19]
  final resNeg1e19 = jsonUtf8.encode([5, -1e19]);
  final strNeg1e19 = utf8.decode(resNeg1e19);
  Expect.equals(json.encode([5, -1e19]), strNeg1e19);
  Expect.isTrue(
    strNeg1e19.startsWith('[5,'),
    'Expected [5,... but got: $strNeg1e19',
  );

  // 3. [5, 1e25] must not throw RangeError and must match json.encode
  final res1e25 = jsonUtf8.encode([5, 1e25]);
  final str1e25 = utf8.decode(res1e25);
  Expect.equals(json.encode([5, 1e25]), str1e25);
  Expect.isTrue(str1e25.startsWith('[5,'), 'Expected [5,... but got: $str1e25');

  // 4. [5, -1e25]
  final resNeg1e25 = jsonUtf8.encode([5, -1e25]);
  final strNeg1e25 = utf8.decode(resNeg1e25);
  Expect.equals(json.encode([5, -1e25]), strNeg1e25);
  Expect.isTrue(
    strNeg1e25.startsWith('[5,'),
    'Expected [5,... but got: $strNeg1e25',
  );

  // 5. Multiple array elements with large integers
  final multi = [1, 2, 1e19, 3, 1e25, 4];
  final resMulti = jsonUtf8.encode(multi);
  Expect.equals(json.encode(multi), utf8.decode(resMulti));

  // 6. Object encoding with large integers
  final map = {'a': 5, 'b': 1e19, 'c': 1e25};
  final resMap = jsonUtf8.encode(map);
  Expect.equals(json.encode(map), utf8.decode(resMap));

  // 7. Nested collections
  final nested = [
    [1e19],
    {
      'list': [-1e19, 1e25],
    },
  ];
  final resNested = jsonUtf8.encode(nested);
  Expect.equals(json.encode(nested), utf8.decode(resNested));
}

/// Verifies that JsonTokenWriter.writeInt and JsonUtf8Encoder.writeInt
/// correctly format numbers >= 1e19 without emitting ASCII ':' or throwing.
void testJsonTokenWriterLargeIntegers() {
  final maxInt64 = int.parse("9223372036854775807");
  final minInt64 = int.parse("-9223372036854775808");

  // 1. JsonTokenWriter.writeInt inside array
  final bb = BytesBuilder(copy: false);
  final writer = JsonTokenWriter.toSink(bb);
  writer.beginArray();
  writer.writeInt(5);
  writer.writeInt(1000000000000000000); // 1e18
  if (identical(1, 1.0)) {
    // 1e19 is an exact integer in JS: 10000000000000000000
    final num1e19 = 1e19.toInt();
    writer.writeInt(num1e19);
  } else {
    writer.writeInt(maxInt64);
  }
  writer.endArray();

  final out = bb.takeBytes();
  final outStr = utf8.decode(out);
  Expect.isFalse(
    outStr.contains(':'),
    'Array contains unexpected colon: $outStr',
  );
  // Assert the whole document, not just that the last value appears somewhere.
  // A containment check passes even when earlier elements have been corrupted.
  if (identical(1, 1.0)) {
    Expect.equals('[5,1000000000000000000,10000000000000000000]', outStr);
  } else {
    Expect.equals('[5,1000000000000000000,9223372036854775807]', outStr);
  }

  // 2. JsonTokenWriter inside object
  final bbObj = BytesBuilder(copy: false);
  final writerObj = JsonTokenWriter.toSink(bbObj);
  writerObj.beginObject();
  writerObj.writeName('key');
  if (identical(1, 1.0)) {
    writerObj.writeInt(1e19.toInt());
  } else {
    writerObj.writeInt(maxInt64);
  }
  writerObj.endObject();
  final objStr = utf8.decode(bbObj.takeBytes());
  if (identical(1, 1.0)) {
    Expect.equals('{"key":10000000000000000000}', objStr);
  } else {
    Expect.equals('{"key":9223372036854775807}', objStr);
  }

  // 3. Direct JsonUtf8Encoder.writeInt with sink
  final bb2 = BytesBuilder(copy: false);
  if (identical(1, 1.0)) {
    final num1e19 = 1e19.toInt();
    JsonUtf8Encoder.writeInt(num1e19, bb2);
    final directBytes = bb2.takeBytes();
    final directStr = utf8.decode(directBytes);
    Expect.equals('10000000000000000000', directStr);
    Expect.isFalse(directStr.contains(':'));
  } else {
    JsonUtf8Encoder.writeInt(maxInt64, bb2);
    final directBytes = bb2.takeBytes();
    final directStr = utf8.decode(directBytes);
    Expect.equals('9223372036854775807', directStr);
    Expect.isFalse(directStr.contains(':'));
  }

  // 4. Negative 1e19 / min int64
  final bb3 = BytesBuilder(copy: false);
  if (identical(1, 1.0)) {
    JsonUtf8Encoder.writeInt((-1e19).toInt(), bb3);
    final negStr = utf8.decode(bb3.takeBytes());
    Expect.equals('-10000000000000000000', negStr);
  } else {
    JsonUtf8Encoder.writeInt(minInt64, bb3);
    final negStr = utf8.decode(bb3.takeBytes());
    Expect.equals('-9223372036854775808', negStr);
  }

  // 5. Large 1e25 on web
  if (identical(1, 1.0)) {
    final bb4 = BytesBuilder(copy: false);
    JsonUtf8Encoder.writeInt(1e25.toInt(), bb4);
    final str1e25 = utf8.decode(bb4.takeBytes());
    Expect.equals((1e25.toInt()).toString(), str1e25);
  }

  // 6. Zero and small integers
  final bbZero = BytesBuilder(copy: false);
  JsonUtf8Encoder.writeInt(0, bbZero);
  Expect.equals('0', utf8.decode(bbZero.takeBytes()));

  final bb42 = BytesBuilder(copy: false);
  JsonUtf8Encoder.writeInt(42, bb42);
  Expect.equals('42', utf8.decode(bb42.takeBytes()));

  final bbNeg42 = BytesBuilder(copy: false);
  JsonUtf8Encoder.writeInt(-42, bbNeg42);
  Expect.equals('-42', utf8.decode(bbNeg42.takeBytes()));
}

/// Verifies that JsonUtf8Encoder.writeIntToBuffer correctly formats
/// numbers with >= 20 digits into target buffers without underflowing cursor.
void testWriteIntToBufferLargeIntegers() {
  final buf = Uint8List(64);
  final maxInt64 = int.parse("9223372036854775807");
  final minInt64 = int.parse("-9223372036854775808");

  // 1. Positive large integer
  final val1 = identical(1, 1.0) ? 1e19.toInt() : maxInt64;
  final len1 = JsonUtf8Encoder.writeIntToBuffer(val1, buf, 5);
  final str1 = utf8.decode(Uint8List.sublistView(buf, 5, 5 + len1));
  Expect.equals(val1.toString(), str1);

  // 2. Negative large integer
  final val2 = identical(1, 1.0) ? (-1e19).toInt() : minInt64;
  final len2 = JsonUtf8Encoder.writeIntToBuffer(val2, buf, 5);
  final str2 = utf8.decode(Uint8List.sublistView(buf, 5, 5 + len2));
  Expect.equals(val2.toString(), str2);

  // 3. 1e25 on Web
  if (identical(1, 1.0)) {
    final len3 = JsonUtf8Encoder.writeIntToBuffer(1e25.toInt(), buf, 5);
    final str3 = utf8.decode(Uint8List.sublistView(buf, 5, 5 + len3));
    Expect.equals((1e25.toInt()).toString(), str3);
  }

  // 4. Standard 0, 42, -42
  final len0 = JsonUtf8Encoder.writeIntToBuffer(0, buf, 0);
  Expect.equals(1, len0);
  Expect.equals(48, buf[0]);

  final len42 = JsonUtf8Encoder.writeIntToBuffer(42, buf, 0);
  Expect.equals(2, len42);
  Expect.equals('42', utf8.decode(Uint8List.sublistView(buf, 0, len42)));

  final lenNeg42 = JsonUtf8Encoder.writeIntToBuffer(-42, buf, 0);
  Expect.equals(3, lenNeg42);
  Expect.equals('-42', utf8.decode(Uint8List.sublistView(buf, 0, lenNeg42)));

  // 5. Bounds validation / RangeError
  Expect.throws<RangeError>(() {
    JsonUtf8Encoder.writeIntToBuffer(42, Uint8List(1), 0);
  });
  Expect.throws<RangeError>(() {
    JsonUtf8Encoder.writeIntToBuffer(42, Uint8List(10), -1);
  });
  Expect.throws<RangeError>(() {
    JsonUtf8Encoder.writeIntToBuffer(42, Uint8List(10), 10);
  });
  if (identical(1, 1.0)) {
    Expect.throws<RangeError>(() {
      JsonUtf8Encoder.writeIntToBuffer(1e19.toInt(), Uint8List(10), 0);
    });
  }
}

/// Verifies that jsonUtf8.decode and JsonUtf8Decoder.tryParseInt return
/// bit-exact results matching json.decode for 16+ digit runs on Web.
void testDecodeLargeIntegersPrecision() {
  final testCases = [
    "0",
    "-0",
    "1",
    "-1",
    "42",
    "-42",
    "68323050187018705",
    "9223372036854775807",
    "-9223372036854775808",
    "9007199254740991", // 2^53 - 1
    "9007199254740992", // 2^53
    "9007199254740993", // 2^53 + 1
    "1000000000000000", // 1e15 (16 digits)
    "1234567890123456",
    "12345678901234567",
    "123456789012345678",
    "1234567890123456789",
    "-68323050187018705",
    "-12345678901234567",
    "1000000000000000000", // 1e18 (19 digits)
  ];

  for (final s in testCases) {
    final bytes = Uint8List.fromList(utf8.encode(s));
    final expected = json.decode(s);
    final actual = jsonUtf8.decode(bytes);
    Expect.equals(
      expected,
      actual,
      'Discrepancy decoding "$s": expected $expected, got $actual',
    );

    final parsed = JsonUtf8Decoder.tryParseInt(bytes, 0, bytes.length);
    Expect.isNotNull(parsed, 'Failed to parse integer "$s"');
    Expect.equals(
      expected,
      parsed,
      'Discrepancy in tryParseInt for "$s": expected $expected, got $parsed',
    );
  }

  // 19-digit overflow boundaries
  final overMaxInt64 = Uint8List.fromList(utf8.encode("9223372036854775808"));
  Expect.isNull(
    JsonUtf8Decoder.tryParseInt(overMaxInt64, 0, overMaxInt64.length),
  );

  final underMinInt64 = Uint8List.fromList(utf8.encode("-9223372036854775809"));
  Expect.isNull(
    JsonUtf8Decoder.tryParseInt(underMinInt64, 0, underMinInt64.length),
  );

  // 20-digit number (exceeds 64-bit int range, parsed as double by jsonUtf8.decode)
  final num20Digits = "10000000000000000000";
  final bytes20 = Uint8List.fromList(utf8.encode(num20Digits));
  Expect.isNull(JsonUtf8Decoder.tryParseInt(bytes20, 0, bytes20.length));
  Expect.equals(json.decode(num20Digits), jsonUtf8.decode(bytes20));
}

/// Verifies that JsonTokenReader.readInt and readNum match json.decode
/// on large integer values.
void testTokenReaderLargeIntegers() {
  final testNumbers = [
    "0",
    "-0",
    "42",
    "-42",
    "68323050187018705",
    "9223372036854775807",
    "-9223372036854775808",
    "9007199254740991",
    "9007199254740992",
    "9007199254740993",
  ];

  for (final numStr in testNumbers) {
    final jsonText = '[$numStr]';
    final bytes = Uint8List.fromList(utf8.encode(jsonText));

    // Test readInt
    final reader1 = JsonTokenReader.fromBytes(bytes);
    reader1.beginArray();
    final intVal = reader1.readInt();
    reader1.endArray();
    Expect.equals(json.decode(numStr), intVal);

    // Test readNum
    final reader2 = JsonTokenReader.fromBytes(bytes);
    reader2.beginArray();
    final numVal = reader2.readNum();
    reader2.endArray();
    Expect.equals(json.decode(numStr), numVal);
  }
}
