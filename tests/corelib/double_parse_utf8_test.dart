// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "package:expect/expect.dart";

import "dart:convert";
import "dart:typed_data";

void testDoubleUtf8(String str, double? expected) {
  final bytes = utf8.encode(str);

  if (expected != null) {
    if (expected.isNaN) {
      Expect.isTrue(double.parseUtf8(bytes).isNaN);
      Expect.isTrue(double.tryParseUtf8(bytes)!.isNaN);
    } else {
      Expect.equals(expected, double.parseUtf8(bytes));
      Expect.equals(expected, double.tryParseUtf8(bytes));
    }
  } else {
    Expect.throwsFormatException(() => double.parseUtf8(bytes));
    Expect.isNull(double.tryParseUtf8(bytes));
  }
}

void testDoubleUtf8Range(String str, double? expected, int start, [int? end]) {
  final bytes = utf8.encode(str);

  if (expected != null) {
    Expect.equals(expected, double.parseUtf8(bytes, start, end));
    Expect.equals(expected, double.tryParseUtf8(bytes, start, end));
  } else {
    Expect.throwsFormatException(() => double.parseUtf8(bytes, start, end));
    Expect.isNull(double.tryParseUtf8(bytes, start, end));
  }
}

void main() {
  testDoubleUtf8("0", 0.0);
  testDoubleUtf8("1", 1.0);
  testDoubleUtf8("-1", -1.0);
  testDoubleUtf8("3.14", 3.14);
  testDoubleUtf8("-3.14", -3.14);
  testDoubleUtf8(".5", 0.5);

  // Exponents
  testDoubleUtf8("1e2", 100.0);
  testDoubleUtf8("1E-2", 0.01);
  testDoubleUtf8("-1e-2", -0.01);
  testDoubleUtf8("1.23e4", 12300.0);

  // Whitespace skipping
  testDoubleUtf8("  42.0  ", 42.0);
  testDoubleUtf8("\t 42.0 \n\r", 42.0);

  // Special values
  testDoubleUtf8("Infinity", double.infinity);
  testDoubleUtf8("-Infinity", double.negativeInfinity);
  testDoubleUtf8("NaN", double.nan);
  testDoubleUtf8("-0.0", -0.0);
  testDoubleUtf8("+1.0", 1.0);

  // Fast loop edge cases vs native fallback edge cases
  testDoubleUtf8(
    "9007199254740992.0",
    9007199254740992.0,
  ); // max exact double edge
  testDoubleUtf8("1.0000000000000001", 1.0000000000000001);
  testDoubleUtf8(
    "2.2250738585072014e-308",
    2.2250738585072014e-308,
  ); // subnormal boundary
  testDoubleUtf8("1e308", 1e308); // exponent boundary

  // Whitespace skipping with multibyte
  testDoubleUtf8("\u00A042.0\u00A0", 42.0);

  // Ranges
  testDoubleUtf8Range("a12.3b", 12.3, 1, 5);
  testDoubleUtf8Range("a 12 b", 12.0, 1, 5);

  // Invalid
  testDoubleUtf8("", null);
  testDoubleUtf8("  ", null);
  testDoubleUtf8("1.2.3", null);
  testDoubleUtf8("abc", null);
  testDoubleUtf8("--1", null);
  testDoubleUtf8("123a", null);
  testDoubleUtf8("€123", null);
}
