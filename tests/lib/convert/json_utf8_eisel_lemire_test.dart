// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:math" as math;
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testZeroAndNegativeZero();
  testBoundaryAndTieBreaking();
  testNegativeRfc8259Syntax();
  testTokenReaderReadDouble();
  testTokenReaderAtomicRollback();
  testOversizedExponents();
  testFuzzDifferential100k();
}

/// Exponents with more digits than the scanner's accumulator can hold.
///
/// Truncating the accumulator is not safe: the decimal exponent is also
/// adjusted by the mantissa's digit count, so a truncated exponent can be
/// cancelled back into the Eisel-Lemire table window and yield a confident
/// finite result for a value that underflows to zero or overflows to infinity.
void testOversizedExponents() {
  final manyDigits = ("123456789" * 1114).substring(0, 10019);
  final manyZeros = "0" * 10000;

  final cases = <String>[
    "${manyDigits}e-100000",
    "-${manyDigits}e-100000",
    "0.${manyZeros}1e100000",
    "0.${manyZeros}1e+100000",
    "-0.${manyZeros}1e-100000",
    "1e100000",
    "1e+100000",
    "1e-100000",
    "1e999999999",
    "1e-999999999",
    "1e10000",
    "1e+10000",
    "1e10001",
    "1e99999",
    "0e100000",
    "-0e-100000",
    "0.0e100000",
    "-0.0e100000",
    "1e309",
    "1e-400",
  ];

  for (final source in cases) {
    final bytes = _utf8Bytes(source);
    final expected = double.parse(source);
    final actual = JsonUtf8Decoder.parseDouble(bytes, 0, bytes.length);
    final label = source.length > 32
        ? "${source.substring(0, 16)}...(${source.length} chars)"
        : source;
    Expect.equals(expected, actual, 'parseDouble("$label")');
    Expect.equals(
      expected.isNegative,
      actual.isNegative,
      'sign of parseDouble("$label")',
    );

    final reader = JsonTokenReader.fromBytes(bytes);
    Expect.equals(expected, reader.readDouble(), 'readDouble("$label")');
  }

  // Structural JSON stream with saturated exponent tokens
  final doc = '{"val": ${manyDigits}e-100000, "flag": true}';
  final rDoc = JsonTokenReader.fromBytes(_utf8Bytes(doc));
  rDoc.beginObject();
  Expect.equals("val", rDoc.nextName());
  Expect.equals(0.0, rDoc.readDouble());
  Expect.equals("flag", rDoc.nextName());
  Expect.isTrue(rDoc.readBool());
  rDoc.endObject();
}

extension DoubleBits on double {
  int toBits() {
    final bd = ByteData(8);
    bd.setFloat64(0, this);
    return bd.getInt64(0);
  }
}

Uint8List _utf8Bytes(String s) => Uint8List.fromList(utf8.encode(s));

void testZeroAndNegativeZero() {
  // Positive zero
  final zeroBytes = _utf8Bytes("0.0");
  final zeroParsed = JsonUtf8Decoder.parseDouble(
    zeroBytes,
    0,
    zeroBytes.length,
  );
  Expect.equals(0.0, zeroParsed);
  Expect.isFalse(zeroParsed.isNegative);
  Expect.equals(0x0, zeroParsed.toBits());

  // Negative zero
  final negZeroBytes = _utf8Bytes("-0.0");
  final negZeroParsed = JsonUtf8Decoder.parseDouble(
    negZeroBytes,
    0,
    negZeroBytes.length,
  );
  Expect.equals(0.0, negZeroParsed);
  Expect.isTrue(negZeroParsed.isNegative);
  Expect.equals(0x8000000000000000, negZeroParsed.toBits());

  // Negative integer zero
  final negIntZeroBytes = _utf8Bytes("-0");
  final negIntZeroParsed = JsonUtf8Decoder.parseDouble(
    negIntZeroBytes,
    0,
    negIntZeroBytes.length,
  );
  Expect.equals(0.0, negIntZeroParsed);
  Expect.isTrue(negIntZeroParsed.isNegative);
  Expect.equals(0x8000000000000000, negIntZeroParsed.toBits());

  // Negative zero with exponent
  final negZeroExpBytes = _utf8Bytes("-0e5");
  final negZeroExpParsed = JsonUtf8Decoder.parseDouble(
    negZeroExpBytes,
    0,
    negZeroExpBytes.length,
  );
  Expect.equals(0.0, negZeroExpParsed);
  Expect.isTrue(negZeroExpParsed.isNegative);
}

void testBoundaryAndTieBreaking() {
  final boundaryCases = [
    // Powers of 2 around 53 bits
    "9007199254740991.0", // 2^53 - 1
    "9007199254740992.0", // 2^53
    "9007199254740993.0", // 2^53 + 1
    "9007199254740994.0", // 2^53 + 2
    "-9007199254740991.0",
    "-9007199254740992.0",
    "-9007199254740993.0",

    // 64-bit int boundaries
    "18446744073709551615.0", // 2^64 - 1
    "18446744073709551616.0", // 2^64
    "9223372036854775807.0", // 2^63 - 1
    "9223372036854775808.0", // 2^63
    "-9223372036854775808.0",

    // Normal and subnormal float boundaries
    "2.2250738585072014e-308", // Min normal float (DBL_MIN)
    "2.2250738585072013e-308", // Max subnormal float
    "4.9406564584124654e-324", // Min subnormal float
    "1.7976931348623157e308", // Max normal float (DBL_MAX)
    "-1.7976931348623157e308",
    "1e308",
    "1e-308",
    "1e-323",

    // Exact half-way tie-breaking points
    "0.5",
    "1.5",
    "2.5",
    "3.5",
    "4.5",
    "-0.5",
    "-1.5",
    "-2.5",
    "-3.5",
    "1.0000000000000002",
    "1.0000000000000004",

    // Long mantissas (>19 digits)
    "10000000000000000000.0",
    "100000000000000000000.0",
    "100000000000000000000000000000000000000000.0",
    "123456789012345678901234567890.123456789",
    "0.00000000000000000000000000000000000000001",
    "0.0000000000000000000000000000000000000000000000000123456",

    // Typical GeoJSON and financial coordinates
    "-65.613617",
    "43.464258",
    "37.774929",
    "-122.419416",
    "123456.789012",
  ];

  for (final s in boundaryCases) {
    final bytes = _utf8Bytes(s);
    final actual = JsonUtf8Decoder.parseDouble(bytes, 0, bytes.length);
    final expected = double.parse(s);
    if (actual.isNaN && expected.isNaN) continue;
    Expect.equals(
      expected.toBits(),
      actual.toBits(),
      "Bit mismatch for '$s': expected=$expected (0x${expected.toBits().toRadixString(16)}), got=$actual (0x${actual.toBits().toRadixString(16)})",
    );
  }
}

void testNegativeRfc8259Syntax() {
  final invalidCases = [
    "+1.0", // Leading plus not allowed in JSON
    "+123",
    "+0.5",
    ".5", // Leading decimal point without integer digit
    "-.5",
    "5.", // Trailing decimal point without fraction digit
    "-5.",
    "0123", // Leading zero followed by digit
    "-0123",
    "00.5",
    "123e", // Exponent without digits
    "123e+",
    "123e-",
    "123E",
    "123abc", // Trailing non-numeric garbage
    "1.2.3", // Multiple decimal points
    "NaN", // Non-JSON literals
    "-NaN",
    "Infinity",
    "-Infinity",
    "null",
    "true",
    "",
    "   ",
    "-",
    "--1",
    "1e1e1",
    "0x123", // Hex not allowed in JSON
  ];

  for (final s in invalidCases) {
    final bytes = _utf8Bytes(s);
    Expect.throwsFormatException(
      () => JsonUtf8Decoder.parseDouble(bytes, 0, bytes.length),
      "Should reject invalid JSON number syntax: '$s'",
    );
    Expect.equals(
      null,
      JsonUtf8Decoder.tryParseDouble(bytes, 0, bytes.length),
      "tryParseDouble should return null for '$s'",
    );
  }
}

void testTokenReaderReadDouble() {
  // Test reading single floats
  final doc1 = _utf8Bytes("-65.613617");
  final r1 = JsonTokenReader.fromBytes(doc1);
  Expect.equals(JsonTokenType.number, r1.peek());
  final val1 = r1.readDouble();
  Expect.equals(-65.613617, val1);
  Expect.equals(JsonTokenType.endOfDocument, r1.peek());

  // Test reading floats in array
  final docArray = _utf8Bytes("[-0.0, 1.23, -45.67, 8.9e10, 1e-5]");
  final r2 = JsonTokenReader.fromBytes(docArray);
  r2.beginArray();
  Expect.isTrue(r2.hasNext());
  final d0 = r2.readDouble();
  Expect.equals(0.0, d0);
  Expect.isTrue(d0.isNegative);
  Expect.isTrue(r2.hasNext());
  Expect.equals(1.23, r2.readDouble());
  Expect.isTrue(r2.hasNext());
  Expect.equals(-45.67, r2.readDouble());
  Expect.isTrue(r2.hasNext());
  Expect.equals(8.9e10, r2.readDouble());
  Expect.isTrue(r2.hasNext());
  Expect.equals(1e-5, r2.readDouble());
  Expect.isFalse(r2.hasNext());
  r2.endArray();

  // Test reading floats in object
  final docObj = _utf8Bytes('{"lat": 37.7749, "lon": -122.4194}');
  final r3 = JsonTokenReader.fromBytes(docObj);
  r3.beginObject();
  Expect.isTrue(r3.hasNext());
  Expect.equals("lat", r3.nextName());
  Expect.equals(37.7749, r3.readDouble());
  Expect.isTrue(r3.hasNext());
  Expect.equals("lon", r3.nextName());
  Expect.equals(-122.4194, r3.readDouble());
  Expect.isFalse(r3.hasNext());
  r3.endObject();
}

void testTokenReaderAtomicRollback() {
  final doc = _utf8Bytes('["not_a_double", 7.89]');
  final r = JsonTokenReader.fromBytes(doc);
  r.beginArray();

  // "not_a_double" is a string, readDouble must throw FormatException and roll back offset
  Expect.throwsFormatException(() => r.readDouble());

  // Verify reader rolled back cleanly: can inspect token type and read string
  Expect.equals(JsonTokenType.string, r.peek());
  Expect.equals("not_a_double", r.readString());
  Expect.equals(7.89, r.readDouble());
  r.endArray();
}

void testFuzzDifferential100k() {
  final rand = math.Random(1234567);
  int passCount = 0;

  for (int i = 0; i < 100000; i++) {
    final mode = i % 5;
    final isNegative = rand.nextBool();
    final sign = isNegative ? '-' : '';
    String s;

    if (mode == 0) {
      // Pure scientific notation with integer mantissa
      final digitCount = rand.nextInt(19) + 1;
      var mantissa = rand.nextInt(9) + 1;
      for (int d = 1; d < digitCount; d++) {
        mantissa = mantissa * 10 + rand.nextInt(10);
      }
      final exp = rand.nextInt(650) - 325;
      final mantissaStr = BigInt.from(mantissa).toUnsigned(64).toString();
      s = "$sign${mantissaStr}e$exp";
    } else if (mode == 1) {
      // Decimal fraction with integer and fraction parts
      final intDigits = rand.nextInt(10) + 1;
      final fracDigits = rand.nextInt(10) + 1;
      var intPart = "${rand.nextInt(9) + 1}";
      for (int d = 1; d < intDigits; d++) {
        intPart += "${rand.nextInt(10)}";
      }
      var fracPart = "";
      for (int d = 0; d < fracDigits; d++) {
        fracPart += "${rand.nextInt(10)}";
      }
      s = "$sign$intPart.$fracPart";
    } else if (mode == 2) {
      // Decimal fraction with scientific exponent
      final intDigits = rand.nextInt(8) + 1;
      final fracDigits = rand.nextInt(8) + 1;
      var intPart = "${rand.nextInt(9) + 1}";
      for (int d = 1; d < intDigits; d++) {
        intPart += "${rand.nextInt(10)}";
      }
      var fracPart = "";
      for (int d = 0; d < fracDigits; d++) {
        fracPart += "${rand.nextInt(10)}";
      }
      final exp = rand.nextInt(600) - 300;
      s = "$sign$intPart.${fracPart}e$exp";
    } else if (mode == 3) {
      // Leading fractional zeros (e.g. 0.00000123)
      final zeroCount = rand.nextInt(15) + 1;
      final sigDigits = rand.nextInt(15) + 1;
      var fracPart = '0' * zeroCount;
      fracPart += "${rand.nextInt(9) + 1}";
      for (int d = 1; d < sigDigits; d++) {
        fracPart += "${rand.nextInt(10)}";
      }
      s = "${sign}0.$fracPart";
    } else {
      // Long mantissas (up to 30 digits)
      final totalDigits = rand.nextInt(15) + 18;
      var digits = "${rand.nextInt(9) + 1}";
      for (int d = 1; d < totalDigits; d++) {
        digits += "${rand.nextInt(10)}";
      }
      final dotPos = rand.nextInt(totalDigits - 1) + 1;
      final intPart = digits.substring(0, dotPos);
      final fracPart = digits.substring(dotPos);
      final exp = rand.nextInt(400) - 200;
      s = "$sign$intPart.${fracPart}e$exp";
    }

    final bytes = _utf8Bytes(s);
    final expected = double.parse(s);
    final actual = JsonUtf8Decoder.parseDouble(bytes, 0, bytes.length);

    if (expected.isNaN && actual.isNaN) {
      passCount++;
      continue;
    }

    Expect.equals(
      expected.toBits(),
      actual.toBits(),
      "Fuzz mismatch on iteration $i for '$s': expected=$expected (0x${expected.toBits().toRadixString(16)}), got=$actual (0x${actual.toBits().toRadixString(16)})",
    );
    passCount++;
  }

  Expect.equals(100000, passCount);
}
