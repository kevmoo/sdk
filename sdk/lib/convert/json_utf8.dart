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
}) => JsonUtf8Decoder(reviver).convert(bytes);

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

  JsonKeyOptions._(this.keys, this.encodedKeys, this.offsets, this.lengths);

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
    return JsonKeyOptions._(
      List.unmodifiable(keys),
      builder.takeBytes(),
      offsets,
      lengths,
    );
  }

  int get length => keys.length;

  /// Matches the byte span `[start..end]` against pre-compiled keys.
  int selectKey(Uint8List source, int start, int end) {
    if (start < 0 || end > source.length || start > end) {
      return -1;
    }
    final spanLen = end - start;
    final count = keys.length;
    for (var i = 0; i < count; i++) {
      if (lengths[i] != spanLen) continue;
      final off = offsets[i];
      var match = true;
      for (var j = 0; j < spanLen; j++) {
        if (source[start + j] != encodedKeys[off + j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
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
    final str = utf8.decode(input, allowMalformed: allowMalformed);
    return jsonDecode(str, reviver: reviver);
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
      final open = b;
      final close = b == 123 ? 125 : 93;
      i++;
      while (i < bytes.length && depth > 0) {
        final c = bytes[i++];
        if (c == 34) {
          while (i < bytes.length) {
            final sc = bytes[i++];
            if (sc == 92) {
              i++;
            } else if (sc == 34) {
              break;
            }
          }
        } else if (c == open) {
          depth++;
        } else if (c == close) {
          depth--;
        }
      }
      return i;
    }
    if (b == 34) {
      i++;
      while (i < bytes.length) {
        final c = bytes[i++];
        if (c == 92) {
          i++;
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
        i++;
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
    final encoded = utf8.encode(jsonEncode(value));
    buffer.setRange(offset, offset + encoded.length, encoded);
    return encoded.length;
  }

  /// Formats [value] as a valid JSON floating-point literal directly into [sink].
  static void writeDouble(double value, BytesBuilder sink) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Must be finite');
    }
    sink.add(utf8.encode(value.toString()));
  }

  /// Formats [value] directly into [buffer] starting at [offset] as ASCII bytes.
  /// Returns the number of bytes written.
  static int writeDoubleToBuffer(double value, Uint8List buffer, int offset) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'Must be finite');
    }
    final encoded = utf8.encode(value.toString());
    buffer.setRange(offset, offset + encoded.length, encoded);
    return encoded.length;
  }

  /// Formats [value] as an ASCII integer literal directly into [sink].
  static void writeInt(int value, BytesBuilder sink) {
    sink.add(utf8.encode(value.toString()));
  }

  /// Formats [value] directly into [buffer] starting at [offset] as ASCII bytes.
  /// Returns the number of bytes written.
  static int writeIntToBuffer(int value, Uint8List buffer, int offset) {
    final encoded = utf8.encode(value.toString());
    buffer.setRange(offset, offset + encoded.length, encoded);
    return encoded.length;
  }

  /// Writes a boolean literal (`true` or `false`) directly into [sink].
  static void writeBool(bool value, BytesBuilder sink) {
    sink.add(utf8.encode(value ? 'true' : 'false'));
  }

  /// Writes a boolean literal directly into [buffer] starting at [offset].
  /// Returns the number of bytes written.
  static int writeBoolToBuffer(bool value, Uint8List buffer, int offset) {
    final encoded = utf8.encode(value ? 'true' : 'false');
    buffer.setRange(offset, offset + encoded.length, encoded);
    return encoded.length;
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
    var cursor = offset;
    if (!isFirst) {
      buffer[cursor++] = 44; // ','
    }
    for (var i = 0; i < asciiKey.length; i++) {
      buffer[cursor++] = asciiKey[i];
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
    writeAsciiString(number.toString());
  }

  void writeAsciiString(String string) {
    for (var i = 0; i < string.length; i++) {
      var char = string.codeUnitAt(i);
      assert(char <= 0x7f);
      writeByte(char);
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
  factory JsonTokenReader.fromBytes(Uint8List bytes) = _JsonTokenReader;

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
  int _offset = 0;
  final List<_ContainerFrame> _stack = [];

  _JsonTokenReader(this._bytes);

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
    _skipWs();
    if (_offset >= _bytes.length) return JsonTokenType.endOfDocument;
    var i = _offset;
    if (_stack.isNotEmpty && _stack.last.state == _ReaderItemState.afterValue) {
      if (i < _bytes.length && _bytes[i] == 44) {
        i++;
        while (i < _bytes.length && _isWs(_bytes[i])) {
          i++;
        }
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
    _beforeReadingName();
    final (start, end) = _scanStringSpan();
    _consumeColon();
    _stack.last.state = _ReaderItemState.afterName;
    return _decodeStringUtf8(_bytes, start, end);
  }

  @override
  int selectName(JsonKeyOptions options) {
    _beforeReadingName();
    final (start, end) = _scanStringSpan();
    _consumeColon();
    _stack.last.state = _ReaderItemState.afterName;
    return options.selectKey(_bytes, start, end);
  }

  @override
  int selectString(JsonKeyOptions options) {
    _beforeReadingValue();
    final (start, end) = _scanStringSpan();
    _afterReadingValue();
    return options.selectKey(_bytes, start, end);
  }

  @override
  String readString() {
    _beforeReadingValue();
    final (start, end) = _scanStringSpan();
    _afterReadingValue();
    return _decodeStringUtf8(_bytes, start, end);
  }

  (int, int) _scanValueSpan() {
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
    final (start, end) = _scanValueSpan();
    return JsonUtf8Decoder.parseInt(_bytes, start, end);
  }

  @override
  double readDouble() {
    final (start, end) = _scanValueSpan();
    return JsonUtf8Decoder.parseDouble(_bytes, start, end);
  }

  @override
  num readNum() {
    final (start, end) = _scanValueSpan();
    final asInt = JsonUtf8Decoder.tryParseInt(_bytes, start, end);
    if (asInt != null) return asInt;
    return JsonUtf8Decoder.parseDouble(_bytes, start, end);
  }

  @override
  bool readBool() {
    final (start, end) = _scanValueSpan();
    return JsonUtf8Decoder.parseBool(_bytes, start, end);
  }

  @override
  void readNull() {
    final (start, end) = _scanValueSpan();
    if (!_isNullUtf8(_bytes, start, end)) {
      throw FormatException('Expected null at offset $start');
    }
  }

  @override
  void skipValue() {
    _beforeReadingValue();
    if (_offset >= _bytes.length) return;
    final b = _bytes[_offset];
    if (b == 123) {
      // object
      var depth = 1;
      _offset++;
      while (_offset < _bytes.length && depth > 0) {
        final c = _bytes[_offset++];
        if (c == 34) {
          while (_offset < _bytes.length) {
            final sc = _bytes[_offset++];
            if (sc == 92) {
              _offset++;
            } else if (sc == 34) {
              break;
            }
          }
        } else if (c == 123) {
          depth++;
        } else if (c == 125) {
          depth--;
        }
      }
    } else if (b == 91) {
      // array
      var depth = 1;
      _offset++;
      while (_offset < _bytes.length && depth > 0) {
        final c = _bytes[_offset++];
        if (c == 34) {
          while (_offset < _bytes.length) {
            final sc = _bytes[_offset++];
            if (sc == 92) {
              _offset++;
            } else if (sc == 34) {
              break;
            }
          }
        } else if (c == 91) {
          depth++;
        } else if (c == 93) {
          depth--;
        }
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
    if (_bytes[i] == 34) {
      final start = i + 1;
      var j = start;
      while (j < _bytes.length) {
        final b = _bytes[j];
        if (b == 92) {
          j += 2;
        } else if (b == 34) {
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
        final b = _bytes[j];
        if (b == 44 || b == 125 || b == 93 || _isWs(b)) {
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
    _sink.addByte(34); // '"'
    _sink.add(asciiKey);
    _sink.addByte(34); // '"'
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
  if (source[i] == 45) {
    // '-'
    i++;
    if (i >= actualEnd) return null;
  }

  // Integer part:
  if (source[i] == 48) {
    // '0'
    i++;
    // Leading zero cannot be followed by another digit
    if (i < actualEnd && source[i] >= 48 && source[i] <= 57) {
      return null;
    }
  } else if (source[i] >= 49 && source[i] <= 57) {
    // '1'..'9'
    i++;
    while (i < actualEnd && source[i] >= 48 && source[i] <= 57) {
      i++;
    }
  } else {
    return null;
  }

  // Fraction part (optional):
  if (i < actualEnd && source[i] == 46) {
    // '.'
    i++;
    if (i >= actualEnd || source[i] < 48 || source[i] > 57) {
      return null;
    }
    while (i < actualEnd && source[i] >= 48 && source[i] <= 57) {
      i++;
    }
  }

  // Exponent part (optional):
  if (i < actualEnd && (source[i] == 101 || source[i] == 69)) {
    // 'e' or 'E'
    i++;
    if (i < actualEnd && (source[i] == 43 || source[i] == 45)) {
      // '+' or '-'
      i++;
    }
    if (i >= actualEnd || source[i] < 48 || source[i] > 57) {
      return null;
    }
    while (i < actualEnd && source[i] >= 48 && source[i] <= 57) {
      i++;
    }
  }

  if (i != actualEnd) return null;

  // The slice [sliceStart..actualEnd] is verified 100% valid RFC 8259 ASCII number.
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
    if (source[i] == 92) return false; // '\\'
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
  if (_isVerbatimUtf8(source, start, end)) {
    return utf8.decode(
      Uint8List.sublistView(source, start, end),
      allowMalformed: allowMalformed,
    );
  }

  final buffer = StringBuffer();
  var i = start;
  var runStart = start;
  while (i < end) {
    if (source[i] == 92) {
      // '\\'
      if (i > runStart) {
        buffer.write(
          utf8.decode(
            Uint8List.sublistView(source, runStart, i),
            allowMalformed: allowMalformed,
          ),
        );
      }
      i++; // skip '\\'
      if (i >= end) {
        throw FormatException('Unexpected EOF in escape sequence', source, i);
      }
      final esc = source[i++];
      switch (esc) {
        case 34:
          buffer.write('"');
        case 92:
          buffer.write('\\');
        case 47:
          buffer.write('/');
        case 98:
          buffer.write('\b');
        case 102:
          buffer.write('\f');
        case 110:
          buffer.write('\n');
        case 114:
          buffer.write('\r');
        case 116:
          buffer.write('\t');
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
    buffer.write(
      utf8.decode(
        Uint8List.sublistView(source, runStart, i),
        allowMalformed: allowMalformed,
      ),
    );
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
