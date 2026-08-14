// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:convert";
import "dart:math";
import "dart:typed_data";

import "package:expect/expect.dart";

void main() {
  testExhaustiveWhitespaceMatrix();
  testNegativeRfc8259SyntaxSuite();
  testDelimiterFusedTypedReads();
  testSelectNameColonAndWhitespaceFusing();
  testDifferentialFuzzer10kCases();
}

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

// =============================================================================
// 1. Exhaustive Whitespace Matrix
// =============================================================================

void testExhaustiveWhitespaceMatrix() {
  final whitespaces = [
    "",
    " ",
    "  ",
    "\t",
    "\r",
    "\n",
    "\r\n",
    " \t ",
    "\t\r\n ",
    "   \r\n\t  \n\r  ",
  ];

  // Test empty containers with all whitespace variations
  for (final ws in whitespaces) {
    // Empty object
    {
      final json = "$ws{$ws}$ws";
      final reader = JsonTokenReader.fromBytes(_b(json));
      Expect.equals(JsonTokenType.beginObject, reader.peek());
      reader.beginObject();
      Expect.isFalse(reader.hasNext());
      reader.endObject();
      Expect.equals(JsonTokenType.endOfDocument, reader.peek());
    }

    // Empty array
    {
      final json = "$ws[$ws]$ws";
      final reader = JsonTokenReader.fromBytes(_b(json));
      Expect.equals(JsonTokenType.beginArray, reader.peek());
      reader.beginArray();
      Expect.isFalse(reader.hasNext());
      reader.endArray();
      Expect.equals(JsonTokenType.endOfDocument, reader.peek());
    }
  }

  // Exhaustive permutation over multi-token structures
  final sampleWs = ["", " ", "\t", "\r\n", " \t\n "];
  for (final w1 in sampleWs) {
    for (final w2 in sampleWs) {
      for (final w3 in sampleWs) {
        for (final w4 in sampleWs) {
          // Object with int, double, string, bool, null
          final json =
              "$w1{$w2"
              '"int"$w3:$w4 42$w1,$w2'
              '"double"$w3:$w4 3.14$w1,$w2'
              '"str"$w3:$w4 "hello"$w1,$w2'
              '"bool"$w3:$w4 true$w1,$w2'
              '"nil"$w3:$w4 null$w1'
              "}$w2";

          final reader = JsonTokenReader.fromBytes(_b(json));
          final options = JsonKeyOptions.of([
            "int",
            "double",
            "str",
            "bool",
            "nil",
          ]);

          reader.beginObject();

          Expect.equals(0, reader.selectName(options));
          Expect.equals(42, reader.readInt());

          Expect.equals(1, reader.selectName(options));
          Expect.equals(3.14, reader.readDouble());

          Expect.equals(2, reader.selectName(options));
          Expect.equals("hello", reader.readString());

          Expect.equals(3, reader.selectName(options));
          Expect.isTrue(reader.readBool());

          Expect.equals(4, reader.selectName(options));
          reader.readNull();

          Expect.isFalse(reader.hasNext());
          reader.endObject();
          Expect.equals(JsonTokenType.endOfDocument, reader.peek());

          // Array with mixed items
          final arrJson = "$w1[$w2 100$w3,$w4 200.5$w1,$w2 \"item\"$w3]$w4";
          final arrReader = JsonTokenReader.fromBytes(_b(arrJson));
          arrReader.beginArray();
          Expect.isTrue(arrReader.hasNext());
          Expect.equals(100, arrReader.readInt());
          Expect.isTrue(arrReader.hasNext());
          Expect.equals(200.5, arrReader.readDouble());
          Expect.isTrue(arrReader.hasNext());
          Expect.equals("item", arrReader.readString());
          Expect.isFalse(arrReader.hasNext());
          arrReader.endArray();
          Expect.equals(JsonTokenType.endOfDocument, arrReader.peek());
        }
      }
    }
  }
}

// =============================================================================
// 2. Negative RFC 8259 Syntax Suite (35+ Robust Negative Test Cases)
// =============================================================================

void testNegativeRfc8259SyntaxSuite() {
  final negativeCases = <String, void Function(JsonTokenReader)>{
    // 1. Trailing comma in object before '}'
    '{"a": 1,}': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.endObject();
    },
    // 2. Trailing comma with whitespace before '}'
    '{"a": 1,   }': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.hasNext();
    },
    // 3. Trailing comma with newlines before '}'
    '{"a": 1,\r\n\t}': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.peek();
    },
    // 4. Trailing comma in multi-key object
    '{"a": 1, "b": 2,}': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.nextName();
      r.readInt();
      r.endObject();
    },
    // 5. Trailing comma in array before ']'
    '[1, 2,]': (r) {
      r.beginArray();
      r.readInt();
      r.readInt();
      r.endArray();
    },
    // 6. Trailing comma in array with whitespace
    '[1, 2,   ]': (r) {
      r.beginArray();
      r.readInt();
      r.readInt();
      r.hasNext();
    },
    // 7. Trailing comma in array with newlines
    '[\n1,\n2,\n]': (r) {
      r.beginArray();
      r.readInt();
      r.readInt();
      r.peek();
    },
    // 8. Double comma in object
    '{"a": 1,, "b": 2}': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.nextName();
    },
    // 9. Double comma with whitespace in object
    '{"a": 1,  , "b": 2}': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.nextName();
    },
    // 10. Double comma in array
    '[1,, 2]': (r) {
      r.beginArray();
      r.readInt();
      r.readInt();
    },
    // 11. Double comma with whitespace in array
    '[1,  , 2]': (r) {
      r.beginArray();
      r.readInt();
      r.readInt();
    },
    // 12. Leading comma in array
    '[, 1, 2]': (r) {
      r.beginArray();
      r.readInt();
    },
    // 13. Leading comma in object
    '{, "a": 1}': (r) {
      r.beginObject();
      r.nextName();
    },
    // 14. Comma only in array
    '[,]': (r) {
      r.beginArray();
      r.readInt();
    },
    // 15. Comma only in object
    '{,}': (r) {
      r.beginObject();
      r.nextName();
    },
    // 16. Missing comma between object properties
    '{"a": 1 "b": 2}': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.nextName();
    },
    // 17. Missing comma between string properties
    '{"a": "hello" "b": "world"}': (r) {
      r.beginObject();
      r.nextName();
      r.readString();
      r.nextName();
    },
    // 18. Missing comma between array elements
    '[1 2 3]': (r) {
      r.beginArray();
      r.readInt();
      r.readInt();
    },
    // 19. Missing comma between array string elements
    '["a" "b"]': (r) {
      r.beginArray();
      r.readString();
      r.readString();
    },
    // 20. Missing comma between array double elements
    '[1.5 2.5]': (r) {
      r.beginArray();
      r.readDouble();
      r.readDouble();
    },
    // 21. Mismatched delimiter in object (colon after value)
    '{"a": 1:}': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.endObject();
    },
    // 22. Mismatched delimiter in object (bracket after value)
    '{"a": 1]}': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.endObject();
    },
    // 23. Mismatched delimiter in array (brace after value)
    '[1, 2}': (r) {
      r.beginArray();
      r.readInt();
      r.readInt();
      r.endArray();
    },
    // 24. Missing colon in object
    '{"a" 123}': (r) {
      r.beginObject();
      r.nextName();
    },
    // 25. Double colon in object
    '{"a":: 123}': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
    },
    // 26. Colon without key in object
    '{: 123}': (r) {
      r.beginObject();
      r.nextName();
    },
    // 27. Colon in array
    '[1: 2]': (r) {
      r.beginArray();
      r.readInt();
    },
    // 28. Trailing colon at EOF
    '{"a":': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
    },
    // 29. Trailing comma at EOF in object
    '{"a": 1,': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.hasNext();
    },
    // 30. Trailing comma at EOF in array
    '[1, 2,': (r) {
      r.beginArray();
      r.readInt();
      r.readInt();
      r.hasNext();
    },
    // 31. Truncated number after comma
    '[1, -': (r) {
      r.beginArray();
      r.readInt();
      r.readInt();
    },
    // 32. Invalid trailing char after number
    '{"a": 123x}': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
    },
    // 33. Invalid trailing char after string
    '{"a": "hello"x}': (r) {
      r.beginObject();
      r.nextName();
      r.readString();
      r.endObject();
    },
    // 34. Unterminated string as key
    '{"unterminated: 1}': (r) {
      r.beginObject();
      r.nextName();
    },
    // 35. Unterminated string as value
    '{"a": "unterminated}': (r) {
      r.beginObject();
      r.nextName();
      r.readString();
    },
    // 36. Trailing comma at EOF via getTokenSpan()
    '{"a": 1, ': (r) {
      r.beginObject();
      r.nextName();
      r.readInt();
      r.getTokenSpan();
    },
  };

  Expect.isTrue(negativeCases.length >= 25);

  negativeCases.forEach((json, action) {
    final reader = JsonTokenReader.fromBytes(_b(json));
    Expect.throwsFormatException(
      () => action(reader),
      'Expected FormatException for invalid JSON: $json',
    );

    // Also assert jsonUtf8Decode throws FormatException
    Expect.throwsFormatException(
      () => jsonUtf8Decode(_b(json)),
      'Expected FormatException from jsonUtf8Decode for: $json',
    );
  });
}

// =============================================================================
// 3. Delimiter-Fused Typed Reads
// =============================================================================

void testDelimiterFusedTypedReads() {
  // Test reading arrays of primitives directly without intermediate hasNext checks
  final numbersJson = '[10, 20, 30, 40, 50]';
  final rNum = JsonTokenReader.fromBytes(_b(numbersJson));
  rNum.beginArray();
  Expect.equals(10, rNum.readInt());
  Expect.equals(20, rNum.readInt());
  Expect.equals(30, rNum.readInt());
  Expect.equals(40, rNum.readInt());
  Expect.equals(50, rNum.readInt());
  rNum.endArray();

  final doublesJson = '[1.1, 2.2, 3.3, 4.4, 5.5]';
  final rDbl = JsonTokenReader.fromBytes(_b(doublesJson));
  rDbl.beginArray();
  Expect.equals(1.1, rDbl.readDouble());
  Expect.equals(2.2, rDbl.readDouble());
  Expect.equals(3.3, rDbl.readDouble());
  Expect.equals(4.4, rDbl.readDouble());
  Expect.equals(5.5, rDbl.readDouble());
  rDbl.endArray();

  final stringsJson = '["alpha", "beta", "gamma"]';
  final rStr = JsonTokenReader.fromBytes(_b(stringsJson));
  rStr.beginArray();
  Expect.equals("alpha", rStr.readString());
  Expect.equals("beta", rStr.readString());
  Expect.equals("gamma", rStr.readString());
  rStr.endArray();

  // Test reading enum values via selectString with fused delimiter
  final enumOptions = JsonKeyOptions.of(["low", "medium", "high"]);
  final enumJson = '["medium", "high", "low"]';
  final rEnum = JsonTokenReader.fromBytes(_b(enumJson));
  rEnum.beginArray();
  Expect.equals(1, rEnum.selectString(enumOptions));
  Expect.equals(2, rEnum.selectString(enumOptions));
  Expect.equals(0, rEnum.selectString(enumOptions));
  rEnum.endArray();
}

// =============================================================================
// 4. selectName Colon & Whitespace Fusing
// =============================================================================

void testSelectNameColonAndWhitespaceFusing() {
  final keys = ["id", "name", "active", "rating", "tags"];
  final options = JsonKeyOptions.of(keys);

  // Varied whitespace around colons and commas
  final json =
      '{"id":123,"name"  :  "Widget"  ,  "active":true,"rating" : 4.8,"tags":["a","b"]}';
  final reader = JsonTokenReader.fromBytes(_b(json));

  reader.beginObject();
  Expect.equals(0, reader.selectName(options));
  Expect.equals(123, reader.readInt());

  Expect.equals(1, reader.selectName(options));
  Expect.equals("Widget", reader.readString());

  Expect.equals(2, reader.selectName(options));
  Expect.isTrue(reader.readBool());

  Expect.equals(3, reader.selectName(options));
  Expect.equals(4.8, reader.readDouble());

  Expect.equals(4, reader.selectName(options));
  reader.beginArray();
  Expect.equals("a", reader.readString());
  Expect.equals("b", reader.readString());
  reader.endArray();

  Expect.isFalse(reader.hasNext());
  reader.endObject();
}

// =============================================================================
// 5. 10,000-Case Differential Fuzzer
// =============================================================================

Object? _decodeAny(JsonTokenReader reader) {
  final token = reader.peek();
  switch (token) {
    case JsonTokenType.beginObject:
      reader.beginObject();
      final map = <String, Object?>{};
      while (reader.hasNext()) {
        final key = reader.nextName();
        final value = _decodeAny(reader);
        map[key] = value;
      }
      reader.endObject();
      return map;
    case JsonTokenType.beginArray:
      reader.beginArray();
      final list = <Object?>[];
      while (reader.hasNext()) {
        list.add(_decodeAny(reader));
      }
      reader.endArray();
      return list;
    case JsonTokenType.string:
      return reader.readString();
    case JsonTokenType.number:
      return reader.readNum();
    case JsonTokenType.boolean:
      return reader.readBool();
    case JsonTokenType.nullValue:
      reader.readNull();
      return null;
    default:
      throw FormatException('Unexpected token: $token');
  }
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is num && b is num) {
    if (a.isNaN && b.isNaN) return true;
    return a == b;
  }
  if (a is String && b is String) return a == b;
  if (a is bool && b is bool) return a == b;
  if (a == null && b == null) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_deepEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  return false;
}

String _randomWs(Random rnd) {
  const wsChars = ["", " ", "  ", "\t", "\n", "\r\n", " \t "];
  return wsChars[rnd.nextInt(wsChars.length)];
}

String _generateRandomJson(Random rnd, int depth) {
  final ws1 = _randomWs(rnd);
  final ws2 = _randomWs(rnd);
  final ws3 = _randomWs(rnd);

  if (depth >= 4 || rnd.nextInt(10) < 4) {
    // Primitive
    final kind = rnd.nextInt(5);
    switch (kind) {
      case 0:
        // Int
        final val = rnd.nextInt(2000000) - 1000000;
        return "$ws1$val$ws2";
      case 1:
        // Double
        final val = (rnd.nextDouble() * 2000.0) - 1000.0;
        return "$ws1${val.toStringAsFixed(4)}$ws2";
      case 2:
        // String
        final strChoices = [
          "hello",
          "world",
          "dart",
          "wasm",
          "fuzz_test",
          "",
          "line\\nbreak",
          "quote\\\"test",
        ];
        return '$ws1"${strChoices[rnd.nextInt(strChoices.length)]}"$ws2';
      case 3:
        // Bool
        return "$ws1${rnd.nextBool()}$ws2";
      case 4:
      default:
        // Null
        return "${ws1}null$ws2";
    }
  }

  if (rnd.nextBool()) {
    // Object
    final count = rnd.nextInt(5);
    final sb = StringBuffer("$ws1{");
    for (var i = 0; i < count; i++) {
      if (i > 0) sb.write(",");
      final key = "key_${rnd.nextInt(100)}";
      sb.write('$ws2"$key"$ws3:$ws1${_generateRandomJson(rnd, depth + 1)}');
    }
    sb.write("$ws2}$ws3");
    return sb.toString();
  } else {
    // Array
    final count = rnd.nextInt(5);
    final sb = StringBuffer("$ws1[");
    for (var i = 0; i < count; i++) {
      if (i > 0) sb.write(",");
      sb.write(_generateRandomJson(rnd, depth + 1));
    }
    sb.write("$ws2]$ws3");
    return sb.toString();
  }
}

void testDifferentialFuzzer10kCases() {
  final rnd = Random(42);
  const totalIterations = 10000;

  for (var i = 0; i < totalIterations; i++) {
    final jsonStr = _generateRandomJson(rnd, 0);
    final bytes = _b(jsonStr);

    // 1. Standard library jsonDecode
    final expected = jsonDecode(jsonStr);

    // 2. JsonUtf8Decoder.convert
    final decodedUtf8 = jsonUtf8Decode(bytes);
    Expect.isTrue(
      _deepEquals(expected, decodedUtf8),
      "Mismatch in jsonUtf8Decode at iteration $i for: $jsonStr",
    );

    // 3. JsonTokenReader pull parser
    final reader = JsonTokenReader.fromBytes(bytes);
    final readerResult = _decodeAny(reader);
    Expect.equals(JsonTokenType.endOfDocument, reader.peek());
    Expect.isTrue(
      _deepEquals(expected, readerResult),
      "Mismatch in JsonTokenReader at iteration $i for: $jsonStr",
    );
  }
}
