// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of "dart:convert";

/// Top-level combined codec for UTF-8 JSON encoding and decoding.
const JsonUtf8Codec jsonUtf8 = JsonUtf8Codec();

/// Decodes the UTF-8 encoded JSON [bytes] directly to a Dart object.
///
/// Shorthand for `jsonUtf8.decode(bytes)`.
Object? jsonUtf8Decode(
  List<int> bytes, {
  Object? Function(Object? key, Object? value)? reviver,
  bool allowMalformed = false,
}) => JsonUtf8Decoder(reviver, allowMalformed).convert(bytes);

/// Converts [value] directly to UTF-8 encoded JSON bytes as a [Uint8List].
///
/// Shorthand for `jsonUtf8.encode(value)`.
Uint8List jsonUtf8Encode(
  Object? value, {
  Object? Function(dynamic object)? toEncodable,
}) {
  final res = JsonUtf8Encoder(null, toEncodable).convert(value);
  return res is Uint8List ? res : Uint8List.fromList(res);
}

/// JSON token structural type discriminator.
enum JsonTokenType {
  none,
  beginObject,
  endObject,
  beginArray,
  endArray,
  propertyName,
  string,
  number,
  boolean,
  nullValue,
  endOfDocument,
}

/// Pre-compiled set of ASCII key names or enum strings for O(1) matching in pull parsers.
final class JsonKeyOptions {
  final List<String> keys;
  final Uint8List encodedKeys;
  final Int32List offsets;
  final Int32List lengths;
  final Int32List _hashTable;
  final int _hashMask;

  JsonKeyOptions._(
    this.keys,
    this.encodedKeys,
    this.offsets,
    this.lengths,
    this._hashTable,
    this._hashMask,
  );

  /// Pre-computes UTF-8 byte representations and length tables for [keys].
  factory JsonKeyOptions.of(List<String> keys) {
    if (keys.isEmpty) {
      throw ArgumentError.value(keys, 'keys', 'Must not be empty');
    }
    final builder = BytesBuilder(copy: false);
    final offsets = Int32List(keys.length);
    final lengths = Int32List(keys.length);

    for (var i = 0; i < keys.length; i++) {
      offsets[i] = builder.length;
      final encoded = utf8.encode(keys[i]);
      lengths[i] = encoded.length;
      builder.add(encoded);
    }
    final encodedKeys = builder.takeBytes();

    var tableSize = 8;
    while (tableSize < keys.length * 2) {
      tableSize <<= 1;
    }
    final mask = tableSize - 1;
    final table = Int32List(tableSize)..fillRange(0, tableSize, -1);

    for (var i = 0; i < keys.length; i++) {
      final off = offsets[i];
      final len = lengths[i];
      var h = 0x811c9dc5;
      for (var j = 0; j < len; j++) {
        h = _imul32(h ^ encodedKeys[off + j], 0x01000193);
      }
      var slot = h & mask;
      while (table[slot] != -1) {
        final existing = table[slot];
        if (lengths[existing] == len) {
          final existingOff = offsets[existing];
          var match = true;
          for (var j = 0; j < len; j++) {
            if (encodedKeys[existingOff + j] != encodedKeys[off + j]) {
              match = false;
              break;
            }
          }
          if (match) break; // duplicate, keep first
        }
        slot = (slot + 1) & mask;
      }
      if (table[slot] == -1) {
        table[slot] = i;
      }
    }

    return JsonKeyOptions._(
      List.unmodifiable(keys),
      encodedKeys.asUnmodifiableView(),
      offsets.asUnmodifiableView(),
      lengths.asUnmodifiableView(),
      table,
      mask,
    );
  }

  int get length => keys.length;

  /// Matches the byte span `[start..end]` against pre-compiled keys in O(1).
  int selectKey(Uint8List source, int start, int end) {
    if (start < 0 || end > source.length || start > end) {
      return -1;
    }
    final spanLen = end - start;
    var h = 0x811c9dc5;
    for (var i = start; i < end; i++) {
      h = _imul32(h ^ source[i], 0x01000193);
    }
    final mask = _hashMask;
    var slot = h & mask;
    while (true) {
      final idx = _hashTable[slot];
      if (idx == -1) return -1;
      if (lengths[idx] == spanLen) {
        final off = offsets[idx];
        var match = true;
        for (var j = 0; j < spanLen; j++) {
          if (source[start + j] != encodedKeys[off + j]) {
            match = false;
            break;
          }
        }
        if (match) return idx;
      }
      slot = (slot + 1) & mask;
    }
  }
}

/// A combined [Codec] for encoding objects to UTF-8 JSON bytes and decoding
/// UTF-8 JSON bytes directly into Dart objects.
final class JsonUtf8Codec extends Codec<Object?, List<int>> {
  /// Indentation string used for pretty-printing, or `null` for compact output.
  final String? indent;

  /// Function called for objects that do not have a native JSON representation.
  final dynamic Function(dynamic object)? toEncodable;

  /// Reviver function applied to decoded key/value pairs.
  final Object? Function(Object? key, Object? value)? reviver;

  /// Whether the decoder allows malformed UTF-8 byte sequences.
  final bool allowMalformed;

  /// Buffer size used for chunked conversion.
  final int? bufferSize;

  /// Creates a [JsonUtf8Codec] with the given configuration.
  const JsonUtf8Codec({
    this.indent,
    this.toEncodable,
    this.reviver,
    this.allowMalformed = false,
    this.bufferSize,
  });

  @override
  JsonUtf8Encoder get encoder =>
      JsonUtf8Encoder(indent, toEncodable, bufferSize);

  @override
  JsonUtf8Decoder get decoder => JsonUtf8Decoder(reviver, allowMalformed);

  @override
  Object? decode(
    List<int> encoded, {
    Object? Function(Object? key, Object? value)? reviver,
    bool? allowMalformed,
  }) {
    if (reviver != null || allowMalformed != null) {
      return JsonUtf8Decoder(
        reviver ?? this.reviver,
        allowMalformed ?? this.allowMalformed,
      ).convert(encoded);
    }
    return decoder.convert(encoded);
  }

  @override
  Uint8List encode(
    Object? value, {
    Object? Function(dynamic object)? toEncodable,
  }) {
    if (toEncodable != null) {
      return JsonUtf8Encoder(indent, toEncodable, bufferSize).convert(value);
    }
    return encoder.convert(value);
  }
}

/// A [Converter] that decodes UTF-8 encoded JSON bytes directly into Dart
/// objects without creating an intermediate [String].
final class JsonUtf8Decoder extends Converter<List<int>, Object?> {
  /// Reviver function applied to decoded key/value pairs, or `null`.
  final Object? Function(Object? key, Object? value)? reviver;

  /// Whether the decoder allows malformed UTF-8 byte sequences.
  final bool allowMalformed;

  /// Creates a [JsonUtf8Decoder].
  const JsonUtf8Decoder([this.reviver, this.allowMalformed = false]);

  @override
  Object? convert(List<int> input) {
    final bytes = input is Uint8List ? input : Uint8List.fromList(input);
    final reader = JsonTokenReader.fromBytes(
      bytes,
      allowMalformed: allowMalformed,
    );
    final rev = reviver;
    final result = _parseValueFromReader(reader, rev);
    if (reader.peek() != JsonTokenType.endOfDocument) {
      throw FormatException('Unexpected extra data after JSON value');
    }
    return rev != null ? rev(null, result) : result;
  }

  @override
  ChunkedConversionSink<List<int>> startChunkedConversion(Sink<Object?> sink) {
    return Utf8Decoder(
      allowMalformed: allowMalformed,
    ).startChunkedConversion(JsonDecoder(reviver).startChunkedConversion(sink));
  }

  // --- Static Low-Level Zero-Allocation Span Parsing Helpers ---

  /// Parses a 64-bit IEEE-754 double directly from a UTF-8 byte span
  /// `[start..end]` without allocating an intermediate [String].
  static double parseDouble(Uint8List bytes, int start, int end) {
    final res = tryParseDouble(bytes, start, end);
    if (res == null) {
      throw FormatException(
        'Invalid double in byte span [$start, $end)',
        bytes,
        start,
      );
    }
    return res;
  }

  /// Parses a 64-bit IEEE-754 double directly from a UTF-8 byte span
  /// `[start..end]`. Returns `null` if the byte slice is not a valid number.
  static double? tryParseDouble(Uint8List bytes, int start, int end) {
    return _tryParseDoubleUtf8(bytes, start, end);
  }

  /// Parses a 64-bit signed integer directly from a base-10 UTF-8 byte span
  /// `[start..end]` without allocating an intermediate [String].
  static int parseInt(Uint8List bytes, int start, int end) {
    final res = tryParseInt(bytes, start, end);
    if (res == null) {
      throw FormatException(
        'Invalid integer in byte span [$start, $end)',
        bytes,
        start,
      );
    }
    return res;
  }

  /// Parses a 64-bit signed integer directly from a base-10 UTF-8 byte span
  /// `[start..end]`. Returns `null` if the byte slice is not a valid integer.
  static int? tryParseInt(Uint8List bytes, int start, int end) {
    return _tryParseIntUtf8(bytes, start, end);
  }

  /// Parses a boolean literal (`true` or `false`) from byte span `[start..end]`.
  static bool parseBool(Uint8List bytes, int start, int end) {
    final res = tryParseBool(bytes, start, end);
    if (res == null) {
      throw FormatException(
        'Invalid boolean in byte span [$start, $end)',
        bytes,
        start,
      );
    }
    return res;
  }

  /// Parses a boolean literal from byte span `[start..end]`, or `null` if invalid.
  static bool? tryParseBool(Uint8List bytes, int start, int end) {
    return _tryParseBoolUtf8(bytes, start, end);
  }

  /// Returns `true` if the byte span `[start..end]` equals `null`.
  static bool isNull(Uint8List bytes, int start, int end) {
    return _isNullUtf8(bytes, start, end);
  }

  /// Compares the UTF-8 byte span `bytes[start..end]` directly against an ASCII
  /// [candidate] string without allocating a [String] instance.
  static bool equalsAscii(
    Uint8List bytes,
    int start,
    int end,
    String candidate,
  ) {
    return _equalsAsciiUtf8(bytes, start, end, candidate);
  }

  /// Matches the UTF-8 byte span `bytes[start..end]` against [options] in O(1)
  /// using pre-hashed lengths and bytes. Returns the matching index, or `-1`.
  static int matchKey(
    Uint8List bytes,
    int start,
    int end,
    JsonKeyOptions options,
  ) {
    if (start < 0 || end > bytes.length || start > end) return -1;
    if (_isVerbatimUtf8(bytes, start, end)) {
      return options.selectKey(bytes, start, end);
    }
    final unescaped = _decodeStringUtf8(bytes, start, end);
    return options.keys.indexOf(unescaped);
  }

  /// Returns `true` if the string literal byte span `bytes[start..end]` contains
  /// no backslash escape characters (`\`), enabling fast zero-copy decoding.
  static bool isVerbatim(Uint8List bytes, int start, int end) {
    return _isVerbatimUtf8(bytes, start, end);
  }

  /// Decodes and unescapes a JSON string literal byte span `bytes[start..end]`
  /// directly into a Dart [String], resolving standard JSON escape sequences.
  static String decodeString(
    Uint8List bytes,
    int start,
    int end, {
    bool allowMalformed = false,
  }) {
    return _decodeStringUtf8(bytes, start, end, allowMalformed: allowMalformed);
  }

  /// Scans [bytes] starting at [offset] and returns the end byte offset of the
  /// complete JSON value (skipping nested objects, arrays, and strings).
  static int skipValue(Uint8List bytes, int offset) {
    if (offset < 0 || offset > bytes.length) {
      throw RangeError.range(offset, 0, bytes.length, 'offset');
    }
    var i = offset;
    while (i < bytes.length &&
        (bytes[i] == 0x20 ||
            bytes[i] == 0x09 ||
            bytes[i] == 0x0A ||
            bytes[i] == 0x0D)) {
      i++;
    }
    if (i >= bytes.length) return i;
    final b = bytes[i];
    if (b == 123 || b == 91) {
      // object or array
      var depth = 1;
      var maskLo = (b == 123) ? 1 : 0;
      var maskHi = 0;
      var hasElementsLo = 0;
      var hasElementsHi = 0;
      var stateLo0 = 0;
      var stateLo1 = 0;
      var stateHi0 = 0;
      var stateHi1 = 0;
      i++;

      while (i < bytes.length && depth > 0) {
        while (i < bytes.length &&
            (bytes[i] == 0x20 ||
                bytes[i] == 0x09 ||
                bytes[i] == 0x0A ||
                bytes[i] == 0x0D)) {
          i++;
        }
        if (i >= bytes.length) break;

        final c = bytes[i];
        final d = depth - 1;
        final isObject = (d < 32)
            ? (((maskLo >> d) & 1) == 1)
            : (((maskHi >> (d - 32)) & 1) == 1);
        final hasElements = (d < 32)
            ? (((hasElementsLo >> d) & 1) == 1)
            : (((hasElementsHi >> (d - 32)) & 1) == 1);
        final st = (d < 16)
            ? ((stateLo0 >> (d << 1)) & 3)
            : (d < 32)
            ? ((stateLo1 >> ((d - 16) << 1)) & 3)
            : (d < 48)
            ? ((stateHi0 >> ((d - 32) << 1)) & 3)
            : ((stateHi1 >> ((d - 48) << 1)) & 3);

        if (c == 125 || c == 93) {
          if (c == 125) {
            if (!isObject) {
              throw FormatException('Mismatched "}" at offset $i', bytes, i);
            }
          } else {
            if (isObject) {
              throw FormatException('Mismatched "]" at offset $i', bytes, i);
            }
          }
          if (st == 3) {
            // Valid close after value
          } else if (st == 0) {
            if (hasElements) {
              final closeChar = isObject ? '"}"' : '"]"';
              throw FormatException(
                'Trailing comma before $closeChar at offset $i',
                bytes,
                i,
              );
            }
            // Valid close of empty container: [] or {}
          } else if (st == 1) {
            throw FormatException('Expected ":" at offset $i', bytes, i);
          } else {
            throw FormatException(
              'Expected value in object at offset $i',
              bytes,
              i,
            );
          }
          i++;
          depth--;
          if (depth > 0) {
            final pd = depth - 1;
            if (pd < 32) {
              hasElementsLo |= (1 << pd);
            } else {
              hasElementsHi |= (1 << (pd - 32));
            }
            if (pd < 16) {
              final shift = pd << 1;
              stateLo0 = (stateLo0 & ~(3 << shift)) | (3 << shift);
            } else if (pd < 32) {
              final shift = (pd - 16) << 1;
              stateLo1 = (stateLo1 & ~(3 << shift)) | (3 << shift);
            } else if (pd < 48) {
              final shift = (pd - 32) << 1;
              stateHi0 = (stateHi0 & ~(3 << shift)) | (3 << shift);
            } else {
              final shift = (pd - 48) << 1;
              stateHi1 = (stateHi1 & ~(3 << shift)) | (3 << shift);
            }
          }
        } else if (c == 44) {
          if (st != 3) {
            if (st == 0) {
              throw FormatException(
                'Unexpected "," in container at offset $i',
                bytes,
                i,
              );
            } else if (st == 1) {
              throw FormatException('Expected ":" at offset $i', bytes, i);
            } else {
              throw FormatException(
                'Expected value before "," at offset $i',
                bytes,
                i,
              );
            }
          }
          i++;
          if (d < 32) {
            hasElementsLo |= (1 << d);
          } else {
            hasElementsHi |= (1 << (d - 32));
          }
          if (d < 16) {
            final shift = d << 1;
            stateLo0 &= ~(3 << shift);
          } else if (d < 32) {
            final shift = (d - 16) << 1;
            stateLo1 &= ~(3 << shift);
          } else if (d < 48) {
            final shift = (d - 32) << 1;
            stateHi0 &= ~(3 << shift);
          } else {
            final shift = (d - 48) << 1;
            stateHi1 &= ~(3 << shift);
          }
        } else if (c == 58) {
          if (!isObject || st != 1) {
            throw FormatException('Unexpected ":" at offset $i', bytes, i);
          }
          i++;
          if (d < 16) {
            final shift = d << 1;
            stateLo0 = (stateLo0 & ~(3 << shift)) | (2 << shift);
          } else if (d < 32) {
            final shift = (d - 16) << 1;
            stateLo1 = (stateLo1 & ~(3 << shift)) | (2 << shift);
          } else if (d < 48) {
            final shift = (d - 32) << 1;
            stateHi0 = (stateHi0 & ~(3 << shift)) | (2 << shift);
          } else {
            final shift = (d - 48) << 1;
            stateHi1 = (stateHi1 & ~(3 << shift)) | (2 << shift);
          }
        } else if (c == 34) {
          if (isObject) {
            if (st == 0) {
              // String is a property key
              i++;
              var closed = false;
              while (i < bytes.length) {
                final sc = bytes[i];
                if (sc < 0x20) {
                  throw FormatException(
                    'Unescaped control character in string literal at offset $i',
                    bytes,
                    i,
                  );
                }
                if (sc == 92) {
                  i = _validateEscape(bytes, i + 1, bytes.length);
                } else if (sc == 34) {
                  i++;
                  closed = true;
                  break;
                } else {
                  i++;
                }
              }
              if (!closed) {
                throw FormatException(
                  'Unterminated string literal at offset $i',
                  bytes,
                  i,
                );
              }
              if (d < 16) {
                final shift = d << 1;
                stateLo0 = (stateLo0 & ~(3 << shift)) | (1 << shift);
              } else if (d < 32) {
                final shift = (d - 16) << 1;
                stateLo1 = (stateLo1 & ~(3 << shift)) | (1 << shift);
              } else if (d < 48) {
                final shift = (d - 32) << 1;
                stateHi0 = (stateHi0 & ~(3 << shift)) | (1 << shift);
              } else {
                final shift = (d - 48) << 1;
                stateHi1 = (stateHi1 & ~(3 << shift)) | (1 << shift);
              }
            } else if (st == 2) {
              // String is a property value
              i++;
              var closed = false;
              while (i < bytes.length) {
                final sc = bytes[i];
                if (sc < 0x20) {
                  throw FormatException(
                    'Unescaped control character in string literal at offset $i',
                    bytes,
                    i,
                  );
                }
                if (sc == 92) {
                  i = _validateEscape(bytes, i + 1, bytes.length);
                } else if (sc == 34) {
                  i++;
                  closed = true;
                  break;
                } else {
                  i++;
                }
              }
              if (!closed) {
                throw FormatException(
                  'Unterminated string literal at offset $i',
                  bytes,
                  i,
                );
              }
              if (d < 32) {
                hasElementsLo |= (1 << d);
              } else {
                hasElementsHi |= (1 << (d - 32));
              }
              if (d < 16) {
                final shift = d << 1;
                stateLo0 = (stateLo0 & ~(3 << shift)) | (3 << shift);
              } else if (d < 32) {
                final shift = (d - 16) << 1;
                stateLo1 = (stateLo1 & ~(3 << shift)) | (3 << shift);
              } else if (d < 48) {
                final shift = (d - 32) << 1;
                stateHi0 = (stateHi0 & ~(3 << shift)) | (3 << shift);
              } else {
                final shift = (d - 48) << 1;
                stateHi1 = (stateHi1 & ~(3 << shift)) | (3 << shift);
              }
            } else if (st == 1) {
              throw FormatException('Expected ":" at offset $i', bytes, i);
            } else {
              throw FormatException(
                'Expected "," or "}" at offset $i',
                bytes,
                i,
              );
            }
          } else {
            // Array element
            if (st == 0 || st == 2) {
              i++;
              var closed = false;
              while (i < bytes.length) {
                final sc = bytes[i];
                if (sc < 0x20) {
                  throw FormatException(
                    'Unescaped control character in string literal at offset $i',
                    bytes,
                    i,
                  );
                }
                if (sc == 92) {
                  i = _validateEscape(bytes, i + 1, bytes.length);
                } else if (sc == 34) {
                  i++;
                  closed = true;
                  break;
                } else {
                  i++;
                }
              }
              if (!closed) {
                throw FormatException(
                  'Unterminated string literal at offset $i',
                  bytes,
                  i,
                );
              }
              if (d < 32) {
                hasElementsLo |= (1 << d);
              } else {
                hasElementsHi |= (1 << (d - 32));
              }
              if (d < 16) {
                final shift = d << 1;
                stateLo0 = (stateLo0 & ~(3 << shift)) | (3 << shift);
              } else if (d < 32) {
                final shift = (d - 16) << 1;
                stateLo1 = (stateLo1 & ~(3 << shift)) | (3 << shift);
              } else if (d < 48) {
                final shift = (d - 32) << 1;
                stateHi0 = (stateHi0 & ~(3 << shift)) | (3 << shift);
              } else {
                final shift = (d - 48) << 1;
                stateHi1 = (stateHi1 & ~(3 << shift)) | (3 << shift);
              }
            } else {
              throw FormatException(
                'Expected "," or "]" at offset $i',
                bytes,
                i,
              );
            }
          }
        } else if (c == 123 || c == 91) {
          if (isObject) {
            if (st == 0) {
              throw FormatException(
                'Expected string key in object at offset $i',
                bytes,
                i,
              );
            } else if (st == 1) {
              throw FormatException('Expected ":" at offset $i', bytes, i);
            } else if (st == 3) {
              throw FormatException(
                'Expected "," or "}" at offset $i',
                bytes,
                i,
              );
            }
          } else {
            if (st == 3) {
              throw FormatException(
                'Expected "," or "]" at offset $i',
                bytes,
                i,
              );
            }
          }

          if (depth >= 64) {
            throw FormatException(
              'Nesting depth exceeds limit of 64 at offset $i',
              bytes,
              i,
            );
          }

          final newIsObj = (c == 123);
          final nd = depth;
          if (nd < 32) {
            if (newIsObj) {
              maskLo |= (1 << nd);
            } else {
              maskLo &= ~(1 << nd);
            }
            hasElementsLo &= ~(1 << nd);
          } else {
            final shift = nd - 32;
            if (newIsObj) {
              maskHi |= (1 << shift);
            } else {
              maskHi &= ~(1 << shift);
            }
            hasElementsHi &= ~(1 << shift);
          }

          if (nd < 16) {
            final shift = nd << 1;
            stateLo0 &= ~(3 << shift);
          } else if (nd < 32) {
            final shift = (nd - 16) << 1;
            stateLo1 &= ~(3 << shift);
          } else if (nd < 48) {
            final shift = (nd - 32) << 1;
            stateHi0 &= ~(3 << shift);
          } else {
            final shift = (nd - 48) << 1;
            stateHi1 &= ~(3 << shift);
          }

          depth++;
          i++;
        } else {
          if (isObject) {
            if (st == 0) {
              throw FormatException(
                'Expected string key in object at offset $i',
                bytes,
                i,
              );
            } else if (st == 1) {
              throw FormatException('Expected ":" at offset $i', bytes, i);
            } else if (st == 3) {
              throw FormatException(
                'Expected "," or "}" at offset $i',
                bytes,
                i,
              );
            }
          } else {
            if (st == 3) {
              throw FormatException(
                'Expected "," or "]" at offset $i',
                bytes,
                i,
              );
            }
          }

          i = _skipScalar(bytes, i);

          if (d < 32) {
            hasElementsLo |= (1 << d);
          } else {
            hasElementsHi |= (1 << (d - 32));
          }
          if (d < 16) {
            final shift = d << 1;
            stateLo0 = (stateLo0 & ~(3 << shift)) | (3 << shift);
          } else if (d < 32) {
            final shift = (d - 16) << 1;
            stateLo1 = (stateLo1 & ~(3 << shift)) | (3 << shift);
          } else if (d < 48) {
            final shift = (d - 32) << 1;
            stateHi0 = (stateHi0 & ~(3 << shift)) | (3 << shift);
          } else {
            final shift = (d - 48) << 1;
            stateHi1 = (stateHi1 & ~(3 << shift)) | (3 << shift);
          }
        }
      }

      if (depth > 0) {
        throw FormatException(
          'Unclosed container at offset $offset',
          bytes,
          offset,
        );
      }
      return i;
    }
    if (b == 34) {
      i++;
      var closed = false;
      while (i < bytes.length) {
        final c = bytes[i];
        if (c < 0x20) {
          throw FormatException(
            'Unescaped control character in string literal at offset $i',
            bytes,
            i,
          );
        }
        if (c == 92) {
          i = _validateEscape(bytes, i + 1, bytes.length);
        } else if (c == 34) {
          i++;
          closed = true;
          break;
        } else {
          i++;
        }
      }
      if (!closed) {
        throw FormatException('Unterminated string literal', bytes, offset);
      }
      return i;
    }
    return _skipScalar(bytes, i);
  }

  /// Fast-skips JSON whitespace (0x20, 0x09, 0x0A, 0x0D) starting at [offset]
  /// and returns the offset of the next non-whitespace byte.
  static int skipWhitespace(Uint8List bytes, int offset) {
    if (offset < 0 || offset > bytes.length) {
      throw RangeError.range(offset, 0, bytes.length, 'offset');
    }
    var i = offset;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D) {
        i++;
      } else {
        break;
      }
    }
    return i;
  }

  /// Scans forward from [offset] past an unescaped closing quote (") without
  /// parsing escapes, returning the byte offset after the closing quote.
  static int skipString(Uint8List bytes, int offset) {
    if (offset < 0 || offset >= bytes.length) {
      throw RangeError.range(
        offset,
        0,
        bytes.length == 0 ? 0 : bytes.length - 1,
        'offset',
      );
    }
    var i = offset;
    if (i < bytes.length && bytes[i] == 34) {
      i++;
    } else {
      throw FormatException('Expected """ at offset $offset', bytes, offset);
    }
    var closed = false;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b < 0x20) {
        throw FormatException(
          'Unescaped control character in string literal at offset $i',
          bytes,
          i,
        );
      }
      if (b == 92) {
        i = _validateEscape(bytes, i + 1, bytes.length);
      } else if (b == 34) {
        i++;
        closed = true;
        break;
      } else {
        i++;
      }
    }
    if (!closed) {
      throw FormatException('Unterminated string literal', bytes, offset);
    }
    return i;
  }
}

/// An encoder that encodes an object directly into UTF-8 JSON bytes.
final class JsonUtf8Encoder extends Converter<Object?, List<int>> {
  /// Default buffer size used by the JSON-to-UTF-8 encoder (32 KB).
  static const int _defaultBufferSize = 32768;

  /// Indentation used in pretty-print mode, `null` if not pretty.
  final List<int>? _indent;

  /// Function called with each un-encodable object encountered.
  final Object? Function(dynamic)? _toEncodable;

  /// UTF-8 buffer size.
  final int _bufferSize;

  /// Create converter.
  JsonUtf8Encoder([
    String? indent,
    dynamic Function(dynamic object)? toEncodable,
    int? bufferSize,
  ]) : _indent = _utf8Encode(indent),
       _toEncodable = toEncodable,
       _bufferSize = bufferSize ?? _defaultBufferSize;

  static List<int>? _utf8Encode(String? string) {
    if (string == null) return null;
    if (string.isEmpty) return Uint8List(0);
    checkAscii:
    {
      for (var i = 0; i < string.length; i++) {
        if (string.codeUnitAt(i) >= 0x80) break checkAscii;
      }
      return string.codeUnits;
    }
    return utf8.encode(string);
  }

  @override
  Uint8List convert(Object? object) {
    var bytes = <Uint8List>[];
    void addChunk(Uint8List chunk, int start, int end) {
      if (start > 0 || end < chunk.length) {
        var length = end - start;
        chunk = Uint8List.view(
          chunk.buffer,
          chunk.offsetInBytes + start,
          length,
        );
      }
      bytes.add(chunk);
    }

    _JsonUtf8Stringifier.stringify(
      object,
      _indent,
      _toEncodable,
      _bufferSize,
      addChunk,
    );
    if (bytes.isEmpty) return Uint8List(0);
    if (bytes.length == 1) {
      final first = bytes[0];
      if (first.length < first.buffer.lengthInBytes) {
        return Uint8List.fromList(first);
      }
      return first;
    }
    var length = 0;
    for (var i = 0; i < bytes.length; i++) {
      length += bytes[i].length;
    }
    var result = Uint8List(length);
    for (var i = 0, offset = 0; i < bytes.length; i++) {
      var byteList = bytes[i];
      int end = offset + byteList.length;
      result.setRange(offset, end, byteList);
      offset = end;
    }
    return result;
  }

  @override
  ChunkedConversionSink<Object?> startChunkedConversion(Sink<List<int>> sink) {
    ByteConversionSink byteSink;
    if (sink is ByteConversionSink) {
      byteSink = sink;
    } else {
      byteSink = ByteConversionSink.from(sink);
    }
    return _JsonUtf8EncoderSink(byteSink, _toEncodable, _indent, _bufferSize);
  }

  @override
  Stream<List<int>> bind(Stream<Object?> stream) {
    return super.bind(stream);
  }

  /// Writes [value] with standard JSON escaping directly into [sink].
  static void writeString(String value, BytesBuilder sink) {
    final len = value.length;
    // Fast path: check if string is pure ASCII and requires no escaping
    var isPureAscii = true;
    for (var i = 0; i < len; i++) {
      final c = value.codeUnitAt(i);
      if (c < 0x20 || c == 0x22 || c == 0x5C || c >= 0x80) {
        isPureAscii = false;
        break;
      }
    }

    if (isPureAscii) {
      sink.addByte(0x22); // '"'
      for (var i = 0; i < len; i++) {
        sink.addByte(value.codeUnitAt(i));
      }
      sink.addByte(0x22); // '"'
      return;
    }

    // General path: handle multi-byte UTF-8, escapes, and surrogates
    sink.addByte(0x22); // '"'
    for (var i = 0; i < len; i++) {
      final c = value.codeUnitAt(i);
      switch (c) {
        case 0x22:
          sink.addByte(0x5C);
          sink.addByte(0x22);
          break;
        case 0x5C:
          sink.addByte(0x5C);
          sink.addByte(0x5C);
          break;
        case 0x08:
          sink.addByte(0x5C);
          sink.addByte(0x62); // 'b'
          break;
        case 0x0C:
          sink.addByte(0x5C);
          sink.addByte(0x66); // 'f'
          break;
        case 0x0A:
          sink.addByte(0x5C);
          sink.addByte(0x6E); // 'n'
          break;
        case 0x0D:
          sink.addByte(0x5C);
          sink.addByte(0x72); // 'r'
          break;
        case 0x09:
          sink.addByte(0x5C);
          sink.addByte(0x74); // 't'
          break;
        default:
          if (c < 0x20) {
            sink.addByte(0x5C);
            sink.addByte(0x75); // 'u'
            sink.addByte(0x30); // '0'
            sink.addByte(0x30); // '0'
            sink.addByte(_hexDigits.codeUnitAt((c >> 4) & 0xF));
            sink.addByte(_hexDigits.codeUnitAt(c & 0xF));
          } else if (c <= 0x7F) {
            sink.addByte(c);
          } else if (c <= 0x7FF) {
            sink.addByte(0xC0 | (c >> 6));
            sink.addByte(0x80 | (c & 0x3F));
          } else if (c >= 0xD800 && c <= 0xDBFF) {
            if (i + 1 < len) {
              final c2 = value.codeUnitAt(i + 1);
              if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
                i++;
                final codePoint =
                    0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00);
                sink.addByte(0xF0 | (codePoint >> 18));
                sink.addByte(0x80 | ((codePoint >> 12) & 0x3F));
                sink.addByte(0x80 | ((codePoint >> 6) & 0x3F));
                sink.addByte(0x80 | (codePoint & 0x3F));
                break;
              }
            }
            // Isolated high surrogate -> \uXXXX
            sink.addByte(0x5C);
            sink.addByte(0x75); // 'u'
            sink.addByte(_hexDigits.codeUnitAt((c >> 12) & 0xF));
            sink.addByte(_hexDigits.codeUnitAt((c >> 8) & 0xF));
            sink.addByte(_hexDigits.codeUnitAt((c >> 4) & 0xF));
            sink.addByte(_hexDigits.codeUnitAt(c & 0xF));
          } else if (c >= 0xDC00 && c <= 0xDFFF) {
            // Isolated low surrogate -> \uXXXX
            sink.addByte(0x5C);
            sink.addByte(0x75); // 'u'
            sink.addByte(_hexDigits.codeUnitAt((c >> 12) & 0xF));
            sink.addByte(_hexDigits.codeUnitAt((c >> 8) & 0xF));
            sink.addByte(_hexDigits.codeUnitAt((c >> 4) & 0xF));
            sink.addByte(_hexDigits.codeUnitAt(c & 0xF));
          } else {
            sink.addByte(0xE0 | (c >> 12));
            sink.addByte(0x80 | ((c >> 6) & 0x3F));
            sink.addByte(0x80 | (c & 0x3F));
          }
          break;
      }
    }
    sink.addByte(0x22); // '"'
  }

  /// Writes [value] with standard JSON escaping directly into [buffer] starting
  /// at [offset]. Returns the number of bytes written.
  static int writeStringToBuffer(String value, Uint8List buffer, int offset) {
    return _writeStringToBufferUtf8(value, buffer, offset);
  }

  /// Formats [value] as a valid JSON floating-point literal directly into [sink].
  static void writeDouble(double value, BytesBuilder sink) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Must be finite');
    }
    final buf = Uint8List(32);
    final len = writeDoubleToBuffer(value, buf, 0);
    for (var i = 0; i < len; i++) {
      sink.addByte(buf[i]);
    }
  }

  /// Formats [value] directly into [buffer] starting at [offset] as ASCII bytes.
  /// Returns the number of bytes written.
  static int writeDoubleToBuffer(double value, Uint8List buffer, int offset) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Must be finite');
    }
    final written = _writeDoubleToBufferUtf8(value, buffer, offset);
    if (written > 0) return written;
    final str = value.toString();
    final len = str.length;
    if (offset < 0 || offset + len > buffer.length) {
      throw RangeError.range(
        offset,
        0,
        buffer.length >= len ? buffer.length - len : 0,
        'offset',
      );
    }
    for (var i = 0; i < len; i++) {
      buffer[offset + i] = str.codeUnitAt(i);
    }
    return len;
  }

  /// Formats [value] as an ASCII integer literal directly into [sink].
  static void writeInt(int value, BytesBuilder sink) {
    if (value == 0) {
      sink.addByte(48); // '0'
      return;
    }
    var v = value;
    if (v < 0) {
      sink.addByte(45); // '-'
    } else {
      v = -v;
    }
    final digitCount = _digitCountNegative(v);
    for (var k = digitCount - 1; k >= 0; k--) {
      final power = _powersOf10Int[k];
      final digit = -(v ~/ power);
      sink.addByte(48 + digit);
      v += digit * power;
    }
  }

  /// Formats [value] directly into [buffer] starting at [offset] as ASCII bytes.
  /// Returns the number of bytes written.
  static int writeIntToBuffer(int value, Uint8List buffer, int offset) {
    if (value == 0) {
      if (offset < 0 || offset >= buffer.length) {
        throw RangeError.range(
          offset,
          0,
          buffer.length >= 1 ? buffer.length - 1 : 0,
          'offset',
        );
      }
      buffer[offset] = 48; // '0'
      return 1;
    }
    var v = value;
    final isNeg = v < 0;
    if (!isNeg) {
      v = -v;
    }
    final digitCount = _digitCountNegative(v);
    final totalLen = (isNeg ? 1 : 0) + digitCount;
    if (offset < 0 || offset + totalLen > buffer.length) {
      throw RangeError.range(
        offset,
        0,
        buffer.length >= totalLen ? buffer.length - totalLen : 0,
        'offset',
      );
    }
    var cursor = offset;
    if (isNeg) {
      buffer[cursor++] = 45; // '-'
    }
    var writePos = cursor + digitCount - 1;
    var temp = v;
    while (temp <= -100) {
      final next = temp ~/ 100;
      final rem = -(temp - next * 100);
      final pairIdx = rem << 1;
      buffer[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
      buffer[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
      writePos -= 2;
      temp = next;
    }
    if (temp <= -10) {
      final rem = -temp;
      final pairIdx = rem << 1;
      buffer[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
      buffer[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
    } else {
      buffer[writePos] = 48 - temp;
    }
    return totalLen;
  }

  /// Writes a boolean literal (`true` or `false`) directly into [sink].
  static void writeBool(bool value, BytesBuilder sink) {
    if (value) {
      sink.add(const [116, 114, 117, 101]); // 'true'
    } else {
      sink.add(const [102, 97, 108, 115, 101]); // 'false'
    }
  }

  /// Writes a boolean literal directly into [buffer] starting at [offset].
  /// Returns the number of bytes written.
  static int writeBoolToBuffer(bool value, Uint8List buffer, int offset) {
    final len = value ? 4 : 5;
    if (offset < 0 || offset + len > buffer.length) {
      throw RangeError.range(
        offset,
        0,
        buffer.length >= len ? buffer.length - len : 0,
        'offset',
      );
    }
    if (value) {
      buffer[offset] = 116; // 't'
      buffer[offset + 1] = 114; // 'r'
      buffer[offset + 2] = 117; // 'u'
      buffer[offset + 3] = 101; // 'e'
      return 4;
    } else {
      buffer[offset] = 102; // 'f'
      buffer[offset + 1] = 97; // 'a'
      buffer[offset + 2] = 108; // 'l'
      buffer[offset + 3] = 115; // 's'
      buffer[offset + 4] = 101; // 'e'
      return 5;
    }
  }

  /// Writes a `null` literal directly into [sink].
  static void writeNull(BytesBuilder sink) {
    sink.add(const [110, 117, 108, 108]); // 'null'
  }

  /// Writes a `null` literal directly into [buffer] starting at [offset].
  /// Returns the number of bytes written.
  static int writeNullToBuffer(Uint8List buffer, int offset) {
    const len = 4;
    if (offset < 0 || offset + len > buffer.length) {
      throw RangeError.range(
        offset,
        0,
        buffer.length >= len ? buffer.length - len : 0,
        'offset',
      );
    }
    buffer[offset] = 110;
    buffer[offset + 1] = 117;
    buffer[offset + 2] = 108;
    buffer[offset + 3] = 108;
    return 4;
  }

  /// Writes a pre-encoded compile-time ASCII byte literal directly into [sink].
  static void writeAsciiLiteral(Uint8List asciiBytes, BytesBuilder sink) {
    sink.add(asciiBytes);
  }

  /// Writes a pre-encoded ASCII byte literal directly into [buffer] at [offset].
  /// Returns the number of bytes written.
  static int writeAsciiLiteralToBuffer(
    Uint8List asciiBytes,
    Uint8List buffer,
    int offset,
  ) {
    final len = asciiBytes.length;
    if (offset < 0 || offset + len > buffer.length) {
      throw RangeError.range(
        offset,
        0,
        buffer.length >= len ? buffer.length - len : 0,
        'offset',
      );
    }
    buffer.setRange(offset, offset + len, asciiBytes);
    return len;
  }

  /// Writes a raw JSON UTF-8 byte fragment directly into [sink].
  static void writeRawJson(Uint8List rawJson, BytesBuilder sink) {
    sink.add(rawJson);
  }

  /// Writes a raw JSON UTF-8 byte fragment directly into [buffer] at [offset].
  /// Returns the number of bytes written.
  static int writeRawJsonToBuffer(
    Uint8List rawJson,
    Uint8List buffer,
    int offset,
  ) {
    final len = rawJson.length;
    if (offset < 0 || offset + len > buffer.length) {
      throw RangeError.range(
        offset,
        0,
        buffer.length >= len ? buffer.length - len : 0,
        'offset',
      );
    }
    buffer.setRange(offset, offset + len, rawJson);
    return len;
  }

  /// Safely writes an object property separator (comma if not first) and key
  /// prefix into [buffer], avoiding leading comma bugs on nullable/omitted fields.
  static int writePropertyPrefixToBuffer(
    Uint8List buffer,
    int offset,
    Uint8List asciiKey, {
    required bool isFirst,
  }) {
    final isFirstOffset = isFirst ? 0 : 1;
    final isColonTerminated =
        asciiKey.length >= 3 &&
        asciiKey.first == 0x22 &&
        asciiKey.last == 0x3A &&
        _isSingleQuotedSlice(asciiKey, 0, asciiKey.length - 1);
    if (isColonTerminated) {
      final requiredLen = isFirstOffset + asciiKey.length;
      if (offset < 0 || offset + requiredLen > buffer.length) {
        throw RangeError.range(
          offset,
          0,
          buffer.length >= requiredLen ? buffer.length - requiredLen : 0,
          'offset',
        );
      }
      var cursor = offset;
      if (!isFirst) {
        buffer[cursor++] = 44; // ','
      }
      final keyLen = asciiKey.length;
      buffer.setRange(cursor, cursor + keyLen, asciiKey);
      cursor += keyLen;
      return cursor - offset;
    }

    final isQuoted = _isSingleQuotedString(asciiKey);
    if (isQuoted) {
      final requiredLen = isFirstOffset + asciiKey.length + 1;
      if (offset < 0 || offset + requiredLen > buffer.length) {
        throw RangeError.range(
          offset,
          0,
          buffer.length >= requiredLen ? buffer.length - requiredLen : 0,
          'offset',
        );
      }
      var cursor = offset;
      if (!isFirst) {
        buffer[cursor++] = 44; // ','
      }
      final keyLen = asciiKey.length;
      buffer.setRange(cursor, cursor + keyLen, asciiKey);
      cursor += keyLen;
      buffer[cursor++] = 58; // ':'
      return cursor - offset;
    }

    var escapedContentLen = 0;
    for (var i = 0; i < asciiKey.length; i++) {
      final b = asciiKey[i];
      if (b == 0x22 || b == 0x5C) {
        escapedContentLen += 2;
      } else if (b < 0x20) {
        escapedContentLen += 6;
      } else {
        escapedContentLen += 1;
      }
    }

    final requiredLen = isFirstOffset + 2 + escapedContentLen + 1;
    if (offset < 0 || offset + requiredLen > buffer.length) {
      throw RangeError.range(
        offset,
        0,
        buffer.length >= requiredLen ? buffer.length - requiredLen : 0,
        'offset',
      );
    }

    var cursor = offset;
    if (!isFirst) {
      buffer[cursor++] = 44; // ','
    }
    buffer[cursor++] = 0x22; // '"'
    for (var i = 0; i < asciiKey.length; i++) {
      final b = asciiKey[i];
      if (b == 0x22) {
        buffer[cursor++] = 0x5C;
        buffer[cursor++] = 0x22;
      } else if (b == 0x5C) {
        buffer[cursor++] = 0x5C;
        buffer[cursor++] = 0x5C;
      } else if (b < 0x20) {
        buffer[cursor++] = 0x5C;
        buffer[cursor++] = 0x75; // 'u'
        buffer[cursor++] = 0x30; // '0'
        buffer[cursor++] = 0x30; // '0'
        buffer[cursor++] = _hexDigits.codeUnitAt((b >> 4) & 0xF);
        buffer[cursor++] = _hexDigits.codeUnitAt(b & 0xF);
      } else {
        buffer[cursor++] = b;
      }
    }
    buffer[cursor++] = 0x22; // '"'
    buffer[cursor++] = 58; // ':'
    return cursor - offset;
  }
}

class _JsonUtf8EncoderSink extends ChunkedConversionSink<Object?> {
  final ByteConversionSink _sink;
  final List<int>? _indent;
  final Object? Function(dynamic)? _toEncodable;
  final int _bufferSize;
  bool _isDone = false;

  _JsonUtf8EncoderSink(
    this._sink,
    this._toEncodable,
    this._indent,
    this._bufferSize,
  );

  void _addChunk(Uint8List chunk, int start, int end) {
    _sink.addSlice(chunk, start, end, false);
  }

  @override
  void add(Object? object) {
    if (_isDone) {
      throw StateError("Only one call to add allowed");
    }
    _isDone = true;
    _JsonUtf8Stringifier.stringify(
      object,
      _indent,
      _toEncodable,
      _bufferSize,
      _addChunk,
    );
    _sink.close();
  }

  @override
  void close() {
    if (!_isDone) {
      _isDone = true;
      _sink.close();
    }
  }
}

class _JsonUtf8Stringifier extends _JsonStringifier {
  final int bufferSize;
  final void Function(Uint8List list, int start, int end) addChunk;
  Uint8List buffer;
  int index = 0;

  _JsonUtf8Stringifier(super.toEncodable, this.bufferSize, this.addChunk)
    : buffer = Uint8List(bufferSize);

  static void stringify(
    Object? object,
    List<int>? indent,
    dynamic Function(dynamic o)? toEncodable,
    int bufferSize,
    void Function(Uint8List chunk, int start, int end) addChunk,
  ) {
    _JsonUtf8Stringifier stringifier;
    if (indent != null) {
      stringifier = _JsonUtf8StringifierPretty(
        toEncodable,
        indent,
        bufferSize,
        addChunk,
      );
    } else {
      stringifier = _JsonUtf8Stringifier(toEncodable, bufferSize, addChunk);
    }
    stringifier.writeObject(object);
    stringifier.flush();
  }

  void flush() {
    if (index > 0) {
      addChunk(buffer, 0, index);
    }
    buffer = Uint8List(0);
    index = 0;
  }

  String? get _partialResult => null;

  void _flushBuffer([int requiredExtra = 0]) {
    if (index > 0) {
      addChunk(buffer, 0, index);
      index = 0;
    }
    final nextSize = requiredExtra > bufferSize ? requiredExtra : bufferSize;
    buffer = Uint8List(nextSize);
  }

  @override
  bool writeJsonValue(Object? object) {
    if (object is num) {
      if (!object.isFinite) return false;
      writeNumber(object);
      return true;
    } else if (identical(object, true)) {
      writeAsciiString('true');
      return true;
    } else if (identical(object, false)) {
      writeAsciiString('false');
      return true;
    } else if (object == null) {
      writeAsciiString('null');
      return true;
    } else if (object is String) {
      final maxLen = object.length * 6 + 2;
      if (index + maxLen > buffer.length) {
        _flushBuffer(maxLen);
      }
      if (index + maxLen <= buffer.length) {
        index += JsonUtf8Encoder.writeStringToBuffer(object, buffer, index);
        return true;
      }
      writeByte(0x22);
      writeStringContent(object);
      writeByte(0x22);
      return true;
    } else if (object is List) {
      _checkCycle(object);
      writeList(object);
      _removeSeen(object);
      return true;
    } else if (object is Map) {
      _checkCycle(object);
      var success = writeMap(object);
      _removeSeen(object);
      return success;
    } else {
      return false;
    }
  }

  @override
  bool writeMap(Map<Object?, Object?> map) {
    if (map.isEmpty) {
      writeAsciiString("{}");
      return true;
    }
    var keyValueList = List<Object?>.filled(map.length * 2, null);
    var i = 0;
    var allStringKeys = true;
    map.forEach((key, value) {
      if (key is! String) {
        allStringKeys = false;
      }
      keyValueList[i++] = key;
      keyValueList[i++] = value;
    });
    if (!allStringKeys) return false;
    writeByte(0x7B); // '{'
    for (var i = 0; i < keyValueList.length; i += 2) {
      if (i > 0) writeByte(0x2C); // ','
      final key = keyValueList[i] as String;
      final maxLen = key.length * 6 + 3; // quotes + escapes + ':'
      if (index + maxLen > buffer.length) {
        _flushBuffer(maxLen);
      }
      if (index + maxLen <= buffer.length) {
        index += JsonUtf8Encoder.writeStringToBuffer(key, buffer, index);
        buffer[index++] = 0x3A; // ':'
      } else {
        writeByte(0x22);
        writeStringContent(key);
        writeByte(0x22);
        writeByte(0x3A);
      }
      writeObject(keyValueList[i + 1]);
    }
    writeByte(0x7D); // '}'
    return true;
  }

  @override
  void writeList(List<Object?> list) {
    writeByte(0x5B); // '['
    if (list.isNotEmpty) {
      writeObject(list[0]);
      for (var i = 1; i < list.length; i++) {
        writeByte(0x2C); // ','
        writeObject(list[i]);
      }
    }
    writeByte(0x5D); // ']'
  }

  void writeNumber(num number) {
    if (number is int) {
      if (index + 24 > buffer.length) {
        _flushBuffer(24);
      }
      if (index + 24 <= buffer.length) {
        index += JsonUtf8Encoder.writeIntToBuffer(number, buffer, index);
        return;
      }
    } else if (number is double && number.isFinite) {
      if (index + 32 > buffer.length) {
        _flushBuffer(32);
      }
      if (index + 32 <= buffer.length) {
        index += JsonUtf8Encoder.writeDoubleToBuffer(number, buffer, index);
        return;
      }
    }
    writeAsciiString(number.toString());
  }

  void writeAsciiString(String string) {
    final len = string.length;
    if (index + len > buffer.length) {
      _flushBuffer(len);
    }
    if (index + len <= buffer.length) {
      for (var i = 0; i < len; i++) {
        buffer[index++] = string.codeUnitAt(i);
      }
      return;
    }
    for (var i = 0; i < len; i++) {
      writeByte(string.codeUnitAt(i));
    }
  }

  void writeString(String string) {
    writeStringSlice(string, 0, string.length);
  }

  void writeStringSlice(String string, int start, int end) {
    var i = start;
    while (i < end) {
      var char = string.codeUnitAt(i);
      if (char <= 0x7f) {
        final asciiStart = i;
        i++;
        while (i < end) {
          if (string.codeUnitAt(i) > 0x7f) break;
          i++;
        }
        final asciiLen = i - asciiStart;
        if (index + asciiLen <= buffer.length) {
          for (var k = asciiStart; k < i; k++) {
            buffer[index++] = string.codeUnitAt(k);
          }
        } else {
          for (var k = asciiStart; k < i; k++) {
            writeByte(string.codeUnitAt(k));
          }
        }
      } else {
        if ((char & 0xF800) == 0xD800) {
          // Surrogate.
          if (char < 0xDC00 && i + 1 < end) {
            var nextChar = string.codeUnitAt(i + 1);
            if ((nextChar & 0xFC00) == 0xDC00) {
              char = 0x10000 + ((char & 0x3ff) << 10) + (nextChar & 0x3ff);
              writeFourByteCharCode(char);
              i += 2;
              continue;
            }
          }
          // Isolated surrogate -> \uXXXX escape matching writeStringToBuffer & RFC 8259
          writeByte(0x5C); // '\'
          writeByte(0x75); // 'u'
          writeByte(_hexDigits.codeUnitAt((char >> 12) & 0xF));
          writeByte(_hexDigits.codeUnitAt((char >> 8) & 0xF));
          writeByte(_hexDigits.codeUnitAt((char >> 4) & 0xF));
          writeByte(_hexDigits.codeUnitAt(char & 0xF));
          i++;
          continue;
        }
        writeMultiByteCharCode(char);
        i++;
      }
    }
  }

  void writeCharCode(int charCode) {
    if (charCode <= 0x7f) {
      writeByte(charCode);
      return;
    }
    writeMultiByteCharCode(charCode);
  }

  void writeMultiByteCharCode(int charCode) {
    if (charCode <= 0x7ff) {
      writeByte(0xC0 | (charCode >> 6));
      writeByte(0x80 | (charCode & 0x3f));
      return;
    }
    if (charCode <= 0xffff) {
      writeByte(0xE0 | (charCode >> 12));
      writeByte(0x80 | ((charCode >> 6) & 0x3f));
      writeByte(0x80 | (charCode & 0x3f));
      return;
    }
    writeFourByteCharCode(charCode);
  }

  void writeFourByteCharCode(int charCode) {
    assert(charCode <= 0x10ffff);
    writeByte(0xF0 | (charCode >> 18));
    writeByte(0x80 | ((charCode >> 12) & 0x3f));
    writeByte(0x80 | ((charCode >> 6) & 0x3f));
    writeByte(0x80 | (charCode & 0x3f));
  }

  void writeByte(int byte) {
    assert(byte <= 0xff);
    if (index == buffer.length) {
      if (index > 0) {
        addChunk(buffer, 0, index);
      }
      buffer = Uint8List(bufferSize);
      index = 0;
    }
    buffer[index++] = byte;
  }
}

class _JsonUtf8StringifierPretty extends _JsonUtf8Stringifier
    with _JsonPrettyPrintMixin {
  final List<int> indent;
  _JsonUtf8StringifierPretty(
    dynamic Function(dynamic o)? toEncodable,
    this.indent,
    int bufferSize,
    void Function(Uint8List buffer, int start, int end) addChunk,
  ) : super(toEncodable, bufferSize, addChunk);

  void writeIndentation(int count) {
    var indent = this.indent;
    var indentLength = indent.length;
    if (indentLength == 1) {
      var char = indent[0];
      while (count > 0) {
        writeByte(char);
        count -= 1;
      }
      return;
    }
    while (count > 0) {
      count--;
      var end = index + indentLength;
      if (end <= buffer.length) {
        buffer.setRange(index, end, indent);
        index = end;
      } else {
        for (var i = 0; i < indentLength; i++) {
          writeByte(indent[i]);
        }
      }
    }
  }
}

/// High-performance imperative pull-based JSON token reader.
abstract interface class JsonTokenReader {
  /// Instantiates a pull-based token reader over [bytes].
  factory JsonTokenReader.fromBytes(Uint8List bytes, {bool allowMalformed}) =
      _JsonTokenReader;

  /// Peeks at the next token type without advancing the cursor.
  JsonTokenType peek();

  /// Advances past the opening `{` of an object.
  void beginObject();

  /// Advances past the closing `}` of an object.
  void endObject();

  /// Advances past the opening `[` of an array.
  void beginArray();

  /// Advances past the closing `]` of an array.
  void endArray();

  /// Returns `true` if the current object or array has more elements.
  bool hasNext();

  /// Reads the next object property name as a [String].
  String nextName();

  /// Matches the next property name against pre-compiled [options] in O(1).
  int selectName(JsonKeyOptions options);

  /// Matches the next string VALUE against pre-compiled [options] in O(1)
  /// without allocating a heap [String] (e.g. for parsing string enums).
  int selectString(JsonKeyOptions options);

  /// Reads a string value.
  String readString();

  /// Reads an integer value.
  int readInt();

  /// Reads a double value (with automatic integer-to-double coercion).
  double readDouble();

  /// Reads a numeric token as a [num] (either [int] or [double]).
  num readNum();

  /// Reads a boolean value.
  bool readBool();

  /// Reads a null literal.
  void readNull();

  /// Skips the entire next value (including nested objects and arrays).
  void skipValue();

  /// Returns the raw byte span `(start, end)` of the current token.
  (int start, int end) getTokenSpan();
}

enum _ContainerType { object, array }

enum _ReaderItemState { start, afterName, afterValue, afterComma }

final class _ContainerFrame {
  final _ContainerType type;
  _ReaderItemState state;

  _ContainerFrame(this.type, this.state);
}

final class _JsonTokenReader implements JsonTokenReader {
  static const int _maxDepth = 64;
  final Uint8List _bytes;
  final bool allowMalformed;
  int _offset = 0;
  final List<_ContainerFrame> _stack = [];
  bool _hasReadRoot = false;

  _JsonTokenReader(this._bytes, {this.allowMalformed = false}) {
    if (_bytes.length >= 3 &&
        _bytes[0] == 0xEF &&
        _bytes[1] == 0xBB &&
        _bytes[2] == 0xBF) {
      _offset = 3;
    }
  }

  void _skipWs() {
    while (_offset < _bytes.length && _isWs(_bytes[_offset])) {
      _offset++;
    }
  }

  void _consumeColon() {
    _skipWs();
    if (_offset < _bytes.length && _bytes[_offset] == 58) {
      _offset++;
    } else {
      throw FormatException('Expected ":" at offset $_offset');
    }
  }

  void _beforeReadingName() {
    _skipWs();
    if (_stack.isEmpty || _stack.last.type != _ContainerType.object) {
      throw FormatException(
        'Cannot read property name outside of an object at offset $_offset',
      );
    }
    final top = _stack.last;
    if (top.state == _ReaderItemState.afterName) {
      throw FormatException(
        'Expected property value before next property name at offset $_offset',
      );
    }
    if (top.state == _ReaderItemState.afterValue) {
      if (_offset < _bytes.length && _bytes[_offset] == 44) {
        _offset++;
        top.state = _ReaderItemState.afterComma;
        _skipWs();
      } else {
        throw FormatException(
          'Expected "," before property name at offset $_offset',
        );
      }
    }
  }

  void _beforeReadingValue() {
    _skipWs();
    if (_stack.isNotEmpty) {
      final top = _stack.last;
      if (top.type == _ContainerType.object) {
        if (top.state != _ReaderItemState.afterName) {
          throw FormatException(
            'Expected property name before value at offset $_offset',
          );
        }
      } else {
        if (top.state == _ReaderItemState.afterValue) {
          if (_offset < _bytes.length && _bytes[_offset] == 44) {
            _offset++;
            top.state = _ReaderItemState.afterComma;
            _skipWs();
          } else {
            throw FormatException(
              'Expected "," before array element at offset $_offset',
            );
          }
        }
      }
    } else {
      if (_hasReadRoot) {
        throw FormatException(
          'Cannot read multiple root values',
          _bytes,
          _offset,
        );
      }
    }
  }

  void _afterReadingValue() {
    if (_stack.isNotEmpty) {
      _stack.last.state = _ReaderItemState.afterValue;
    } else {
      _hasReadRoot = true;
    }
  }

  static JsonTokenType _valueTokenType(int b) {
    switch (b) {
      case 123: // '{'
        return JsonTokenType.beginObject;
      case 91: // '['
        return JsonTokenType.beginArray;
      case 34: // '"'
        return JsonTokenType.string;
      case 116: // 't'
      case 102: // 'f'
        return JsonTokenType.boolean;
      case 110: // 'n'
        return JsonTokenType.nullValue;
      case 45: // '-'
      case 48:
      case 49:
      case 50:
      case 51:
      case 52:
      case 53:
      case 54:
      case 55:
      case 56:
      case 57:
        return JsonTokenType.number;
      default:
        return JsonTokenType.none;
    }
  }

  @override
  JsonTokenType peek() {
    var i = _offset;
    while (i < _bytes.length && _isWs(_bytes[i])) {
      i++;
    }
    if (i >= _bytes.length) return JsonTokenType.endOfDocument;

    if (_stack.isNotEmpty) {
      final top = _stack.last;
      if (top.type == _ContainerType.object) {
        switch (top.state) {
          case _ReaderItemState.start:
            if (_bytes[i] == 125) return JsonTokenType.endObject;
            if (_bytes[i] == 34) return JsonTokenType.propertyName;
            return JsonTokenType.none;
          case _ReaderItemState.afterName:
            return _valueTokenType(_bytes[i]);
          case _ReaderItemState.afterComma:
            if (_bytes[i] == 34) return JsonTokenType.propertyName;
            if (_bytes[i] == 125 || _bytes[i] == 93) {
              throw FormatException(
                'Trailing comma before closing delimiter',
                _bytes,
                _offset,
              );
            }
            return JsonTokenType.none;
          case _ReaderItemState.afterValue:
            if (_bytes[i] == 125) return JsonTokenType.endObject;
            if (_bytes[i] == 44) {
              i++;
              while (i < _bytes.length && _isWs(_bytes[i])) {
                i++;
              }
              if (i >= _bytes.length) {
                throw FormatException(
                  'Unexpected end of document after comma',
                  _bytes,
                  _offset,
                );
              }
              if (_bytes[i] == 125 || _bytes[i] == 93) {
                throw FormatException(
                  'Trailing comma before closing delimiter',
                  _bytes,
                  _offset,
                );
              }
              if (_bytes[i] == 34) return JsonTokenType.propertyName;
              return JsonTokenType.none;
            }
            throw FormatException(
              'Expected comma or closing delimiter',
              _bytes,
              _offset,
            );
        }
      } else {
        // _ContainerType.array
        switch (top.state) {
          case _ReaderItemState.start:
            if (_bytes[i] == 93) return JsonTokenType.endArray;
            return _valueTokenType(_bytes[i]);
          case _ReaderItemState.afterComma:
            if (_bytes[i] == 93 || _bytes[i] == 125) {
              throw FormatException(
                'Trailing comma before closing delimiter',
                _bytes,
                _offset,
              );
            }
            return _valueTokenType(_bytes[i]);
          case _ReaderItemState.afterValue:
            if (_bytes[i] == 93) return JsonTokenType.endArray;
            if (_bytes[i] == 44) {
              i++;
              while (i < _bytes.length && _isWs(_bytes[i])) {
                i++;
              }
              if (i >= _bytes.length) {
                throw FormatException(
                  'Unexpected end of document after comma',
                  _bytes,
                  _offset,
                );
              }
              if (_bytes[i] == 93 || _bytes[i] == 125) {
                throw FormatException(
                  'Trailing comma before closing delimiter',
                  _bytes,
                  _offset,
                );
              }
              return _valueTokenType(_bytes[i]);
            }
            throw FormatException(
              'Expected comma or closing delimiter',
              _bytes,
              _offset,
            );
          case _ReaderItemState.afterName:
            return JsonTokenType.none;
        }
      }
    } else {
      if (_hasReadRoot) {
        return JsonTokenType.none;
      }
      return _valueTokenType(_bytes[i]);
    }
  }

  @override
  void beginObject() {
    _beforeReadingValue();
    if (_offset < _bytes.length && _bytes[_offset] == 123) {
      _offset++;
      if (_stack.length >= _maxDepth) {
        throw FormatException(
          'Nesting depth exceeds limit of $_maxDepth at offset $_offset',
        );
      }
      _stack.add(
        _ContainerFrame(_ContainerType.object, _ReaderItemState.start),
      );
    } else {
      throw FormatException('Expected "{" at offset $_offset');
    }
  }

  @override
  void endObject() {
    _skipWs();
    if (_stack.isEmpty || _stack.last.type != _ContainerType.object) {
      throw FormatException('Expected "}" at offset $_offset');
    }
    if (_stack.last.state == _ReaderItemState.afterComma) {
      throw FormatException('Trailing comma before "}" at offset $_offset');
    }
    if (_stack.last.state == _ReaderItemState.afterName) {
      throw FormatException(
        'Expected value after property name before "}" at offset $_offset',
      );
    }
    if (_offset < _bytes.length && _bytes[_offset] == 125) {
      _offset++;
      _stack.removeLast();
      _afterReadingValue();
    } else {
      throw FormatException('Expected "}" at offset $_offset');
    }
  }

  @override
  void beginArray() {
    _beforeReadingValue();
    if (_offset < _bytes.length && _bytes[_offset] == 91) {
      _offset++;
      if (_stack.length >= _maxDepth) {
        throw FormatException(
          'Nesting depth exceeds limit of $_maxDepth at offset $_offset',
        );
      }
      _stack.add(_ContainerFrame(_ContainerType.array, _ReaderItemState.start));
    } else {
      throw FormatException('Expected "[" at offset $_offset');
    }
  }

  @override
  void endArray() {
    _skipWs();
    if (_stack.isEmpty || _stack.last.type != _ContainerType.array) {
      throw FormatException('Expected "]" at offset $_offset');
    }
    if (_stack.last.state == _ReaderItemState.afterComma) {
      throw FormatException('Trailing comma before "]" at offset $_offset');
    }
    if (_offset < _bytes.length && _bytes[_offset] == 93) {
      _offset++;
      _stack.removeLast();
      _afterReadingValue();
    } else {
      throw FormatException('Expected "]" at offset $_offset');
    }
  }

  @override
  bool hasNext() {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    try {
      _skipWs();
      if (_offset >= _bytes.length) return false;
      if (_stack.isNotEmpty) {
        final top = _stack.last;
        final closeChar = top.type == _ContainerType.object ? 125 : 93;
        final closeStr = top.type == _ContainerType.object ? '"}"' : '"]"';

        if (top.state == _ReaderItemState.start) {
          if (_bytes[_offset] == closeChar) {
            return false;
          }
          return true;
        } else if (top.state == _ReaderItemState.afterValue) {
          if (_bytes[_offset] == closeChar) {
            return false;
          }
          if (_bytes[_offset] == 44) {
            _offset++;
            top.state = _ReaderItemState.afterComma;
            _skipWs();
            if (_offset >= _bytes.length) {
              throw FormatException(
                'Unexpected end of document after comma',
                _bytes,
                _offset,
              );
            }
            if (_bytes[_offset] == 125 || _bytes[_offset] == 93) {
              throw FormatException(
                'Trailing comma before $closeStr at offset $_offset',
              );
            }
            return true;
          }
          throw FormatException('Expected "," or $closeStr at offset $_offset');
        } else if (top.state == _ReaderItemState.afterComma) {
          if (_offset >= _bytes.length) {
            throw FormatException(
              'Unexpected end of document after comma',
              _bytes,
              _offset,
            );
          }
          if (_bytes[_offset] == 125 || _bytes[_offset] == 93) {
            throw FormatException(
              'Trailing comma before $closeStr at offset $_offset',
            );
          }
          return true;
        } else if (top.state == _ReaderItemState.afterName) {
          return true;
        }
      } else {
        if (_hasReadRoot) {
          return false;
        }
      }
      final b = _bytes[_offset];
      return b != 125 && b != 93;
    } catch (_) {
      _offset = initialOffset;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  (int, int) _scanStringSpan() {
    _skipWs();
    if (_offset >= _bytes.length || _bytes[_offset] != 34) {
      throw FormatException('Expected string at offset $_offset');
    }
    final start = _offset + 1;
    var i = start;
    while (i < _bytes.length) {
      final b = _bytes[i];
      if (b < 0x20) {
        throw FormatException(
          'Unescaped control character in string literal at offset $i',
          _bytes,
          i,
        );
      }
      if (b == 92) {
        i = _validateEscape(_bytes, i + 1, _bytes.length);
      } else if (b == 34) {
        final end = i;
        _offset = i + 1;
        return (start, end);
      } else {
        i++;
      }
    }
    throw FormatException('Unterminated string literal at offset $start');
  }

  @override
  String nextName() {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    try {
      _beforeReadingName();
      final (start, end) = _scanStringSpan();
      _consumeColon();
      _stack.last.state = _ReaderItemState.afterName;
      return _decodeStringUtf8(
        _bytes,
        start,
        end,
        allowMalformed: allowMalformed,
      );
    } catch (_) {
      _offset = initialOffset;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  @override
  int selectName(JsonKeyOptions options) {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    try {
      _beforeReadingName();
      final (start, end) = _scanStringSpan();
      _consumeColon();
      _stack.last.state = _ReaderItemState.afterName;
      if (_isVerbatimUtf8(_bytes, start, end)) {
        return options.selectKey(_bytes, start, end);
      }
      final unescaped = _decodeStringUtf8(
        _bytes,
        start,
        end,
        allowMalformed: allowMalformed,
      );
      return options.keys.indexOf(unescaped);
    } catch (_) {
      _offset = initialOffset;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  @override
  int selectString(JsonKeyOptions options) {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    final hadReadRoot = _hasReadRoot;
    try {
      _beforeReadingValue();
      final (start, end) = _scanStringSpan();
      _afterReadingValue();
      if (_isVerbatimUtf8(_bytes, start, end)) {
        return options.selectKey(_bytes, start, end);
      }
      final unescaped = _decodeStringUtf8(
        _bytes,
        start,
        end,
        allowMalformed: allowMalformed,
      );
      return options.keys.indexOf(unescaped);
    } catch (_) {
      _offset = initialOffset;
      _hasReadRoot = hadReadRoot;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  @override
  String readString() {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    final hadReadRoot = _hasReadRoot;
    try {
      _beforeReadingValue();
      final (start, end) = _scanStringSpan();
      _afterReadingValue();
      return _decodeStringUtf8(
        _bytes,
        start,
        end,
        allowMalformed: allowMalformed,
      );
    } catch (_) {
      _offset = initialOffset;
      _hasReadRoot = hadReadRoot;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  (int, int) _scanScalarSpan() {
    _beforeReadingValue();
    final start = _offset;
    var i = start;
    while (i < _bytes.length) {
      final b = _bytes[i];
      if (b == 44 || b == 125 || b == 93 || _isWs(b)) {
        break;
      }
      i++;
    }
    _offset = i;
    _afterReadingValue();
    return (start, i);
  }

  @override
  int readInt() {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    final hadReadRoot = _hasReadRoot;
    try {
      final (start, end) = _scanScalarSpan();
      return JsonUtf8Decoder.parseInt(_bytes, start, end);
    } catch (_) {
      _offset = initialOffset;
      _hasReadRoot = hadReadRoot;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  @override
  double readDouble() {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    final hadReadRoot = _hasReadRoot;
    try {
      final (start, end) = _scanScalarSpan();
      return JsonUtf8Decoder.parseDouble(_bytes, start, end);
    } catch (_) {
      _offset = initialOffset;
      _hasReadRoot = hadReadRoot;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  @override
  num readNum() {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    final hadReadRoot = _hasReadRoot;
    try {
      final (start, end) = _scanScalarSpan();
      final asInt = JsonUtf8Decoder.tryParseInt(_bytes, start, end);
      if (asInt != null) return asInt;
      return JsonUtf8Decoder.parseDouble(_bytes, start, end);
    } catch (_) {
      _offset = initialOffset;
      _hasReadRoot = hadReadRoot;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  @override
  bool readBool() {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    final hadReadRoot = _hasReadRoot;
    try {
      final (start, end) = _scanScalarSpan();
      return JsonUtf8Decoder.parseBool(_bytes, start, end);
    } catch (_) {
      _offset = initialOffset;
      _hasReadRoot = hadReadRoot;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  @override
  void readNull() {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    final hadReadRoot = _hasReadRoot;
    try {
      final (start, end) = _scanScalarSpan();
      if (!_isNullUtf8(_bytes, start, end)) {
        throw FormatException('Expected null at offset $start');
      }
    } catch (_) {
      _offset = initialOffset;
      _hasReadRoot = hadReadRoot;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  @override
  void skipValue() {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
    final hadReadRoot = _hasReadRoot;
    try {
      if (_stack.isNotEmpty &&
          _stack.last.type == _ContainerType.object &&
          _stack.last.state != _ReaderItemState.afterName) {
        _beforeReadingName();
        _scanStringSpan();
        _consumeColon();
        _stack.last.state = _ReaderItemState.afterName;
        skipValue();
        return;
      }
      _beforeReadingValue();
      if (_offset >= _bytes.length) return;
      final b = _bytes[_offset];
      if (b == 123 || b == 91) {
        _offset = JsonUtf8Decoder.skipValue(_bytes, _offset);
      } else if (b == 34) {
        _scanStringSpan();
      } else {
        _offset = _skipScalar(_bytes, _offset);
      }
      _afterReadingValue();
    } catch (_) {
      _offset = initialOffset;
      _hasReadRoot = hadReadRoot;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  @override
  (int start, int end) getTokenSpan() {
    if (_hasReadRoot) {
      throw FormatException(
        'Cannot read token span past root value',
        _bytes,
        _offset,
      );
    }
    var i = _offset;
    while (i < _bytes.length && _isWs(_bytes[i])) {
      i++;
    }
    if (_stack.isNotEmpty) {
      final state = _stack.last.state;
      if (state == _ReaderItemState.afterValue) {
        if (i < _bytes.length && _bytes[i] == 44) {
          i++;
          while (i < _bytes.length && _isWs(_bytes[i])) {
            i++;
          }
          if (i >= _bytes.length) {
            throw FormatException(
              'Unexpected end of document after comma',
              _bytes,
              _offset,
            );
          }
          if (_bytes[i] == 125 || _bytes[i] == 93) {
            throw FormatException(
              'Trailing comma before closing delimiter',
              _bytes,
              _offset,
            );
          }
        } else {
          final top = _stack.last;
          final closeChar = top.type == _ContainerType.object ? 125 : 93;
          final closeStr = top.type == _ContainerType.object ? '"}"' : '"]"';
          if (i < _bytes.length && _bytes[i] != closeChar) {
            throw FormatException(
              'Expected "," or $closeStr at offset $i',
              _bytes,
              i,
            );
          }
        }
      } else if (state == _ReaderItemState.afterComma) {
        if (i >= _bytes.length) {
          throw FormatException(
            'Unexpected end of document after comma',
            _bytes,
            _offset,
          );
        }
        if (_bytes[i] == 125 || _bytes[i] == 93) {
          throw FormatException(
            'Trailing comma before closing delimiter',
            _bytes,
            _offset,
          );
        }
      }
    }
    if (i >= _bytes.length) {
      throw FormatException('Unexpected end of document');
    }
    final b = _bytes[i];
    if (b == 123 || b == 125 || b == 91 || b == 93 || b == 58 || b == 44) {
      return (i, i + 1);
    }
    if (b == 34) {
      final start = i + 1;
      var j = start;
      while (j < _bytes.length) {
        final c = _bytes[j];
        if (c < 0x20) {
          throw FormatException(
            'Unescaped control character in string literal at offset $j',
            _bytes,
            j,
          );
        }
        if (c == 92) {
          j = _validateEscape(_bytes, j + 1, _bytes.length);
        } else if (c == 34) {
          return (start, j);
        } else {
          j++;
        }
      }
      throw FormatException('Unterminated string literal at offset $start');
    } else {
      final start = i;
      var j = start;
      while (j < _bytes.length) {
        final c = _bytes[j];
        if (c == 44 || c == 125 || c == 93 || c == 58 || _isWs(c)) {
          break;
        }
        j++;
      }
      return (start, j);
    }
  }
}

enum _ObjectState { empty, key, value }

/// High-performance push-based JSON token writer.
abstract interface class JsonTokenWriter {
  /// Instantiates a token writer emitting to [sink].
  factory JsonTokenWriter.toSink(BytesBuilder sink) = _JsonTokenWriter;

  void beginObject();
  void endObject();
  void beginArray();
  void endArray();
  void writeName(String name);
  void writeNameBytes(Uint8List asciiKey);
  void writeAsciiLiteral(Uint8List preEncoded);
  void writeRawJson(Uint8List rawJson);
  void writeString(String value);
  void writeInt(int value);
  void writeDouble(double value);
  void writeBool(bool value);
  void writeNull();
}

final class _JsonTokenWriter implements JsonTokenWriter {
  static const int _maxDepth = 64;
  final BytesBuilder _sink;
  final List<_ContainerType> _stateStack = [];
  final List<_ObjectState> _objectStateStack = [];
  final List<bool> _isArrayFirstStack = [];
  bool _hasRootValue = false;

  _JsonTokenWriter(this._sink);

  void _beforeValue() {
    if (_stateStack.isNotEmpty) {
      final inObject = _stateStack.last == _ContainerType.object;
      if (inObject) {
        if (_objectStateStack.last != _ObjectState.key) {
          throw StateError('Expected property name before value in object');
        }
        _objectStateStack.last = _ObjectState.value;
      } else {
        // In array
        if (!_isArrayFirstStack.last) {
          _sink.addByte(44); // ','
        }
        _isArrayFirstStack.last = false;
      }
    } else {
      if (_hasRootValue) {
        throw StateError('Cannot write multiple root values');
      }
      _hasRootValue = true;
    }
  }

  @override
  void beginObject() {
    if (_stateStack.length >= _maxDepth) {
      throw StateError('Nesting depth exceeds limit of $_maxDepth');
    }
    _beforeValue();
    _sink.addByte(123); // '{'
    _stateStack.add(_ContainerType.object);
    _objectStateStack.add(_ObjectState.empty);
  }

  @override
  void endObject() {
    if (_stateStack.isEmpty || _stateStack.last != _ContainerType.object) {
      throw StateError('Cannot endObject: not inside an object');
    }
    if (_objectStateStack.last == _ObjectState.key) {
      throw StateError('Cannot endObject: expected value after property name');
    }
    _sink.addByte(125); // '}'
    _stateStack.removeLast();
    _objectStateStack.removeLast();
    if (_stateStack.isNotEmpty &&
        _stateStack.last == _ContainerType.object &&
        _objectStateStack.last == _ObjectState.key) {
      _objectStateStack.last = _ObjectState.value;
    }
  }

  @override
  void beginArray() {
    if (_stateStack.length >= _maxDepth) {
      throw StateError('Nesting depth exceeds limit of $_maxDepth');
    }
    _beforeValue();
    _sink.addByte(91); // '['
    _stateStack.add(_ContainerType.array);
    _isArrayFirstStack.add(true);
  }

  @override
  void endArray() {
    if (_stateStack.isEmpty || _stateStack.last != _ContainerType.array) {
      throw StateError('Cannot endArray: not inside an array');
    }
    _sink.addByte(93); // ']'
    _stateStack.removeLast();
    _isArrayFirstStack.removeLast();
    if (_stateStack.isNotEmpty &&
        _stateStack.last == _ContainerType.object &&
        _objectStateStack.last == _ObjectState.key) {
      _objectStateStack.last = _ObjectState.value;
    }
  }

  @override
  void writeName(String name) {
    if (_stateStack.isEmpty || _stateStack.last != _ContainerType.object) {
      throw StateError('Cannot writeName: not inside an object');
    }
    final objState = _objectStateStack.last;
    if (objState == _ObjectState.key) {
      throw StateError(
        'Cannot writeName: already expecting a value for previous property',
      );
    }
    if (objState == _ObjectState.value) {
      _sink.addByte(44); // ','
    }
    _objectStateStack.last = _ObjectState.key;
    JsonUtf8Encoder.writeString(name, _sink);
    _sink.addByte(58); // ':'
  }

  @override
  void writeNameBytes(Uint8List asciiKey) {
    if (_stateStack.isEmpty || _stateStack.last != _ContainerType.object) {
      throw StateError('Cannot writeNameBytes: not inside an object');
    }
    final objState = _objectStateStack.last;
    if (objState == _ObjectState.key) {
      throw StateError(
        'Cannot writeNameBytes: already expecting a value for previous property',
      );
    }
    if (objState == _ObjectState.value) {
      _sink.addByte(44); // ','
    }
    _objectStateStack.last = _ObjectState.key;
    final isColonTerminated =
        asciiKey.length >= 3 &&
        asciiKey.first == 0x22 &&
        asciiKey.last == 0x3A &&
        _isSingleQuotedSlice(asciiKey, 0, asciiKey.length - 1);
    if (isColonTerminated) {
      _sink.add(asciiKey);
      return;
    }
    final isQuoted = _isSingleQuotedString(asciiKey);
    if (isQuoted) {
      _sink.add(asciiKey);
    } else {
      _sink.addByte(34); // '"'
      for (var i = 0; i < asciiKey.length; i++) {
        final b = asciiKey[i];
        if (b == 0x22) {
          _sink.addByte(0x5C);
          _sink.addByte(0x22);
        } else if (b == 0x5C) {
          _sink.addByte(0x5C);
          _sink.addByte(0x5C);
        } else if (b < 0x20) {
          _sink.addByte(0x5C);
          _sink.addByte(0x75); // 'u'
          _sink.addByte(0x30); // '0'
          _sink.addByte(0x30); // '0'
          _sink.addByte(_hexDigits.codeUnitAt((b >> 4) & 0xF));
          _sink.addByte(_hexDigits.codeUnitAt(b & 0xF));
        } else {
          _sink.addByte(b);
        }
      }
      _sink.addByte(34); // '"'
    }
    _sink.addByte(58); // ':'
  }

  @override
  void writeAsciiLiteral(Uint8List preEncoded) {
    _beforeValue();
    _sink.add(preEncoded);
  }

  @override
  void writeRawJson(Uint8List rawJson) {
    _beforeValue();
    _sink.add(rawJson);
  }

  @override
  void writeString(String value) {
    _beforeValue();
    JsonUtf8Encoder.writeString(value, _sink);
  }

  @override
  void writeInt(int value) {
    _beforeValue();
    JsonUtf8Encoder.writeInt(value, _sink);
  }

  @override
  void writeDouble(double value) {
    _beforeValue();
    JsonUtf8Encoder.writeDouble(value, _sink);
  }

  @override
  void writeBool(bool value) {
    _beforeValue();
    JsonUtf8Encoder.writeBool(value, _sink);
  }

  @override
  void writeNull() {
    _beforeValue();
    JsonUtf8Encoder.writeNull(_sink);
  }
}

// =============================================================================
// Pure Dart Private Span Helpers (Fallbacks & Shared Algorithms)
// =============================================================================

const String _digitPairs =
    "00010203040506070809"
    "10111213141516171819"
    "20212223242526272829"
    "30313233343536373839"
    "40414243444546474849"
    "50515253545556575859"
    "60616263646566676869"
    "70717273747576777879"
    "80818283848586878889"
    "90919293949596979899";

@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
int _digitCountNegative(int v) {
  if (v > -10) return 1;
  if (v > -100) return 2;
  if (v > -1000) return 3;
  if (v > -10000) return 4;
  if (v > -100000) return 5;
  if (v > -1000000) return 6;
  if (v > -10000000) return 7;
  if (v > -100000000) return 8;
  if (v > -1000000000) return 9;
  if (v > -10000000000) return 10;
  if (v > -100000000000) return 11;
  if (v > -1000000000000) return 12;
  if (v > -10000000000000) return 13;
  if (v > -100000000000000) return 14;
  if (v > -1000000000000000) return 15;
  if (v > -10000000000000000) return 16;
  if (v > -100000000000000000) return 17;
  if (v > -1000000000000000000) return 18;
  return 19;
}

const String _hexDigits = "0123456789abcdef";

/// Web-safe 32-bit integer multiplication performing exact modulo 2^32
/// multiplication with 31-bit non-negative masking (`& 0x7fffffff`), safe
/// against JavaScript 53-bit float mantissa precision limits.
@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
int _imul32(int a, int b) {
  final aLo = a & 0xffff;
  final aHi = (a >> 16) & 0xffff;
  final bLo = b & 0xffff;
  final bHi = (b >> 16) & 0xffff;
  final lo = aLo * bLo;
  final hi = aLo * bHi + aHi * bLo;
  return ((lo + ((hi & 0xffff) << 16)) & 0x7fffffff);
}

@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
bool _isHexDigit(int b) =>
    (b >= 48 && b <= 57) || (b >= 65 && b <= 70) || (b >= 97 && b <= 102);

@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
bool _isValidEscapeChar(int b) =>
    b == 34 ||
    b == 92 ||
    b == 47 ||
    b == 98 ||
    b == 102 ||
    b == 110 ||
    b == 114 ||
    b == 116 ||
    b == 117;

@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
int _validateEscape(Uint8List bytes, int escOffset, int endOffset) {
  if (escOffset >= endOffset) {
    throw FormatException(
      'Unterminated escape sequence at offset ${escOffset - 1}',
      bytes,
      escOffset - 1,
    );
  }
  final esc = bytes[escOffset];
  if (esc == 117) {
    // 'u'
    if (escOffset + 5 > endOffset) {
      throw FormatException(
        'Incomplete unicode escape at offset ${escOffset - 1}',
        bytes,
        escOffset - 1,
      );
    }
    for (var k = 1; k <= 4; k++) {
      final hc = bytes[escOffset + k];
      if (!_isHexDigit(hc)) {
        throw FormatException(
          'Invalid hex digit "${String.fromCharCode(hc)}" at offset ${escOffset + k}',
          bytes,
          escOffset + k,
        );
      }
    }
    return escOffset + 5;
  }
  if (!_isValidEscapeChar(esc)) {
    throw FormatException(
      'Invalid escape character "${String.fromCharCode(esc)}" at offset $escOffset',
      bytes,
      escOffset,
    );
  }
  return escOffset + 1;
}

int _writeStringToBufferUtf8(String value, Uint8List buffer, int offset) {
  final len = value.length;
  if (offset < 0 || offset > buffer.length) {
    throw RangeError.range(offset, 0, buffer.length, 'offset');
  }

  // Fast path: check if string is pure ASCII and requires no escaping
  var isPureAscii = true;
  for (var i = 0; i < len; i++) {
    final c = value.codeUnitAt(i);
    if (c < 0x20 || c == 0x22 || c == 0x5C || c >= 0x80) {
      isPureAscii = false;
      break;
    }
  }

  if (isPureAscii) {
    final requiredLen = len + 2;
    if (offset + requiredLen > buffer.length) {
      throw RangeError.range(
        offset,
        0,
        buffer.length >= requiredLen ? buffer.length - requiredLen : 0,
        'offset',
      );
    }
    buffer[offset] = 0x22; // '"'
    for (var i = 0; i < len; i++) {
      buffer[offset + 1 + i] = value.codeUnitAt(i);
    }
    buffer[offset + 1 + len] = 0x22; // '"'
    return requiredLen;
  }

  // General path: calculate exact required length first to ensure atomic rollback
  var requiredLen = 2; // For opening and closing quotes
  for (var i = 0; i < len; i++) {
    final c = value.codeUnitAt(i);
    switch (c) {
      case 0x22: // '"'
      case 0x5C: // '\\'
      case 0x08: // '\b'
      case 0x0C: // '\f'
      case 0x0A: // '\n'
      case 0x0D: // '\r'
      case 0x09: // '\t'
        requiredLen += 2;
        break;
      default:
        if (c < 0x20) {
          requiredLen += 6; // \u00XX
        } else if (c <= 0x7F) {
          requiredLen += 1;
        } else if (c <= 0x7FF) {
          requiredLen += 2;
        } else if (c >= 0xD800 && c <= 0xDBFF) {
          if (i + 1 < len) {
            final c2 = value.codeUnitAt(i + 1);
            if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
              i++;
              requiredLen += 4;
              break;
            }
          }
          // Isolated high surrogate -> \uXXXX (6 bytes)
          requiredLen += 6;
        } else if (c >= 0xDC00 && c <= 0xDFFF) {
          // Isolated low surrogate -> \uXXXX (6 bytes)
          requiredLen += 6;
        } else {
          requiredLen += 3;
        }
        break;
    }
  }

  if (offset + requiredLen > buffer.length) {
    throw RangeError.range(
      offset,
      0,
      buffer.length >= requiredLen ? buffer.length - requiredLen : 0,
      'offset',
    );
  }

  var cursor = offset;
  buffer[cursor++] = 0x22; // '"'

  for (var i = 0; i < len; i++) {
    final c = value.codeUnitAt(i);
    switch (c) {
      case 0x22:
        buffer[cursor++] = 0x5C;
        buffer[cursor++] = 0x22;
        break;
      case 0x5C:
        buffer[cursor++] = 0x5C;
        buffer[cursor++] = 0x5C;
        break;
      case 0x08:
        buffer[cursor++] = 0x5C;
        buffer[cursor++] = 0x62; // 'b'
        break;
      case 0x0C:
        buffer[cursor++] = 0x5C;
        buffer[cursor++] = 0x66; // 'f'
        break;
      case 0x0A:
        buffer[cursor++] = 0x5C;
        buffer[cursor++] = 0x6E; // 'n'
        break;
      case 0x0D:
        buffer[cursor++] = 0x5C;
        buffer[cursor++] = 0x72; // 'r'
        break;
      case 0x09:
        buffer[cursor++] = 0x5C;
        buffer[cursor++] = 0x74; // 't'
        break;
      default:
        if (c < 0x20) {
          buffer[cursor++] = 0x5C;
          buffer[cursor++] = 0x75; // 'u'
          buffer[cursor++] = 0x30; // '0'
          buffer[cursor++] = 0x30; // '0'
          buffer[cursor++] = _hexDigits.codeUnitAt((c >> 4) & 0xF);
          buffer[cursor++] = _hexDigits.codeUnitAt(c & 0xF);
        } else if (c <= 0x7F) {
          buffer[cursor++] = c;
        } else if (c <= 0x7FF) {
          buffer[cursor++] = 0xC0 | (c >> 6);
          buffer[cursor++] = 0x80 | (c & 0x3F);
        } else if (c >= 0xD800 && c <= 0xDBFF) {
          if (i + 1 < len) {
            final c2 = value.codeUnitAt(i + 1);
            if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
              i++;
              final codePoint = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00);
              buffer[cursor++] = 0xF0 | (codePoint >> 18);
              buffer[cursor++] = 0x80 | ((codePoint >> 12) & 0x3F);
              buffer[cursor++] = 0x80 | ((codePoint >> 6) & 0x3F);
              buffer[cursor++] = 0x80 | (codePoint & 0x3F);
              break;
            }
          }
          // Isolated high surrogate -> \uXXXX
          buffer[cursor++] = 0x5C;
          buffer[cursor++] = 0x75; // 'u'
          buffer[cursor++] = _hexDigits.codeUnitAt((c >> 12) & 0xF);
          buffer[cursor++] = _hexDigits.codeUnitAt((c >> 8) & 0xF);
          buffer[cursor++] = _hexDigits.codeUnitAt((c >> 4) & 0xF);
          buffer[cursor++] = _hexDigits.codeUnitAt(c & 0xF);
        } else if (c >= 0xDC00 && c <= 0xDFFF) {
          // Isolated low surrogate -> \uXXXX
          buffer[cursor++] = 0x5C;
          buffer[cursor++] = 0x75; // 'u'
          buffer[cursor++] = _hexDigits.codeUnitAt((c >> 12) & 0xF);
          buffer[cursor++] = _hexDigits.codeUnitAt((c >> 8) & 0xF);
          buffer[cursor++] = _hexDigits.codeUnitAt((c >> 4) & 0xF);
          buffer[cursor++] = _hexDigits.codeUnitAt(c & 0xF);
        } else {
          buffer[cursor++] = 0xE0 | (c >> 12);
          buffer[cursor++] = 0x80 | ((c >> 6) & 0x3F);
          buffer[cursor++] = 0x80 | (c & 0x3F);
        }
        break;
    }
  }

  buffer[cursor++] = 0x22; // '"'
  return cursor - offset;
}

int _writeDoubleToBufferUtf8(double value, Uint8List buffer, int offset) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'Must be finite');
  }
  if (offset < 0 || offset > buffer.length) {
    throw RangeError.range(offset, 0, buffer.length, 'offset');
  }

  // 1. Zero handling
  if (value == 0.0) {
    if (value.isNegative) {
      if (offset + 4 > buffer.length) {
        throw RangeError.range(
          offset,
          0,
          buffer.length >= 4 ? buffer.length - 4 : 0,
          'offset',
        );
      }
      buffer[offset] = 0x2D; // '-'
      buffer[offset + 1] = 0x30; // '0'
      buffer[offset + 2] = 0x2E; // '.'
      buffer[offset + 3] = 0x30; // '0'
      return 4;
    } else {
      if (offset + 3 > buffer.length) {
        throw RangeError.range(
          offset,
          0,
          buffer.length >= 3 ? buffer.length - 3 : 0,
          'offset',
        );
      }
      buffer[offset] = 0x30; // '0'
      buffer[offset + 1] = 0x2E; // '.'
      buffer[offset + 2] = 0x30; // '0'
      return 3;
    }
  }

  // 2. Integer float fast path (up to 15 digits)
  final isNeg = value.isNegative;
  final absVal = isNeg ? -value : value;
  final trunc = absVal.truncateToDouble();

  if (absVal == trunc && absVal <= 9007199254740991.0) {
    final intVal = absVal.toInt();
    final negVal = -intVal;
    final digitCount = _digitCountNegative(negVal);
    final totalLen = (isNeg ? 1 : 0) + digitCount + 2; // +2 for '.0'
    if (offset + totalLen > buffer.length) {
      throw RangeError.range(
        offset,
        0,
        buffer.length >= totalLen ? buffer.length - totalLen : 0,
        'offset',
      );
    }
    var cursor = offset;
    if (isNeg) {
      buffer[cursor++] = 0x2D; // '-'
    }
    var writePos = cursor + digitCount - 1;
    var temp = negVal;
    while (temp <= -100) {
      final next = temp ~/ 100;
      final rem = -(temp - next * 100);
      final pairIdx = rem << 1;
      buffer[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
      buffer[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
      writePos -= 2;
      temp = next;
    }
    if (temp <= -10) {
      final rem = -temp;
      final pairIdx = rem << 1;
      buffer[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
      buffer[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
    } else {
      buffer[writePos] = 48 - temp;
    }
    cursor += digitCount;
    buffer[cursor++] = 0x2E; // '.'
    buffer[cursor++] = 0x30; // '0'
    return totalLen;
  }

  // 3. Decimal fraction fast path (exact representation within 53-bit mantissa)
  if (absVal >= 1e-15 && absVal <= 1e15) {
    final intPart = absVal.toInt();
    final intPartDigits = intPart == 0 ? 0 : _digitCountNegative(-intPart);
    final maxFrac = 15 - intPartDigits;
    if (maxFrac > 0 && maxFrac <= 15) {
      final p10 = _powersOfTen[maxFrac];
      final scaled = absVal * p10;
      if (scaled <= 9007199254740991.0) {
        var intVal = scaled.round();
        if (intVal / p10 == absVal) {
          // Exactly representable! Strip trailing zeros to get shortest representation.
          var k = maxFrac;
          while (k >= 4 && intVal % 10000 == 0) {
            intVal ~/= 10000;
            k -= 4;
          }
          while (k >= 2 && intVal % 100 == 0) {
            intVal ~/= 100;
            k -= 2;
          }
          if (k > 0 && intVal % 10 == 0) {
            intVal ~/= 10;
            k--;
          }
          if (k == 0) {
            // Integer float, append '.0'
            final negVal = -intVal;
            final digitCount = _digitCountNegative(negVal);
            final totalLen = (isNeg ? 1 : 0) + digitCount + 2;
            if (offset + totalLen > buffer.length) {
              throw RangeError.range(
                offset,
                0,
                buffer.length >= totalLen ? buffer.length - totalLen : 0,
                'offset',
              );
            }
            var cursor = offset;
            if (isNeg) {
              buffer[cursor++] = 0x2D; // '-'
            }
            var writePos = cursor + digitCount - 1;
            var temp = negVal;
            while (temp <= -100) {
              final next = temp ~/ 100;
              final rem = -(temp - next * 100);
              final pairIdx = rem << 1;
              buffer[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
              buffer[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
              writePos -= 2;
              temp = next;
            }
            if (temp <= -10) {
              final rem = -temp;
              final pairIdx = rem << 1;
              buffer[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
              buffer[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
            } else {
              buffer[writePos] = 48 - temp;
            }
            cursor += digitCount;
            buffer[cursor++] = 0x2E; // '.'
            buffer[cursor++] = 0x30; // '0'
            return totalLen;
          }

          final negVal = -intVal;
          final numDigits = _digitCountNegative(negVal);
          if (numDigits > k) {
            // >= 1, e.g. 3.14 (k=2, intVal=314, numDigits=3)
            final totalLen = (isNeg ? 1 : 0) + numDigits + 1; // +1 for '.'
            if (offset + totalLen > buffer.length) {
              throw RangeError.range(
                offset,
                0,
                buffer.length >= totalLen ? buffer.length - totalLen : 0,
                'offset',
              );
            }
            var cursor = offset;
            if (isNeg) {
              buffer[cursor++] = 0x2D; // '-'
            }
            final digitsStart = cursor;
            var writePos = digitsStart + numDigits;
            var temp = negVal;
            var digitsWritten = 0;
            while (digitsWritten < k) {
              final next = temp ~/ 10;
              final rem = -(temp - next * 10);
              buffer[writePos--] = 48 + rem;
              temp = next;
              digitsWritten++;
            }
            buffer[writePos--] = 0x2E; // '.'
            while (temp <= -100) {
              final next = temp ~/ 100;
              final rem = -(temp - next * 100);
              final pairIdx = rem << 1;
              buffer[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
              buffer[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
              writePos -= 2;
              temp = next;
            }
            if (temp <= -10) {
              final rem = -temp;
              final pairIdx = rem << 1;
              buffer[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
              buffer[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
            } else {
              buffer[writePos] = 48 - temp;
            }
            return totalLen;
          } else {
            // < 1, e.g. 0.05 (k=2, intVal=5, numDigits=1)
            final leadingZeros = k - numDigits;
            final totalLen =
                (isNeg ? 1 : 0) +
                2 +
                leadingZeros +
                numDigits; // '0.' + zeros + digits
            if (offset + totalLen > buffer.length) {
              throw RangeError.range(
                offset,
                0,
                buffer.length >= totalLen ? buffer.length - totalLen : 0,
                'offset',
              );
            }
            var cursor = offset;
            if (isNeg) {
              buffer[cursor++] = 0x2D; // '-'
            }
            buffer[cursor++] = 0x30; // '0'
            buffer[cursor++] = 0x2E; // '.'
            for (var z = 0; z < leadingZeros; z++) {
              buffer[cursor++] = 0x30; // '0'
            }
            var writePos = cursor + numDigits - 1;
            var temp = negVal;
            while (temp <= -100) {
              final next = temp ~/ 100;
              final rem = -(temp - next * 100);
              final pairIdx = rem << 1;
              buffer[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
              buffer[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
              writePos -= 2;
              temp = next;
            }
            if (temp <= -10) {
              final rem = -temp;
              final pairIdx = rem << 1;
              buffer[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
              buffer[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
            } else {
              buffer[writePos] = 48 - temp;
            }
            return totalLen;
          }
        }
      }
    }
  }

  // 4. Return 0 when exact 53-bit mantissa scaling is not possible.
  // TODO(kevmoo): Pure-Dart Dragonbox/Ryu Port:
  // Port a pure-Dart shortest float formatting algorithm (Dragonbox/Grisu2)
  // directly into Uint8List buffers to eliminate fallback to C++ Grisu2 or
  // value.toString() on numbers with > 15 digits or subnormals.
  return 0;
}

Object? _parseValueFromReader(
  JsonTokenReader reader,
  Object? Function(Object? key, Object? value)? reviver,
) {
  final type = reader.peek();
  switch (type) {
    case JsonTokenType.beginObject:
      reader.beginObject();
      final map = <String, dynamic>{};
      while (reader.hasNext()) {
        final key = reader.nextName();
        var value = _parseValueFromReader(reader, reviver);
        if (reviver != null) {
          value = reviver(key, value);
        }
        map[key] = value;
      }
      reader.endObject();
      return map;
    case JsonTokenType.beginArray:
      reader.beginArray();
      final list = <dynamic>[];
      while (reader.hasNext()) {
        final index = list.length;
        var value = _parseValueFromReader(reader, reviver);
        if (reviver != null) {
          value = reviver(index, value);
        }
        list.add(value);
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
      throw FormatException('Unexpected JSON token: $type');
  }
}

const List<double> _powersOfTen = [
  1.0,
  1e1,
  1e2,
  1e3,
  1e4,
  1e5,
  1e6,
  1e7,
  1e8,
  1e9,
  1e10,
  1e11,
  1e12,
  1e13,
  1e14,
  1e15,
  1e16,
  1e17,
  1e18,
  1e19,
  1e20,
  1e21,
  1e22,
];

@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
bool _isWs(int b) => b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D;

const List<int> _powersOf10Int = [
  1,
  10,
  100,
  1000,
  10000,
  100000,
  1000000,
  10000000,
  100000000,
  1000000000,
  10000000000,
  100000000000,
  1000000000000,
  10000000000000,
  100000000000000,
  1000000000000000,
  10000000000000000,
  100000000000000000,
  1000000000000000000,
];

int _skipScalar(Uint8List bytes, int offset) {
  if (offset >= bytes.length) {
    throw FormatException('Unexpected end of document', bytes, offset);
  }
  final b = bytes[offset];
  if (b == 116) {
    // 'true'
    if (offset + 4 > bytes.length ||
        bytes[offset + 1] != 114 ||
        bytes[offset + 2] != 117 ||
        bytes[offset + 3] != 101) {
      throw FormatException('Expected true at offset $offset', bytes, offset);
    }
    if (offset + 4 < bytes.length &&
        bytes[offset + 4] != 44 &&
        bytes[offset + 4] != 125 &&
        bytes[offset + 4] != 93 &&
        !_isWs(bytes[offset + 4])) {
      throw FormatException(
        'Invalid JSON token starting with true at offset $offset',
        bytes,
        offset,
      );
    }
    return offset + 4;
  }
  if (b == 102) {
    // 'false'
    if (offset + 5 > bytes.length ||
        bytes[offset + 1] != 97 ||
        bytes[offset + 2] != 108 ||
        bytes[offset + 3] != 115 ||
        bytes[offset + 4] != 101) {
      throw FormatException('Expected false at offset $offset', bytes, offset);
    }
    if (offset + 5 < bytes.length &&
        bytes[offset + 5] != 44 &&
        bytes[offset + 5] != 125 &&
        bytes[offset + 5] != 93 &&
        !_isWs(bytes[offset + 5])) {
      throw FormatException(
        'Invalid JSON token starting with false at offset $offset',
        bytes,
        offset,
      );
    }
    return offset + 5;
  }
  if (b == 110) {
    // 'null'
    if (offset + 4 > bytes.length ||
        bytes[offset + 1] != 117 ||
        bytes[offset + 2] != 108 ||
        bytes[offset + 3] != 108) {
      throw FormatException('Expected null at offset $offset', bytes, offset);
    }
    if (offset + 4 < bytes.length &&
        bytes[offset + 4] != 44 &&
        bytes[offset + 4] != 125 &&
        bytes[offset + 4] != 93 &&
        !_isWs(bytes[offset + 4])) {
      throw FormatException(
        'Invalid JSON token starting with null at offset $offset',
        bytes,
        offset,
      );
    }
    return offset + 4;
  }
  if (b == 45 || (b >= 48 && b <= 57)) {
    return _scanNumberSpan(bytes, offset);
  }
  throw FormatException(
    'Invalid JSON value starting with "${String.fromCharCode(b)}" at offset $offset',
    bytes,
    offset,
  );
}

int _scanNumberSpan(Uint8List bytes, int offset) {
  var i = offset;
  if (i >= bytes.length) {
    throw FormatException('Unexpected end of document', bytes, offset);
  }
  if (bytes[i] == 45) {
    // '-'
    i++;
    if (i >= bytes.length) {
      throw FormatException('Invalid number at offset $offset', bytes, offset);
    }
  }

  // Integer part:
  if (bytes[i] == 48) {
    // '0'
    i++;
    // Leading zero cannot be followed by another digit
    if (i < bytes.length && bytes[i] >= 48 && bytes[i] <= 57) {
      throw FormatException(
        'Leading zeros are not permitted at offset $offset',
        bytes,
        offset,
      );
    }
  } else if (bytes[i] >= 49 && bytes[i] <= 57) {
    // '1'..'9'
    while (i < bytes.length && bytes[i] >= 48 && bytes[i] <= 57) {
      i++;
    }
  } else {
    throw FormatException('Invalid number at offset $offset', bytes, offset);
  }

  // Fraction part (optional):
  if (i < bytes.length && bytes[i] == 46) {
    // '.'
    i++;
    if (i >= bytes.length || bytes[i] < 48 || bytes[i] > 57) {
      throw FormatException(
        'Decimal point must be followed by at least one digit at offset $offset',
        bytes,
        offset,
      );
    }
    while (i < bytes.length && bytes[i] >= 48 && bytes[i] <= 57) {
      i++;
    }
  }

  // Exponent part (optional):
  if (i < bytes.length && (bytes[i] == 101 || bytes[i] == 69)) {
    // 'e' or 'E'
    i++;
    if (i < bytes.length && (bytes[i] == 43 || bytes[i] == 45)) {
      i++;
    }
    if (i >= bytes.length || bytes[i] < 48 || bytes[i] > 57) {
      throw FormatException(
        'Exponent must be followed by at least one digit at offset $offset',
        bytes,
        offset,
      );
    }
    while (i < bytes.length && bytes[i] >= 48 && bytes[i] <= 57) {
      i++;
    }
  }

  // Ensure trailing character is a valid delimiter
  if (i < bytes.length &&
      bytes[i] != 44 &&
      bytes[i] != 125 &&
      bytes[i] != 93 &&
      !_isWs(bytes[i])) {
    throw FormatException(
      'Unexpected character in number literal at offset $i',
      bytes,
      i,
    );
  }

  return i;
}

double? _tryParseDoubleUtf8(
  Uint8List source,
  int start,
  int end, {
  bool allowFallback = true,
}) {
  if (start >= end || start < 0 || end > source.length) return null;

  var i = start;
  while (i < end &&
      (source[i] == 0x20 ||
          source[i] == 0x09 ||
          source[i] == 0x0A ||
          source[i] == 0x0D)) {
    i++;
  }
  if (i >= end) return null;

  var actualEnd = end;
  while (actualEnd > i &&
      (source[actualEnd - 1] == 0x20 ||
          source[actualEnd - 1] == 0x09 ||
          source[actualEnd - 1] == 0x0A ||
          source[actualEnd - 1] == 0x0D)) {
    actualEnd--;
  }
  if (i >= actualEnd) return null;

  final sliceStart = i;
  var isNegative = false;
  if (source[i] == 45) {
    // '-'
    isNegative = true;
    i++;
    if (i >= actualEnd) return null;
  }

  int mantissa = 0;
  int digitCount = 0;
  var hasLeadingZero = false;

  // Integer part:
  if (source[i] == 48) {
    // '0'
    hasLeadingZero = true;
    digitCount = 0;
    i++;
    // Leading zero cannot be followed by another digit
    if (i < actualEnd && source[i] >= 48 && source[i] <= 57) {
      return null;
    }
  } else if (source[i] >= 49 && source[i] <= 57) {
    // '1'..'9'
    while (i < actualEnd && source[i] >= 48 && source[i] <= 57) {
      if (digitCount < 16) {
        mantissa = mantissa * 10 + (source[i] - 48);
        digitCount++;
      }
      i++;
    }
  } else {
    return null;
  }

  int decimalExp = 0;
  // Fraction part (optional):
  if (i < actualEnd && source[i] == 46) {
    // '.'
    i++;
    if (i >= actualEnd || source[i] < 48 || source[i] > 57) {
      return null;
    }
    while (i < actualEnd && source[i] >= 48 && source[i] <= 57) {
      if (mantissa == 0 && source[i] == 48) {
        decimalExp--;
      } else if (digitCount < 16) {
        mantissa = mantissa * 10 + (source[i] - 48);
        digitCount++;
        decimalExp--;
      }
      i++;
    }
  }

  // Exponent part (optional):
  if (i < actualEnd && (source[i] == 101 || source[i] == 69)) {
    // 'e' or 'E'
    i++;
    var expNegative = false;
    if (i < actualEnd && (source[i] == 43 || source[i] == 45)) {
      // '+' or '-'
      if (source[i] == 45) expNegative = true;
      i++;
    }
    if (i >= actualEnd || source[i] < 48 || source[i] > 57) {
      return null;
    }
    var explicitExp = 0;
    while (i < actualEnd && source[i] >= 48 && source[i] <= 57) {
      if (explicitExp < 1000) {
        explicitExp = explicitExp * 10 + (source[i] - 48);
      }
      i++;
    }
    decimalExp += expNegative ? -explicitExp : explicitExp;
  }

  if (i != actualEnd) return null;

  // Exact fast path if mantissa <= 2^53 (up to 15 decimal digits) and exponent within power table
  if (digitCount <= 15 && decimalExp >= -22 && decimalExp <= 22) {
    double result = isNegative ? -mantissa.toDouble() : mantissa.toDouble();
    if (decimalExp > 0) {
      result *= _powersOfTen[decimalExp];
    } else if (decimalExp < 0) {
      result /= _powersOfTen[-decimalExp];
    }
    if (hasLeadingZero && mantissa == 0 && isNegative) {
      return -0.0;
    }
    return result;
  }

  if (!allowFallback) return null;

  // Fallback to exact platform float parser
  return double.tryParse(String.fromCharCodes(source, sliceStart, actualEnd));
}

const List<int> _maxInt64Digits = [
  57,
  50,
  50,
  51,
  51,
  55,
  50,
  48,
  51,
  54,
  56,
  53,
  52,
  55,
  55,
  53,
  56,
  48,
  55,
]; // '9223372036854775807'
const List<int> _minInt64Digits = [
  57,
  50,
  50,
  51,
  51,
  55,
  50,
  48,
  51,
  54,
  56,
  53,
  52,
  55,
  55,
  53,
  56,
  48,
  56,
]; // '9223372036854775808'

int? _tryParseIntUtf8(Uint8List source, int start, int end) {
  if (start >= end || start < 0 || end > source.length) return null;

  var i = start;
  while (i < end &&
      (source[i] == 0x20 ||
          source[i] == 0x09 ||
          source[i] == 0x0A ||
          source[i] == 0x0D)) {
    i++;
  }
  if (i >= end) return null;

  var actualEnd = end;
  while (actualEnd > i &&
      (source[actualEnd - 1] == 0x20 ||
          source[actualEnd - 1] == 0x09 ||
          source[actualEnd - 1] == 0x0A ||
          source[actualEnd - 1] == 0x0D)) {
    actualEnd--;
  }
  if (i >= actualEnd) return null;

  var negative = false;
  if (source[i] == 45) {
    // '-'
    negative = true;
    i++;
    if (i >= actualEnd) return null;
  }

  // Integer part:
  if (source[i] == 48) {
    // '0'
    i++;
    // Leading zero cannot be followed by another digit
    if (i < actualEnd) return null;
    return 0;
  }

  if (source[i] < 49 || source[i] > 57) {
    // '1'..'9'
    return null;
  }

  final digitsStart = i;
  while (i < actualEnd) {
    final byte = source[i];
    if (byte < 48 || byte > 57) return null;
    i++;
  }

  final numDigits = actualEnd - digitsStart;
  if (numDigits > 19) return null;
  if (numDigits == 19) {
    final limit = negative ? _minInt64Digits : _maxInt64Digits;
    for (var k = 0; k < 19; k++) {
      final d = source[digitsStart + k];
      final lim = limit[k];
      if (d < lim) break;
      if (d > lim) return null;
    }
  }

  int value = 0;
  for (var k = digitsStart; k < actualEnd; k++) {
    value = value * 10 - (source[k] - 48);
  }
  return negative ? value : -value;
}

@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
bool? _tryParseBoolUtf8(Uint8List source, int start, int end) {
  final len = end - start;
  if (start < 0 || end > source.length || len < 4 || len > 5) return null;

  if (len == 4 &&
      source[start] == 116 &&
      source[start + 1] == 114 &&
      source[start + 2] == 117 &&
      source[start + 3] == 101) {
    return true;
  }
  if (len == 5 &&
      source[start] == 102 &&
      source[start + 1] == 97 &&
      source[start + 2] == 108 &&
      source[start + 3] == 115 &&
      source[start + 4] == 101) {
    return false;
  }
  return null;
}

bool _equalsAsciiUtf8(
  Uint8List source,
  int start,
  int end,
  String asciiString,
) {
  if (start < 0 || end > source.length || end - start != asciiString.length) {
    return false;
  }
  for (var i = 0; i < asciiString.length; i++) {
    final c = asciiString.codeUnitAt(i);
    if (c > 0x7F || source[start + i] != c) return false;
  }
  return true;
}

@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
bool _isNullUtf8(Uint8List source, int start, int end) {
  return (end - start == 4) &&
      start >= 0 &&
      end <= source.length &&
      source[start] == 110 &&
      source[start + 1] == 117 &&
      source[start + 2] == 108 &&
      source[start + 3] == 108;
}

@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
bool _isVerbatimUtf8(Uint8List source, int start, int end) {
  if (start < 0 || end > source.length || start > end) return false;
  for (var i = start; i < end; i++) {
    final b = source[i];
    if (b < 0x20 || b > 0x7E || b == 0x22 || b == 0x5C) {
      return false; // Non-ASCII, control char, quote, or backslash
    }
  }
  return true;
}

String _decodeStringUtf8(
  Uint8List source,
  int start,
  int end, {
  bool allowMalformed = false,
}) {
  if (start < 0 || end > source.length || start > end) {
    throw RangeError('Invalid byte span [$start, $end)');
  }
  if (start == end) return '';
  var maxByte = 0;
  var hasBackslash = false;
  for (var i = start; i < end; i++) {
    final b = source[i];
    if (b < 0x20) {
      throw FormatException(
        'Unescaped control character in string literal at offset $i',
        source,
        i,
      );
    }
    maxByte |= b;
    if (b == 92) {
      hasBackslash = true;
      break;
    }
  }

  if (!hasBackslash) {
    if (maxByte <= 0x7F) {
      return String.fromCharCodes(source, start, end);
    }
    return utf8.decode(
      Uint8List.sublistView(source, start, end),
      allowMalformed: allowMalformed,
    );
  }

  final buffer = StringBuffer();
  var i = start;
  var runStart = start;
  while (i < end) {
    final b = source[i];
    if (b < 0x20) {
      throw FormatException(
        'Unescaped control character in string literal at offset $i',
        source,
        i,
      );
    }
    if (b == 92) {
      // '\\'
      if (i > runStart) {
        var runMax = 0;
        for (var k = runStart; k < i; k++) {
          runMax |= source[k];
        }
        if (runMax <= 0x7F) {
          buffer.write(String.fromCharCodes(source, runStart, i));
        } else {
          buffer.write(
            utf8.decode(
              Uint8List.sublistView(source, runStart, i),
              allowMalformed: allowMalformed,
            ),
          );
        }
      }
      i++; // skip '\\'
      if (i >= end) {
        throw FormatException('Unexpected EOF in escape sequence', source, i);
      }
      final esc = source[i++];
      switch (esc) {
        case 34: // '"'
          buffer.writeCharCode(34);
        case 92: // '\\'
          buffer.writeCharCode(92);
        case 47: // '/'
          buffer.writeCharCode(47);
        case 98: // 'b'
          buffer.writeCharCode(8);
        case 102: // 'f'
          buffer.writeCharCode(12);
        case 110: // 'n'
          buffer.writeCharCode(10);
        case 114: // 'r'
          buffer.writeCharCode(13);
        case 116: // 't'
          buffer.writeCharCode(9);
        case 117: // \uXXXX
          if (i + 4 > end) {
            throw FormatException('Incomplete unicode escape', source, i);
          }
          final codeUnit = _parseHex4(source, i);
          i += 4;
          if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
            if (i + 6 <= end && source[i] == 92 && source[i + 1] == 117) {
              final low = _parseHex4(source, i + 2);
              if (low >= 0xDC00 && low <= 0xDFFF) {
                i += 6;
                final codePoint =
                    0x10000 + ((codeUnit - 0xD800) << 10) + (low - 0xDC00);
                buffer.writeCharCode(codePoint);
                break;
              }
            }
          }
          buffer.writeCharCode(codeUnit);
        default:
          throw FormatException(
            'Invalid escape character: ${String.fromCharCode(esc)}',
            source,
            i - 1,
          );
      }
      runStart = i;
    } else {
      i++;
    }
  }
  if (i > runStart) {
    var runMax = 0;
    for (var k = runStart; k < i; k++) {
      runMax |= source[k];
    }
    if (runMax <= 0x7F) {
      buffer.write(String.fromCharCodes(source, runStart, i));
    } else {
      buffer.write(
        utf8.decode(
          Uint8List.sublistView(source, runStart, i),
          allowMalformed: allowMalformed,
        ),
      );
    }
  }
  return buffer.toString();
}

@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
int _parseHex4(Uint8List source, int offset) {
  var v = 0;
  for (var i = 0; i < 4; i++) {
    final b = source[offset + i];
    final int digit;
    if (b >= 48 && b <= 57) {
      digit = b - 48;
    } else if (b >= 65 && b <= 70) {
      digit = b - 55;
    } else if (b >= 97 && b <= 102) {
      digit = b - 87;
    } else {
      throw FormatException(
        'Invalid hex digit: ${String.fromCharCode(b)}',
        source,
        offset + i,
      );
    }
    v = (v << 4) | digit;
  }
  return v;
}

@pragma('vm:prefer-inline')
@pragma('wasm:prefer-inline')
bool _isSingleQuotedString(Uint8List bytes) {
  return _isSingleQuotedSlice(bytes, 0, bytes.length);
}

bool _isSingleQuotedSlice(Uint8List bytes, int start, int end) {
  if (start < 0 ||
      end > bytes.length ||
      end - start < 2 ||
      bytes[start] != 0x22 ||
      bytes[end - 1] != 0x22) {
    return false;
  }
  var i = start + 1;
  final last = end - 1;
  while (i < last) {
    final b = bytes[i];
    if (b == 0x22 || b < 0x20) {
      return false;
    }
    if (b == 0x5C) {
      if (i + 1 >= last) return false;
      final next = bytes[i + 1];
      if (next == 0x22 || // '"'
          next == 0x5C || // '\'
          next == 0x2F || // '/'
          next == 0x62 || // 'b'
          next == 0x66 || // 'f'
          next == 0x6E || // 'n'
          next == 0x72 || // 'r'
          next == 0x74) {
        // 't'
        i += 2;
      } else if (next == 0x75) {
        // 'u'
        if (i + 5 >= last + 1) return false;
        for (var j = i + 2; j <= i + 5; j++) {
          final c = bytes[j];
          final isHex =
              (c >= 48 && c <= 57) ||
              (c >= 65 && c <= 70) ||
              (c >= 97 && c <= 102);
          if (!isHex) return false;
        }
        i += 6;
      } else {
        return false;
      }
    } else {
      i++;
    }
  }
  return i == last;
}
