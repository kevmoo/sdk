import 'dart:typed_data';
// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:_internal" show patch, unsafeCast;
import "dart:_string" show StringUncheckedOperations;
import "dart:_string_helper" show skipLeadingWhitespace, skipTrailingWhitespace;
import "dart:_wasm";
import "dart:_error_utils";

@patch
class int {
  @patch
  static int? tryParse(String source, {int? radix}) {
    if (source.isEmpty) {
      return null;
    }
    if (radix == null || radix == 10) {
      // Try parsing immediately, without trimming whitespace.
      int? result = _tryParseIntRadix10(source, 0, source.length);
      if (result != null) return result;
    } else {
      RangeErrorUtils.checkValueBetweenZeroAndPositiveMax(
        radix - 2,
        34,
        "Radix $radix not in range 2..36",
      );
    }
    return _parse(source, radix, _kNull);
  }

  static bool _isUtf8Whitespace(int codeUnit) {
    return codeUnit <= 32 &&
        (codeUnit == 32 || (codeUnit <= 13 && codeUnit >= 9));
  }

  @patch
  static int parseUtf8(
    Uint8List source, {
    int start = 0,
    int? end,
    int? radix,
  }) {
    if (source.isEmpty) {
      throw FormatException("Invalid number");
    }
    int? result = tryParseUtf8(source, start: start, end: end, radix: radix);
    if (result != null) return result;
    throw FormatException("Invalid number");
  }

  @patch
  static int? tryParseUtf8(
    Uint8List source, {
    int start = 0,
    int? end,
    int? radix,
  }) {
    int actualEnd = end ?? source.length;
    if (start < 0 || start > actualEnd) {
      throw RangeError.range(start, 0, actualEnd, "start");
    }
    if (actualEnd > source.length) {
      throw RangeError.range(actualEnd, start, source.length, "end");
    }
    if (start == actualEnd) return null;

    // Trim ASCII whitespace
    while (start < actualEnd && _isUtf8Whitespace(source[start])) {
      start++;
    }
    while (start < actualEnd && _isUtf8Whitespace(source[actualEnd - 1])) {
      actualEnd--;
    }
    if (start == actualEnd) return null;

    if (radix == null || radix == 10) {
      int? result = _tryParseUtf8Radix10(source, start, actualEnd);
      if (result != null) return result;
    } else {
      RangeErrorUtils.checkValueBetweenZeroAndPositiveMax(
        radix - 2,
        34,
        "Radix $radix not in range 2..36",
      );
    }

    return _parseUtf8Radix(source, radix, start, actualEnd, null);
  }

  static int? _parseUtf8Radix(
    Uint8List source,
    int? radix,
    int start,
    int end,
    int? Function(String)? onError,
  ) {
    int first = source[start];
    int sign = 1;
    if (first == 0x2b /* + */ || first == 0x2d /* - */ ) {
      sign = 0x2c - first; // -1 if '-', +1 if '+'.
      start++;
      if (start == end) {
        return null; // FormatError
      }
      first = source[start];
    }
    if (radix == null) {
      if (first == 0x30 /* 0 */ ) {
        int index = start + 1;
        if (index == end) return 0;
        first = source[index];
        if ((first | 0x20) == 0x78 /* x */ ) {
          index++;
          if (index == end) return null; // Format exception
          radix = 16;
          start = index;
        } else {
          radix = 10;
        }
      } else {
        radix = 10;
      }
    }
    return _parseUtf8RadixGeneral(
      source,
      radix,
      start,
      end,
      sign,
      radix == 16 && sign > 0,
      onError,
    );
  }

  static int? _parseUtf8RadixGeneral(
    Uint8List source,
    int radix,
    int start,
    int end,
    int sign,
    bool allowOverflow,
    int? Function(String)? onError,
  ) {
    // Skip leading zeroes.
    while (start < end && source[start] == 0x30 /* 0 */ ) {
      start += 1;
    }

    final blockSize = _PARSE_LIMITS[radix].toInt();
    final length = end - start;

    // Parse at most `blockSize` characters without overflows.
    final parseBlockLength = length < blockSize ? length : blockSize;
    int? blockResult = _parseBlockUtf8(
      source,
      radix,
      start,
      start + parseBlockLength,
    );
    if (blockResult == null) {
      return null;
    }

    int result = sign * blockResult;

    if (parseBlockLength < blockSize) {
      // Overflow is not possible.
      return result;
    }

    // Check overflows on the next digits. We can scan at most two digits before an overflow.
    start += parseBlockLength;

    for (int i = start; i < end; i++) {
      int char = source[i];
      int digit = char ^ 0x30;
      if (digit > 9) {
        digit = (char | 0x20) - (0x61 - 10);
        if (digit < 10 || digit >= radix) {
          return null;
        }
      }

      if (sign > 0) {
        const max = 9223372036854775807;
        if (!allowOverflow && (result > (max - digit) ~/ radix)) {
          return null;
        }
        result = (radix * result) + digit;
      } else {
        const min = -9223372036854775808;
        if (result < (min + digit) ~/ radix) {
          return null;
        }
        result = (radix * result) - digit;
      }
    }

    return result;
  }

  static int? _parseBlockUtf8(Uint8List source, int radix, int start, int end) {
    int result = 0;
    if (radix <= 10) {
      for (int i = start; i < end; i++) {
        int digit = source[i] ^ 0x30;
        if (digit >= radix) return null;
        result = (radix * result) + digit;
      }
    } else {
      for (int i = start; i < end; i++) {
        int char = source[i];
        int digit = char ^ 0x30;
        if (digit > 9) {
          digit = (char | 0x20) - (0x61 - 10);
          if (digit < 10 || digit >= radix) return null;
        }
        result = (radix * result) + digit;
      }
    }
    return result;
  }

  static int? _tryParseUtf8Radix10(Uint8List str, int start, int end) {
    int ix = start;
    int sign = 1;
    int c = str[ix];
    if ((c == 0x2b) || (c == 0x2d)) {
      ix++;
      sign = 0x2c - c;
      if (ix == end) {
        return null;
      }
    }
    if (end - ix > 19) {
      return null;
    }
    int result = 0;
    int limit = end - ix == 19 ? end - 1 : end;
    for (int i = ix; i < limit; i++) {
      int c = 0x30 ^ str[i];
      if (9 < c) {
        return null;
      }
      result = (10 * result) + c;
    }
    if (limit != end) {
      int c = 0x30 ^ str[limit];
      if (9 < c) return null;
      if (sign > 0) {
        if (result > (9223372036854775807 - c) ~/ 10) return null;
      } else {
        if (sign * result < (-9223372036854775808 + c) ~/ 10) return null;
      }
      result = (10 * result) + c;
    }
    return sign * result;
  }

  @patch
  static int parse(String source, {int? radix}) {
    if (source.isEmpty) {
      return _handleFormatError(null, source, 0, radix, null) as int;
    }
    if (radix == null || radix == 10) {
      // Try parsing immediately, without trimming whitespace.
      int? result = _tryParseIntRadix10(source, 0, source.length);
      if (result != null) return result;
    } else {
      RangeErrorUtils.checkValueBetweenZeroAndPositiveMax(
        radix - 2,
        34,
        "Radix $radix not in range 2..36",
      );
    }
    // Split here so improve odds of parse being inlined and the checks omitted.
    return _parse(source, radix, null)!;
  }

  static int? _parse(
    String source,
    int? radix,
    int? Function(String)? onError,
  ) {
    int end = skipTrailingWhitespace(source, source.length);
    if (end == 0) {
      return _handleFormatError(onError, source, source.length, radix, null);
    }
    int start = skipLeadingWhitespace(source, 0);

    int first = source.codeUnitAtUnchecked(start);
    int sign = 1;
    if (first == 0x2b /* + */ || first == 0x2d /* - */ ) {
      sign = 0x2c - first; // -1 if '-', +1 if '+'.
      start++;
      if (start == end) {
        return _handleFormatError(onError, source, end, radix, null);
      }
      first = source.codeUnitAtUnchecked(start);
    }
    if (radix == null) {
      // check for 0x prefix.
      int index = start;
      if (first == 0x30 /* 0 */ ) {
        index++;
        if (index == end) return 0;
        first = source.codeUnitAtUnchecked(index);
        if ((first | 0x20) == 0x78 /* x */ ) {
          index++;
          if (index == end) {
            return _handleFormatError(onError, source, index, null, null);
          }
          return _parseRadix(source, 16, index, end, sign, sign > 0, onError);
        }
      }
      radix = 10;
    }
    return _parseRadix(source, radix, start, end, sign, false, onError);
  }

  static Null _kNull(_) => null;

  static int? _handleFormatError(
    int? Function(String)? onError,
    String source,
    int? index,
    int? radix,
    String? message,
  ) {
    if (onError != null) return onError(source);
    if (message != null) {
      throw FormatException(message, source, index);
    }
    if (radix == null) {
      throw FormatException("Invalid number", source, index);
    }
    throw FormatException("Invalid radix-$radix number", source, index);
  }

  static int? _parseRadix(
    String source,
    int radix,
    int start,
    int end,
    int sign,
    bool allowOverflow,
    int? Function(String)? onError,
  ) {
    // Skip leading zeroes.
    while (start < end && source.codeUnitAtUnchecked(start) == 0x30 /* 0 */ ) {
      start += 1;
    }

    final blockSize = _PARSE_LIMITS[radix].toInt();
    final length = end - start;

    // Parse at most `blockSize` characters without overflows.
    final parseBlockLength = length < blockSize ? length : blockSize;
    int? blockResult = _parseBlock(
      source,
      radix,
      start,
      start + parseBlockLength,
    );
    if (blockResult == null) {
      return _handleFormatError(onError, source, start, radix, null);
    }

    int result = sign * blockResult;

    if (parseBlockLength < blockSize) {
      // Overflow is not possible.
      return result;
    }

    // Check overflows on the next digits. We can scan at most two digits before an overflow.
    start += parseBlockLength;

    for (int i = start; i < end; i++) {
      int char = source.codeUnitAtUnchecked(i);
      int digit = char ^ 0x30;
      if (digit > 9) {
        digit = (char | 0x20) - (0x61 - 10);
        if (digit < 10 || digit >= radix) {
          return _handleFormatError(onError, source, start, radix, null);
        }
      }

      if (sign > 0) {
        const max = 9223372036854775807;

        if (!allowOverflow && (result > (max - digit) ~/ radix)) {
          return _handleFormatError(
            onError,
            source,
            null,
            radix,
            "Positive input exceeds the limit of integer",
          );
        }

        result = (radix * result) + digit;
      } else {
        const min = -9223372036854775808;

        // We don't need to check `allowOverflow` as overflows are only allowed
        // in positive numbers.
        if (result < (min + digit) ~/ radix) {
          return _handleFormatError(
            onError,
            source,
            null,
            radix,
            "Negative input exceeds the limit of integer",
          );
        }

        result = (radix * result) - digit;
      }
    }

    return result;
  }

  /// Parse digits in [source] range from [start] to [end].
  ///
  /// Returns `null` if a character is not valid in radix [radix].
  ///
  /// Does not check for overflows, assumes that the number of digits in the
  /// range will fit into an [int].
  static int? _parseBlock(String source, int radix, int start, int end) {
    int result = 0;
    if (radix <= 10) {
      for (int i = start; i < end; i++) {
        int digit = source.codeUnitAtUnchecked(i) ^ 0x30;
        if (digit >= radix) return null;
        result = (radix * result) + digit;
      }
    } else {
      for (int i = start; i < end; i++) {
        int char = source.codeUnitAtUnchecked(i);
        int digit = char ^ 0x30;
        if (digit > 9) {
          digit = (char | 0x20) - (0x61 - 10);
          if (digit < 10 || digit >= radix) return null;
        }
        result = (radix * result) + digit;
      }
    }
    return result;
  }

  static int? _tryParseIntRadix10(String str, int start, int end) {
    int ix = start;
    int sign = 1;
    int c = str.codeUnitAtUnchecked(ix);
    // Check for leading '+' or '-'.
    if ((c == 0x2b) || (c == 0x2d)) {
      ix++;
      sign = 0x2c - c; // -1 for '-', +1 for '+'.
      if (ix == end) {
        return null; // Empty.
      }
    }
    if (end - ix > 19) {
      return null;
    }
    int result = 0;
    int limit = end - ix == 19 ? end - 1 : end;
    for (int i = ix; i < limit; i++) {
      int c = 0x30 ^ str.codeUnitAtUnchecked(i);
      if (9 < c) {
        return null;
      }
      result = (10 * result) + c;
    }
    if (limit != end) {
      int c = 0x30 ^ str.codeUnitAtUnchecked(limit);
      if (9 < c) return null;
      if (sign > 0) {
        if (result > (9223372036854775807 - c) ~/ 10) return null;
      } else {
        if (sign * result < (-9223372036854775808 + c) ~/ 10) return null;
      }
      result = (10 * result) + c;
    }
    return sign * result;
  }

  // For each radix, 2-36, how many digits are guaranteed to fit in an `int`.
  static const _PARSE_LIMITS = ImmutableWasmArray<WasmI64>.literal([
    0, // unused
    0, // unused
    63, // radix: 2
    39,
    31,
    27, // radix: 5
    24,
    22,
    21,
    19,
    18, // radix: 10
    18,
    17,
    17,
    16,
    16, // radix: 15
    15,
    15,
    15,
    14,
    14, // radix: 20
    14,
    14,
    13,
    13,
    13, // radix: 25
    13,
    13,
    13,
    12,
    12, // radix: 30
    12,
    12,
    12,
    12,
    12, // radix: 35
    12,
  ]);
}
