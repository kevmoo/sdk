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
}) => Uint8List.fromList(JsonUtf8Encoder(null, toEncodable).convert(value));

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
        h = ((h ^ encodedKeys[off + j]) * 0x01000193) & 0x7fffffff;
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
      encodedKeys,
      offsets,
      lengths,
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
      h = ((h ^ source[i]) * 0x01000193) & 0x7fffffff;
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
    return utf8.decoder.startChunkedConversion(
      JsonDecoder(reviver).startChunkedConversion(sink),
    );
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
    return options.selectKey(bytes, start, end);
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
      var mask = (b == 123) ? 1 : 0;
      i++;
      while (i < bytes.length && depth > 0) {
        final c = bytes[i++];
        if (c == 34) {
          while (i < bytes.length) {
            final sc = bytes[i++];
            if (sc == 92) {
              if (i < bytes.length) i++;
            } else if (sc == 34) {
              break;
            }
          }
        } else if (c == 123 || c == 91) {
          if (depth >= 64) {
            throw FormatException(
              'Nesting depth exceeds limit of 64 at offset ${i - 1}',
              bytes,
              i - 1,
            );
          }
          if (c == 123) {
            mask |= (1 << depth);
          } else {
            mask &= ~(1 << depth);
          }
          depth++;
        } else if (c == 125) {
          if (depth == 0 || ((mask >> (depth - 1)) & 1) != 1) {
            throw FormatException(
              'Mismatched "}" at offset ${i - 1}',
              bytes,
              i - 1,
            );
          }
          depth--;
        } else if (c == 93) {
          if (depth == 0 || ((mask >> (depth - 1)) & 1) != 0) {
            throw FormatException(
              'Mismatched "]" at offset ${i - 1}',
              bytes,
              i - 1,
            );
          }
          depth--;
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
      while (i < bytes.length) {
        final c = bytes[i++];
        if (c == 92) {
          if (i < bytes.length) i++;
        } else if (c == 34) {
          break;
        }
      }
      return i;
    }
    while (i < bytes.length &&
        bytes[i] != 44 &&
        bytes[i] != 125 &&
        bytes[i] != 93 &&
        bytes[i] != 0x20 &&
        bytes[i] != 0x09 &&
        bytes[i] != 0x0A &&
        bytes[i] != 0x0D) {
      i++;
    }
    return i;
  }

  /// Fast-skips JSON whitespace (0x20, 0x09, 0x0A, 0x0D) starting at [offset]
  /// and returns the offset of the next non-whitespace byte.
  static int skipWhitespace(Uint8List bytes, int offset) {
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
    var i = offset;
    if (i < bytes.length && bytes[i] == 34) i++;
    while (i < bytes.length) {
      final b = bytes[i++];
      if (b == 92) {
        if (i < bytes.length) i++;
      } else if (b == 34) {
        break;
      }
    }
    return i;
  }
}

/// An encoder that encodes an object directly into UTF-8 JSON bytes.
final class JsonUtf8Encoder extends Converter<Object?, List<int>> {
  /// Default buffer size used by the JSON-to-UTF-8 encoder.
  static const int _defaultBufferSize = 256;

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
  List<int> convert(Object? object) {
    var bytes = <List<int>>[];
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
    if (bytes.length == 1) return bytes[0];
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

  // --- Static Direct-To-Buffer Formatting Helpers ---

  /// Writes [value] with standard JSON escaping directly into [sink].
  static void writeString(String value, BytesBuilder sink) {
    sink.add(utf8.encode(jsonEncode(value)));
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
    final str = value.toString();
    for (var i = 0; i < str.length; i++) {
      sink.addByte(str.codeUnitAt(i));
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
    if (offset + len > buffer.length) {
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
    final digits = Uint8List(digitCount);
    var writePos = digitCount - 1;
    var temp = v;
    while (temp <= -100) {
      final next = temp ~/ 100;
      final rem = -(temp - next * 100);
      final pairIdx = rem << 1;
      digits[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
      digits[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
      writePos -= 2;
      temp = next;
    }
    if (temp <= -10) {
      final rem = -temp;
      final pairIdx = rem << 1;
      digits[writePos] = _digitPairs.codeUnitAt(pairIdx + 1);
      digits[writePos - 1] = _digitPairs.codeUnitAt(pairIdx);
    } else {
      digits[writePos] = 48 - temp;
    }
    sink.add(digits);
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
    buffer.setRange(offset, offset + asciiBytes.length, asciiBytes);
    return asciiBytes.length;
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
    buffer.setRange(offset, offset + rawJson.length, rawJson);
    return rawJson.length;
  }

  /// Safely writes an object property separator (comma if not first) and key
  /// prefix into [buffer], avoiding leading comma bugs on nullable/omitted fields.
  static int writePropertyPrefixToBuffer(
    Uint8List buffer,
    int offset,
    Uint8List asciiKey, {
    required bool isFirst,
  }) {
    final isQuoted = _isSingleQuotedString(asciiKey);
    final requiredLen =
        (isFirst ? 0 : 1) + asciiKey.length + (isQuoted ? 0 : 2) + 1;
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
    if (!isQuoted) {
      buffer[cursor++] = 0x22; // '"'
    }
    for (var i = 0; i < asciiKey.length; i++) {
      buffer[cursor++] = asciiKey[i];
    }
    if (!isQuoted) {
      buffer[cursor++] = 0x22; // '"'
    }
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

  void writeNumber(num number) {
    if (number is int) {
      if (index + 24 > buffer.length) {
        if (index > 0) {
          addChunk(buffer, 0, index);
          buffer = Uint8List(bufferSize);
          index = 0;
        }
      }
      if (index + 24 <= buffer.length) {
        index += JsonUtf8Encoder.writeIntToBuffer(number, buffer, index);
        return;
      }
    } else if (number is double && number.isFinite) {
      if (index + 32 > buffer.length) {
        if (index > 0) {
          addChunk(buffer, 0, index);
          buffer = Uint8List(bufferSize);
          index = 0;
        }
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
    for (var i = start; i < end; i++) {
      var char = string.codeUnitAt(i);
      if (char <= 0x7f) {
        writeByte(char);
      } else {
        if ((char & 0xF800) == 0xD800) {
          // Surrogate.
          if (char < 0xDC00 && i + 1 < end) {
            var nextChar = string.codeUnitAt(i + 1);
            if ((nextChar & 0xFC00) == 0xDC00) {
              char = 0x10000 + ((char & 0x3ff) << 10) + (nextChar & 0x3ff);
              writeFourByteCharCode(char);
              i++;
              continue;
            }
          }
          writeMultiByteCharCode(unicodeReplacementCharacterRune);
          continue;
        }
        writeMultiByteCharCode(char);
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
      addChunk(buffer, 0, index);
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

  _JsonTokenReader(this._bytes, {this.allowMalformed = false}) {
    if (_bytes.length >= 3 &&
        _bytes[0] == 0xEF &&
        _bytes[1] == 0xBB &&
        _bytes[2] == 0xBF) {
      _offset = 3;
    }
  }

  bool _isWs(int b) => b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D;

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
    }
  }

  void _afterReadingValue() {
    if (_stack.isNotEmpty) {
      _stack.last.state = _ReaderItemState.afterValue;
    }
  }

  @override
  JsonTokenType peek() {
    var i = _offset;
    while (i < _bytes.length && _isWs(_bytes[i])) {
      i++;
    }
    if (i >= _bytes.length) return JsonTokenType.endOfDocument;
    if (_stack.isNotEmpty && _stack.last.state == _ReaderItemState.afterValue) {
      final closingByte = _stack.last.type == _ContainerType.object ? 125 : 93;
      if (i < _bytes.length && _bytes[i] == 44) {
        i++;
        while (i < _bytes.length && _isWs(_bytes[i])) {
          i++;
        }
      } else if (i < _bytes.length && _bytes[i] == closingByte) {
        // Closing delimiter is valid
      } else {
        return JsonTokenType.none;
      }
    }
    if (i >= _bytes.length) return JsonTokenType.endOfDocument;
    final b = _bytes[i];
    switch (b) {
      case 123: // '{'
        return JsonTokenType.beginObject;
      case 125: // '}'
        return JsonTokenType.endObject;
      case 91: // '['
        return JsonTokenType.beginArray;
      case 93: // ']'
        return JsonTokenType.endArray;
      case 34: // '"'
        if (_stack.isNotEmpty &&
            _stack.last.type == _ContainerType.object &&
            _stack.last.state != _ReaderItemState.afterName) {
          return JsonTokenType.propertyName;
        }
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
          if (_offset < _bytes.length && _bytes[_offset] == closeChar) {
            throw FormatException(
              'Trailing comma before $closeStr at offset $_offset',
            );
          }
          return true;
        }
        throw FormatException('Expected "," or $closeStr at offset $_offset');
      } else if (top.state == _ReaderItemState.afterComma) {
        if (_bytes[_offset] == closeChar) {
          throw FormatException(
            'Trailing comma before $closeStr at offset $_offset',
          );
        }
        return true;
      } else if (top.state == _ReaderItemState.afterName) {
        return true;
      }
    }
    final b = _bytes[_offset];
    return b != 125 && b != 93;
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
        i += 2;
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
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  T _readValue<T>(T Function(int start, int end) parser) {
    final initialOffset = _offset;
    final initialFrameState = _stack.isNotEmpty ? _stack.last.state : null;
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
    try {
      return parser(start, i);
    } catch (_) {
      _offset = initialOffset;
      if (_stack.isNotEmpty && initialFrameState != null) {
        _stack.last.state = initialFrameState;
      }
      rethrow;
    }
  }

  @override
  int readInt() {
    return _readValue(
      (start, end) => JsonUtf8Decoder.parseInt(_bytes, start, end),
    );
  }

  @override
  double readDouble() {
    return _readValue(
      (start, end) => JsonUtf8Decoder.parseDouble(_bytes, start, end),
    );
  }

  @override
  num readNum() {
    return _readValue((start, end) {
      final asInt = JsonUtf8Decoder.tryParseInt(_bytes, start, end);
      if (asInt != null) return asInt;
      return JsonUtf8Decoder.parseDouble(_bytes, start, end);
    });
  }

  @override
  bool readBool() {
    return _readValue(
      (start, end) => JsonUtf8Decoder.parseBool(_bytes, start, end),
    );
  }

  @override
  void readNull() {
    _readValue((start, end) {
      if (!_isNullUtf8(_bytes, start, end)) {
        throw FormatException('Expected null at offset $start');
      }
    });
  }

  @override
  void skipValue() {
    _beforeReadingValue();
    if (_offset >= _bytes.length) return;
    final b = _bytes[_offset];
    if (b == 123 || b == 91) {
      var depth = 1;
      var mask = (b == 123) ? 1 : 0;
      _offset++;
      while (_offset < _bytes.length && depth > 0) {
        final c = _bytes[_offset++];
        if (c == 34) {
          while (_offset < _bytes.length) {
            final sc = _bytes[_offset++];
            if (sc == 92) {
              if (_offset < _bytes.length) _offset++;
            } else if (sc == 34) {
              break;
            }
          }
        } else if (c == 123 || c == 91) {
          if (depth >= _maxDepth) {
            throw FormatException(
              'Nesting depth exceeds limit of $_maxDepth at offset ${_offset - 1}',
              _bytes,
              _offset - 1,
            );
          }
          if (c == 123) {
            mask |= (1 << depth);
          } else {
            mask &= ~(1 << depth);
          }
          depth++;
        } else if (c == 125) {
          if (depth == 0 || ((mask >> (depth - 1)) & 1) != 1) {
            throw FormatException(
              'Mismatched "}" at offset ${_offset - 1}',
              _bytes,
              _offset - 1,
            );
          }
          depth--;
        } else if (c == 93) {
          if (depth == 0 || ((mask >> (depth - 1)) & 1) != 0) {
            throw FormatException(
              'Mismatched "]" at offset ${_offset - 1}',
              _bytes,
              _offset - 1,
            );
          }
          depth--;
        }
      }
      if (depth > 0) {
        throw FormatException(
          'Unclosed container at end of document',
          _bytes,
          _offset,
        );
      }
    } else if (b == 34) {
      _scanStringSpan();
    } else {
      var i = _offset;
      while (i < _bytes.length) {
        final c = _bytes[i];
        if (c == 44 || c == 125 || c == 93 || _isWs(c)) {
          break;
        }
        i++;
      }
      _offset = i;
    }
    _afterReadingValue();
  }

  @override
  (int start, int end) getTokenSpan() {
    var i = _offset;
    while (i < _bytes.length && _isWs(_bytes[i])) {
      i++;
    }
    if (_stack.isNotEmpty && _stack.last.state == _ReaderItemState.afterValue) {
      if (i < _bytes.length && _bytes[i] == 44) {
        i++;
        while (i < _bytes.length && _isWs(_bytes[i])) {
          i++;
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
          j += 2;
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
    final isQuoted = _isSingleQuotedString(asciiKey);
    if (!isQuoted) {
      _sink.addByte(34); // '"'
    }
    _sink.add(asciiKey);
    if (!isQuoted) {
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

num _pow10(int exp) {
  num res = 1;
  for (var j = 0; j < exp; j++) res *= 10;
  return res;
}

double? _tryParseDoubleUtf8(Uint8List source, int start, int end) {
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
    digitCount = 1;
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
      if (digitCount < 16) {
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
    if (source[start + i] != asciiString.codeUnitAt(i)) return false;
  }
  return true;
}

bool _isNullUtf8(Uint8List source, int start, int end) {
  return (end - start == 4) &&
      start >= 0 &&
      end <= source.length &&
      source[start] == 110 &&
      source[start + 1] == 117 &&
      source[start + 2] == 108 &&
      source[start + 3] == 108;
}

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
  if (start == end) return '';
  if (start < 0 || end > source.length || start > end) {
    throw RangeError('Invalid byte span [$start, $end)');
  }
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

int _utf8SequenceLength(int firstByte) {
  if (firstByte <= 0x7F) return 1;
  if ((firstByte & 0xE0) == 0xC0) return 2;
  if ((firstByte & 0xF0) == 0xE0) return 3;
  if ((firstByte & 0xF8) == 0xF0) return 4;
  return 1;
}

bool _isSingleQuotedString(Uint8List bytes) {
  if (bytes.length < 2 || bytes.first != 0x22 || bytes.last != 0x22) {
    return false;
  }
  var i = 1;
  final end = bytes.length - 1;
  while (i < end) {
    final b = bytes[i];
    if (b == 0x22) {
      return false;
    }
    if (b == 0x5C) {
      i += 2;
    } else {
      i++;
    }
  }
  return i == end;
}
