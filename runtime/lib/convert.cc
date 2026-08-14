// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/bootstrap_natives.h"
#include "vm/double_conversion.h"
#include "vm/exceptions.h"
#include "vm/native_entry.h"
#include "vm/object.h"
#include "vm/symbols.h"
#include <cmath>
#include <string.h>

#if defined(__x86_64__) || defined(_M_X64)
#include <emmintrin.h>
#elif defined(__aarch64__) || defined(_M_ARM64)
#include <arm_neon.h>
#endif

// TODO(kevmoo): Architectural Opportunity (Horizon / Extreme-Scale Streaming):
// Implement a native C++ compact 64-bit structural delimiter tape parser
// (simdjson Stage 1 style) for JsonTokenReader. This records 64-bit offsets of
// structural characters ('{', '}', '[', ']', '"', ':', ',') in a single vectorized
// SIMD pass over the raw Uint8List buffer, allowing streaming consumers to parse
// multi-megabyte payloads with minimal RAM overhead (~15MB vs >62MB) and zero
// per-token VM FFI transition overhead.

namespace dart {

static inline bool IsJsonWhitespace(uint8_t c) {
  return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D;
}

static bool IsValidJsonNumber(const uint8_t* str, intptr_t len) {
  if (len == 0) return false;
  intptr_t i = 0;
  if (str[i] == '-') {
    i++;
    if (i == len) return false;
  }
  // Integer part
  if (str[i] == '0') {
    i++;
    // A leading zero cannot be followed by another digit
    if (i < len && str[i] >= '0' && str[i] <= '9') {
      return false;
    }
  } else if (str[i] >= '1' && str[i] <= '9') {
    i++;
    while (i < len && str[i] >= '0' && str[i] <= '9') {
      i++;
    }
  } else {
    return false;
  }
  // Fraction part
  if (i < len && str[i] == '.') {
    i++;
    if (i == len || str[i] < '0' || str[i] > '9') {
      return false;
    }
    while (i < len && str[i] >= '0' && str[i] <= '9') {
      i++;
    }
  }
  // Exponent part
  if (i < len && (str[i] == 'e' || str[i] == 'E')) {
    i++;
    if (i < len && (str[i] == '+' || str[i] == '-')) {
      i++;
    }
    if (i == len || str[i] < '0' || str[i] > '9') {
      return false;
    }
    while (i < len && str[i] >= '0' && str[i] <= '9') {
      i++;
    }
  }
  return i == len;
}

DEFINE_NATIVE_ENTRY(JsonUtf8Decoder_parseDouble, 0, 3) {
  GET_NON_NULL_NATIVE_ARGUMENT(TypedDataBase, bytes, arguments->NativeArgAt(0));
  GET_NON_NULL_NATIVE_ARGUMENT(Smi, startValue, arguments->NativeArgAt(1));
  GET_NON_NULL_NATIVE_ARGUMENT(Smi, endValue, arguments->NativeArgAt(2));

  intptr_t start = startValue.Value();
  intptr_t end = endValue.Value();

  if (0 <= start && start < end && end <= bytes.LengthInBytes()) {
    const uint8_t* payload =
        reinterpret_cast<const uint8_t*>(bytes.DataAddr(start));
    intptr_t len = end - start;

    // Skip leading JSON whitespace.
    while (len > 0 && IsJsonWhitespace(*payload)) {
      payload++;
      len--;
    }
    // Skip trailing JSON whitespace.
    while (len > 0 && IsJsonWhitespace(payload[len - 1])) {
      len--;
    }
    if (len == 0 || !IsValidJsonNumber(payload, len)) {
      return Object::null();
    }

    double double_value = 0.0;
    if (CStringToDouble(reinterpret_cast<const char*>(payload), len,
                        &double_value)) {
      return Double::New(double_value);
    }
  }
  return Object::null();
}

DEFINE_NATIVE_ENTRY(JsonUtf8Encoder_writeDoubleToBuffer, 0, 3) {
  GET_NON_NULL_NATIVE_ARGUMENT(Double, value_obj, arguments->NativeArgAt(0));
  GET_NON_NULL_NATIVE_ARGUMENT(TypedDataBase, buffer, arguments->NativeArgAt(1));
  GET_NON_NULL_NATIVE_ARGUMENT(Smi, offset_obj, arguments->NativeArgAt(2));

  double value = value_obj.value();
  if (!std::isfinite(value)) {
    Exceptions::ThrowArgumentError(value_obj);
  }
  intptr_t offset = offset_obj.Value();
  intptr_t buf_len = buffer.LengthInBytes();

  char char_buffer[128];
  DoubleToCString(value, char_buffer, sizeof(char_buffer));
  intptr_t len = strlen(char_buffer);

  if (offset < 0 || buf_len < len || offset > buf_len - len) {
    Exceptions::ThrowRangeError("offset", offset_obj, 0,
                                buf_len >= len ? buf_len - len : 0);
  }

  uint8_t* dest = reinterpret_cast<uint8_t*>(buffer.DataAddr(offset));
  memmove(dest, char_buffer, len);
  return Smi::New(len);
}

DEFINE_NATIVE_ENTRY(JsonUtf8Encoder_writeStringToBuffer, 0, 3) {
  GET_NON_NULL_NATIVE_ARGUMENT(String, value_str, arguments->NativeArgAt(0));
  GET_NON_NULL_NATIVE_ARGUMENT(TypedDataBase, buffer, arguments->NativeArgAt(1));
  GET_NON_NULL_NATIVE_ARGUMENT(Smi, offset_obj, arguments->NativeArgAt(2));

  intptr_t offset = offset_obj.Value();
  intptr_t buf_len = buffer.LengthInBytes();
  if (offset < 0 || offset > buf_len) {
    Exceptions::ThrowRangeError("offset", offset_obj, 0, buf_len);
  }

  intptr_t str_len = value_str.Length();

  // Fast path for OneByteString
  if (value_str.IsOneByteString()) {
    const uint8_t* src = OneByteString::DataStart(value_str);

    // Vectorized 16/32-byte SIMD scan for characters needing escapes (< 0x20, '"', '\\', >= 0x80)
    intptr_t i = 0;
#if defined(__x86_64__) || defined(_M_X64)
    const __m128i v_0x20 = _mm_set1_epi8(0x20);
    const __m128i v_quote = _mm_set1_epi8('"');
    const __m128i v_slash = _mm_set1_epi8('\\');

    // 32-byte unrolled loop (2x 16-byte SSE2 vectors)
    while (i + 32 <= str_len) {
      __m128i c0 = _mm_loadu_si128(reinterpret_cast<const __m128i*>(src + i));
      __m128i c1 = _mm_loadu_si128(reinterpret_cast<const __m128i*>(src + i + 16));

      // _mm_cmplt_epi8 treats signed 8-bit ints:
      // chars in [0x00, 0x1F] are signed 0..31 (< 32 = 0x20)
      // chars in [0x80, 0xFF] are signed -128..-1 (< 32 = 0x20)
      // So this detects both control characters (< 0x20) AND non-ASCII bytes (>= 0x80)!
      __m128i ctrl_or_high0 = _mm_cmplt_epi8(c0, v_0x20);
      __m128i ctrl_or_high1 = _mm_cmplt_epi8(c1, v_0x20);

      __m128i quote0 = _mm_cmpeq_epi8(c0, v_quote);
      __m128i quote1 = _mm_cmpeq_epi8(c1, v_quote);

      __m128i slash0 = _mm_cmpeq_epi8(c0, v_slash);
      __m128i slash1 = _mm_cmpeq_epi8(c1, v_slash);

      __m128i escapes0 = _mm_or_si128(_mm_or_si128(ctrl_or_high0, quote0), slash0);
      __m128i escapes1 = _mm_or_si128(_mm_or_si128(ctrl_or_high1, quote1), slash1);

      __m128i any_escapes = _mm_or_si128(escapes0, escapes1);
      if (_mm_movemask_epi8(any_escapes) != 0) {
        break;
      }
      i += 32;
    }
    while (i + 16 <= str_len) {
      __m128i c0 = _mm_loadu_si128(reinterpret_cast<const __m128i*>(src + i));
      __m128i ctrl_or_high0 = _mm_cmplt_epi8(c0, v_0x20);
      __m128i quote0 = _mm_cmpeq_epi8(c0, v_quote);
      __m128i slash0 = _mm_cmpeq_epi8(c0, v_slash);
      __m128i escapes0 = _mm_or_si128(_mm_or_si128(ctrl_or_high0, quote0), slash0);
      if (_mm_movemask_epi8(escapes0) != 0) {
        break;
      }
      i += 16;
    }
#elif defined(__aarch64__) || defined(_M_ARM64)
    const uint8x16_t v_0x20 = vdupq_n_u8(0x20);
    const uint8x16_t v_0x80 = vdupq_n_u8(0x80);
    const uint8x16_t v_quote = vdupq_n_u8('"');
    const uint8x16_t v_slash = vdupq_n_u8('\\');

    // 32-byte unrolled loop (2x 16-byte NEON vectors)
    while (i + 32 <= str_len) {
      uint8x16_t chunk0 = vld1q_u8(src + i);
      uint8x16_t chunk1 = vld1q_u8(src + i + 16);
      uint8x16_t is_ctrl0 = vcltq_u8(chunk0, v_0x20);
      uint8x16_t is_ctrl1 = vcltq_u8(chunk1, v_0x20);
      uint8x16_t is_high0 = vcgeq_u8(chunk0, v_0x80);
      uint8x16_t is_high1 = vcgeq_u8(chunk1, v_0x80);
      uint8x16_t is_quote0 = vceqq_u8(chunk0, v_quote);
      uint8x16_t is_quote1 = vceqq_u8(chunk1, v_quote);
      uint8x16_t is_slash0 = vceqq_u8(chunk0, v_slash);
      uint8x16_t is_slash1 = vceqq_u8(chunk1, v_slash);
      uint8x16_t escapes0 =
          vorrq_u8(vorrq_u8(is_ctrl0, is_high0), vorrq_u8(is_quote0, is_slash0));
      uint8x16_t escapes1 =
          vorrq_u8(vorrq_u8(is_ctrl1, is_high1), vorrq_u8(is_quote1, is_slash1));
      uint8x16_t any = vorrq_u8(escapes0, escapes1);
      uint64x2_t mask64 = vreinterpretq_u64_u8(any);
      if ((vgetq_lane_u64(mask64, 0) | vgetq_lane_u64(mask64, 1)) != 0) {
        break;
      }
      i += 32;
    }
    while (i + 16 <= str_len) {
      uint8x16_t chunk = vld1q_u8(src + i);
      uint8x16_t is_ctrl = vcltq_u8(chunk, v_0x20);
      uint8x16_t is_high = vcgeq_u8(chunk, v_0x80);
      uint8x16_t is_quote = vceqq_u8(chunk, v_quote);
      uint8x16_t is_slash = vceqq_u8(chunk, v_slash);
      uint8x16_t escapes =
          vorrq_u8(vorrq_u8(is_ctrl, is_high), vorrq_u8(is_quote, is_slash));
      uint64x2_t mask64 = vreinterpretq_u64_u8(escapes);
      if ((vgetq_lane_u64(mask64, 0) | vgetq_lane_u64(mask64, 1)) != 0) {
        break;
      }
      i += 16;
    }
#else
    while (i + 8 <= str_len) {
      uint64_t chunk;
      memcpy(&chunk, src + i, sizeof(chunk));
      uint64_t has_high = chunk & 0x8080808080808080ULL;
      uint64_t sub_20 = chunk - 0x2020202020202020ULL;
      uint64_t has_ctrl = sub_20 & ~chunk & 0x8080808080808080ULL;
      uint64_t xor_quote = chunk ^ 0x2222222222222222ULL;
      uint64_t has_quote =
          (xor_quote - 0x0101010101010101ULL) & ~xor_quote & 0x8080808080808080ULL;
      uint64_t xor_slash = chunk ^ 0x5C5C5C5C5C5C5C5CULL;
      uint64_t has_slash =
          (xor_slash - 0x0101010101010101ULL) & ~xor_slash & 0x8080808080808080ULL;

      if ((has_high | has_ctrl | has_quote | has_slash) != 0) {
        break;
      }
      i += 8;
    }
#endif
    while (i < str_len) {
      uint8_t c = src[i];
      if (c < 0x20 || c == '"' || c == '\\' || c >= 0x80) {
        break;
      }
      i++;
    }

    if (i == str_len) {
      // Pure ASCII string without any escapes needed!
      // Output is: '"' + src + '"'
      intptr_t required_len = str_len + 2;
      if (buf_len < required_len || offset > buf_len - required_len) {
        Exceptions::ThrowRangeError("offset", offset_obj, 0,
                                    buf_len >= required_len ? buf_len - required_len : 0);
      }
      uint8_t* dest = reinterpret_cast<uint8_t*>(buffer.DataAddr(offset));
      dest[0] = '"';
      memmove(dest + 1, src, str_len);
      dest[str_len + 1] = '"';
      return Smi::New(required_len);
    }
    // OneByteString with escapes or Latin-1 characters: use direct pointer access src[j]
    intptr_t required_len = 2; // For opening and closing quotes
    for (intptr_t j = 0; j < str_len; j++) {
      uint8_t c = src[j];
      switch (c) {
        case '"':
        case '\\':
        case '\b':
        case '\f':
        case '\n':
        case '\r':
        case '\t':
          required_len += 2;
          break;
        default:
          if (c < 0x20) {
            required_len += 6; // \u00XX
          } else if (c <= 0x7F) {
            required_len += 1;
          } else {
            // Latin-1 byte in [0x80, 0xFF] encodes to 2 UTF-8 bytes (0xC0..0xC3, 0x80..0xBF)
            required_len += 2;
          }
          break;
      }
    }

    if (buf_len < required_len || offset > buf_len - required_len) {
      Exceptions::ThrowRangeError("offset", offset_obj, 0,
                                  buf_len >= required_len ? buf_len - required_len : 0);
    }

    uint8_t* dest = reinterpret_cast<uint8_t*>(buffer.DataAddr(offset));
    intptr_t cursor = 0;
    static const char hex_digits[] = "0123456789abcdef";

    dest[cursor++] = '"';

    for (intptr_t j = 0; j < str_len; j++) {
      uint8_t c = src[j];
      switch (c) {
        case '"':
          dest[cursor++] = '\\';
          dest[cursor++] = '"';
          break;
        case '\\':
          dest[cursor++] = '\\';
          dest[cursor++] = '\\';
          break;
        case '\b':
          dest[cursor++] = '\\';
          dest[cursor++] = 'b';
          break;
        case '\f':
          dest[cursor++] = '\\';
          dest[cursor++] = 'f';
          break;
        case '\n':
          dest[cursor++] = '\\';
          dest[cursor++] = 'n';
          break;
        case '\r':
          dest[cursor++] = '\\';
          dest[cursor++] = 'r';
          break;
        case '\t':
          dest[cursor++] = '\\';
          dest[cursor++] = 't';
          break;
        default:
          if (c < 0x20) {
            dest[cursor++] = '\\';
            dest[cursor++] = 'u';
            dest[cursor++] = '0';
            dest[cursor++] = '0';
            dest[cursor++] = hex_digits[(c >> 4) & 0xF];
            dest[cursor++] = hex_digits[c & 0xF];
          } else if (c <= 0x7F) {
            dest[cursor++] = c;
          } else {
            dest[cursor++] = static_cast<uint8_t>(0xC0 | (c >> 6));
            dest[cursor++] = static_cast<uint8_t>(0x80 | (c & 0x3F));
          }
          break;
      }
    }

    dest[cursor++] = '"';
    return Smi::New(cursor);
  }

  if (value_str.IsTwoByteString()) {
    const uint16_t* src = TwoByteString::DataStart(value_str);
    intptr_t required_len = 2; // For opening and closing quotes
    for (intptr_t i = 0; i < str_len; i++) {
      uint16_t c = src[i];
      switch (c) {
        case '"':
        case '\\':
        case '\b':
        case '\f':
        case '\n':
        case '\r':
        case '\t':
          required_len += 2;
          break;
        default:
          if (c < 0x20) {
            required_len += 6; // \u00XX
          } else if (c <= 0x7F) {
            required_len += 1;
          } else if (c <= 0x7FF) {
            required_len += 2;
          } else if (c >= 0xD800 && c <= 0xDBFF) {
            if (i + 1 < str_len) {
              uint16_t c2 = src[i + 1];
              if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
                i++;
                required_len += 4;
                break;
              }
            }
            // Isolated high surrogate -> \uXXXX (6 bytes)
            required_len += 6;
          } else if (c >= 0xDC00 && c <= 0xDFFF) {
            // Isolated low surrogate -> \uXXXX (6 bytes)
            required_len += 6;
          } else {
            required_len += 3;
          }
          break;
      }
    }

    if (buf_len < required_len || offset > buf_len - required_len) {
      Exceptions::ThrowRangeError("offset", offset_obj, 0,
                                  buf_len >= required_len ? buf_len - required_len : 0);
    }

    uint8_t* dest = reinterpret_cast<uint8_t*>(buffer.DataAddr(offset));
    intptr_t cursor = 0;
    static const char hex_digits[] = "0123456789abcdef";

    dest[cursor++] = '"';

    for (intptr_t i = 0; i < str_len; i++) {
      uint16_t c = src[i];
      switch (c) {
        case '"':
          dest[cursor++] = '\\';
          dest[cursor++] = '"';
          break;
        case '\\':
          dest[cursor++] = '\\';
          dest[cursor++] = '\\';
          break;
        case '\b':
          dest[cursor++] = '\\';
          dest[cursor++] = 'b';
          break;
        case '\f':
          dest[cursor++] = '\\';
          dest[cursor++] = 'f';
          break;
        case '\n':
          dest[cursor++] = '\\';
          dest[cursor++] = 'n';
          break;
        case '\r':
          dest[cursor++] = '\\';
          dest[cursor++] = 'r';
          break;
        case '\t':
          dest[cursor++] = '\\';
          dest[cursor++] = 't';
          break;
        default:
          if (c < 0x20) {
            dest[cursor++] = '\\';
            dest[cursor++] = 'u';
            dest[cursor++] = '0';
            dest[cursor++] = '0';
            dest[cursor++] = hex_digits[(c >> 4) & 0xF];
            dest[cursor++] = hex_digits[c & 0xF];
          } else if (c <= 0x7F) {
            dest[cursor++] = static_cast<uint8_t>(c);
          } else if (c <= 0x7FF) {
            dest[cursor++] = static_cast<uint8_t>(0xC0 | (c >> 6));
            dest[cursor++] = static_cast<uint8_t>(0x80 | (c & 0x3F));
          } else if (c >= 0xD800 && c <= 0xDBFF) {
            // Surrogate pair
            if (i + 1 < str_len) {
              uint16_t c2 = src[i + 1];
              if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
                i++;
                int32_t code_point =
                    0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00);
                dest[cursor++] =
                    static_cast<uint8_t>(0xF0 | (code_point >> 18));
                dest[cursor++] =
                    static_cast<uint8_t>(0x80 | ((code_point >> 12) & 0x3F));
                dest[cursor++] =
                    static_cast<uint8_t>(0x80 | ((code_point >> 6) & 0x3F));
                dest[cursor++] =
                    static_cast<uint8_t>(0x80 | (code_point & 0x3F));
                break;
              }
            }
            // Isolated high surrogate -> \uXXXX (6 ASCII bytes)
            dest[cursor++] = '\\';
            dest[cursor++] = 'u';
            dest[cursor++] = hex_digits[(c >> 12) & 0xF];
            dest[cursor++] = hex_digits[(c >> 8) & 0xF];
            dest[cursor++] = hex_digits[(c >> 4) & 0xF];
            dest[cursor++] = hex_digits[c & 0xF];
          } else if (c >= 0xDC00 && c <= 0xDFFF) {
            // Isolated low surrogate -> \uXXXX (6 ASCII bytes)
            dest[cursor++] = '\\';
            dest[cursor++] = 'u';
            dest[cursor++] = hex_digits[(c >> 12) & 0xF];
            dest[cursor++] = hex_digits[(c >> 8) & 0xF];
            dest[cursor++] = hex_digits[(c >> 4) & 0xF];
            dest[cursor++] = hex_digits[c & 0xF];
          } else {
            // 3-byte UTF-8
            dest[cursor++] = static_cast<uint8_t>(0xE0 | (c >> 12));
            dest[cursor++] = static_cast<uint8_t>(0x80 | ((c >> 6) & 0x3F));
            dest[cursor++] = static_cast<uint8_t>(0x80 | (c & 0x3F));
          }
          break;
      }
    }

    dest[cursor++] = '"';
    return Smi::New(cursor);
  }

  // Precalculate exact required output length to avoid partial buffer corruption
  intptr_t required_len = 2; // For opening and closing quotes
  for (intptr_t i = 0; i < str_len; i++) {
    int32_t c = value_str.CharAt(i);
    switch (c) {
      case '"':
      case '\\':
      case '\b':
      case '\f':
      case '\n':
      case '\r':
      case '\t':
        required_len += 2;
        break;
      default:
        if (c < 0x20) {
          required_len += 6; // \u00XX
        } else if (c <= 0x7F) {
          required_len += 1;
        } else if (c <= 0x7FF) {
          required_len += 2;
        } else if (c >= 0xD800 && c <= 0xDBFF) {
          if (i + 1 < str_len) {
            int32_t c2 = value_str.CharAt(i + 1);
            if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
              i++;
              required_len += 4;
              break;
            }
          }
          // Isolated high surrogate -> \uXXXX (6 bytes)
          required_len += 6;
        } else if (c >= 0xDC00 && c <= 0xDFFF) {
          // Isolated low surrogate -> \uXXXX (6 bytes)
          required_len += 6;
        } else {
          required_len += 3;
        }
        break;
    }
  }

  if (buf_len < required_len || offset > buf_len - required_len) {
    Exceptions::ThrowRangeError("offset", offset_obj, 0,
                                buf_len >= required_len ? buf_len - required_len : 0);
  }

  uint8_t* dest = reinterpret_cast<uint8_t*>(buffer.DataAddr(offset));
  intptr_t cursor = 0;
  static const char hex_digits[] = "0123456789abcdef";

  dest[cursor++] = '"';

  for (intptr_t i = 0; i < str_len; i++) {
    int32_t c = value_str.CharAt(i);
    switch (c) {
      case '"':
        dest[cursor++] = '\\';
        dest[cursor++] = '"';
        break;
      case '\\':
        dest[cursor++] = '\\';
        dest[cursor++] = '\\';
        break;
      case '\b':
        dest[cursor++] = '\\';
        dest[cursor++] = 'b';
        break;
      case '\f':
        dest[cursor++] = '\\';
        dest[cursor++] = 'f';
        break;
      case '\n':
        dest[cursor++] = '\\';
        dest[cursor++] = 'n';
        break;
      case '\r':
        dest[cursor++] = '\\';
        dest[cursor++] = 'r';
        break;
      case '\t':
        dest[cursor++] = '\\';
        dest[cursor++] = 't';
        break;
      default:
        if (c < 0x20) {
          dest[cursor++] = '\\';
          dest[cursor++] = 'u';
          dest[cursor++] = '0';
          dest[cursor++] = '0';
          dest[cursor++] = hex_digits[(c >> 4) & 0xF];
          dest[cursor++] = hex_digits[c & 0xF];
        } else if (c <= 0x7F) {
          dest[cursor++] = static_cast<uint8_t>(c);
        } else if (c <= 0x7FF) {
          dest[cursor++] = static_cast<uint8_t>(0xC0 | (c >> 6));
          dest[cursor++] = static_cast<uint8_t>(0x80 | (c & 0x3F));
        } else if (c >= 0xD800 && c <= 0xDBFF) {
          // Surrogate pair
          if (i + 1 < str_len) {
            int32_t c2 = value_str.CharAt(i + 1);
            if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
              i++;
              int32_t code_point =
                  0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00);
              dest[cursor++] =
                  static_cast<uint8_t>(0xF0 | (code_point >> 18));
              dest[cursor++] =
                  static_cast<uint8_t>(0x80 | ((code_point >> 12) & 0x3F));
              dest[cursor++] =
                  static_cast<uint8_t>(0x80 | ((code_point >> 6) & 0x3F));
              dest[cursor++] =
                  static_cast<uint8_t>(0x80 | (code_point & 0x3F));
              break;
            }
          }
          // Isolated high surrogate -> \uXXXX (6 ASCII bytes)
          dest[cursor++] = '\\';
          dest[cursor++] = 'u';
          dest[cursor++] = hex_digits[(c >> 12) & 0xF];
          dest[cursor++] = hex_digits[(c >> 8) & 0xF];
          dest[cursor++] = hex_digits[(c >> 4) & 0xF];
          dest[cursor++] = hex_digits[c & 0xF];
        } else if (c >= 0xDC00 && c <= 0xDFFF) {
          // Isolated low surrogate -> \uXXXX (6 ASCII bytes)
          dest[cursor++] = '\\';
          dest[cursor++] = 'u';
          dest[cursor++] = hex_digits[(c >> 12) & 0xF];
          dest[cursor++] = hex_digits[(c >> 8) & 0xF];
          dest[cursor++] = hex_digits[(c >> 4) & 0xF];
          dest[cursor++] = hex_digits[c & 0xF];
        } else {
          // 3-byte UTF-8
          dest[cursor++] = static_cast<uint8_t>(0xE0 | (c >> 12));
          dest[cursor++] = static_cast<uint8_t>(0x80 | ((c >> 6) & 0x3F));
          dest[cursor++] = static_cast<uint8_t>(0x80 | (c & 0x3F));
        }
        break;
    }
  }

  dest[cursor++] = '"';
  return Smi::New(cursor);
}

}  // namespace dart
