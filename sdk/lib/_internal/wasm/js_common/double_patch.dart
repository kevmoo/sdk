import 'dart:typed_data';
// Copyright (c) 2022, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:_internal" show patch;
import 'dart:convert';
import 'dart:_js_helper' show JS;
import 'dart:_js_helper';

@patch
class double {
  static bool _isUtf8Whitespace(int codeUnit) {
    return codeUnit <= 32 &&
        (codeUnit == 32 || (codeUnit <= 13 && codeUnit >= 9));
  }

  static double? _tryParseUtf8Double(Uint8List str, int start, int end) {
    assert(start < end);
    const int _DOT = 0x2e; // '.'
    const int _ZERO = 0x30; // '0'
    const int _MINUS = 0x2d; // '-'
    const int _N = 0x4e; // 'N'
    const int _a = 0x61; // 'a'
    const int _I = 0x49; // 'I'
    const int _e = 0x65; // 'e'
    int exponent = 0;
    bool digitsSeen = false;
    int exponentDelta = 0;
    double doubleValue = 0.0;
    double sign = 1.0;
    int firstChar = str[start];
    if (firstChar == _MINUS || firstChar == 0x2b /* + */ ) {
      sign = firstChar == _MINUS ? -1.0 : 1.0;
      start++;
      if (start == end) return null;
      firstChar = str[start];
    }
    if (firstChar == _I) {
      if (end == start + 8 &&
          str[start + 1] == 0x6e &&
          str[start + 2] == 0x66 &&
          str[start + 3] == 0x69 &&
          str[start + 4] == 0x6e &&
          str[start + 5] == 0x69 &&
          str[start + 6] == 0x74 &&
          str[start + 7] == 0x79) {
        return sign * double.infinity;
      }
      return null;
    }
    if (firstChar == _N) {
      if (end == start + 3 && str[start + 1] == _a && str[start + 2] == _N) {
        return double.nan;
      }
      return null;
    }

    int firstDigit = firstChar ^ _ZERO;
    if (firstDigit <= 9) {
      start++;
      doubleValue = firstDigit.toDouble();
      digitsSeen = true;
    }
    for (int i = start; i < end; i++) {
      int c = str[i];
      int digit = c ^ _ZERO;
      if (digit <= 9) {
        doubleValue = 10.0 * doubleValue + digit;
        const double MAX_EXACT_DOUBLE = 9007199254740992.0;
        if (doubleValue >= MAX_EXACT_DOUBLE) return null;
        exponent += exponentDelta;
        digitsSeen = true;
      } else if (c == _DOT && exponentDelta == 0) {
        exponentDelta = -1;
      } else if ((c | 0x20) == _e) {
        i++;
        if (i == end) return null;

        // Inline _tryParseUtf8Smi for exponent parsing
        int expPart = 0;
        int expSign = 1;
        int expC = str[i];
        if (expC == 0x2b || expC == 0x2d) {
          expSign = 0x2c - expC;
          i++;
          if (i == end) return null;
          expC = str[i];
        }
        if (end - i > 18) return null;
        for (int j = i; j < end; j++) {
          int d = 0x30 ^ str[j];
          if (9 < d) return null;
          expPart = (10 * expPart) + d;
        }
        exponent += (expSign * expPart);
        break; // Reached end of float
      } else {
        return null;
      }
    }
    if (!digitsSeen) return null;
    if (exponent == 0) return sign * doubleValue;

    // Fall back to allocating String instead of hardcoding POWERS_OF_TEN here for sizes
    return null;
  }

  @patch
  static double parseUtf8(Uint8List source, [int start = 0, int? end]) {
    double? result = tryParseUtf8(source, start, end);
    if (result == null) {
      throw FormatException("Invalid double");
    }
    return result;
  }

  @patch
  static double? tryParseUtf8(Uint8List source, [int start = 0, int? end]) {
    int actualEnd = end ?? source.length;
    if (start < 0 || start > actualEnd) {
      throw RangeError.range(start, 0, actualEnd, "start");
    }
    if (actualEnd > source.length) {
      throw RangeError.range(actualEnd, start, source.length, "end");
    }
    if (start == actualEnd) return null;

    int currentStart = start;
    int currentEnd = actualEnd;

    while (currentStart < currentEnd &&
        _isUtf8Whitespace(source[currentStart])) {
      currentStart++;
    }
    while (currentStart < currentEnd &&
        _isUtf8Whitespace(source[currentEnd - 1])) {
      currentEnd--;
    }
    if (currentStart == currentEnd) return null;

    double? fastResult = _tryParseUtf8Double(source, currentStart, currentEnd);
    if (fastResult != null) return fastResult;

    // Fall back to JS parseFloat via String
    return double.tryParse(
      utf8.decode(source.sublist(currentStart, currentEnd)),
    );
  }

  @patch
  static double parse(String source) {
    double? result = tryParse(source);
    if (result == null) {
      throw FormatException('Invalid double $source');
    }
    return result;
  }

  @patch
  static double? tryParse(String source) {
    // Notice that JS parseFloat accepts garbage at the end of the string.
    // Accept only:
    // - [+/-]NaN
    // - [+/-]Infinity
    // - a Dart double literal
    // We do allow leading or trailing whitespace.
    double result = JS<double>(r"""s => {
      if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
        return NaN;
      }
      return parseFloat(s);
    }""", jsStringFromDartString(source).wrappedExternRef);
    if (result.isNaN) {
      String trimmed = source.trim();
      if (!(trimmed == 'NaN' || trimmed == '+NaN' || trimmed == '-NaN')) {
        return null;
      }
    }
    return result;
  }
}
