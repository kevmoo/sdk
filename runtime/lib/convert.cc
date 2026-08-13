// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/bootstrap_natives.h"
#include "vm/double_conversion.h"
#include "vm/exceptions.h"
#include "vm/native_entry.h"
#include "vm/object.h"
#include "vm/symbols.h"
#include <string.h>

namespace dart {

DEFINE_NATIVE_ENTRY(JsonUtf8Decoder_parseDouble, 0, 3) {
  GET_NON_NULL_NATIVE_ARGUMENT(TypedData, bytes, arguments->NativeArgAt(0));
  GET_NON_NULL_NATIVE_ARGUMENT(Smi, startValue, arguments->NativeArgAt(1));
  GET_NON_NULL_NATIVE_ARGUMENT(Smi, endValue, arguments->NativeArgAt(2));

  intptr_t start = startValue.Value();
  intptr_t end = endValue.Value();

  if (0 <= start && start < end && end <= bytes.LengthInBytes()) {
    const uint8_t* payload =
        reinterpret_cast<const uint8_t*>(bytes.DataAddr(start));
    intptr_t len = end - start;

    // Skip leading ASCII whitespace.
    while (len > 0 && *payload <= 32) {
      payload++;
      len--;
    }
    // Skip trailing ASCII whitespace.
    while (len > 0 && payload[len - 1] <= 32) {
      len--;
    }
    if (len == 0) {
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
  GET_NON_NULL_NATIVE_ARGUMENT(TypedData, buffer, arguments->NativeArgAt(1));
  GET_NON_NULL_NATIVE_ARGUMENT(Smi, offset_obj, arguments->NativeArgAt(2));

  double value = value_obj.value();
  intptr_t offset = offset_obj.Value();

  char char_buffer[128];
  DoubleToCString(value, char_buffer, sizeof(char_buffer));
  intptr_t len = strlen(char_buffer);

  if (offset >= 0 && offset + len <= buffer.LengthInBytes()) {
    uint8_t* dest = reinterpret_cast<uint8_t*>(buffer.DataAddr(offset));
    memmove(dest, char_buffer, len);
    return Smi::New(len);
  }
  return Smi::New(0);
}

DEFINE_NATIVE_ENTRY(JsonUtf8Encoder_writeStringToBuffer, 0, 3) {
  GET_NON_NULL_NATIVE_ARGUMENT(String, value_str, arguments->NativeArgAt(0));
  GET_NON_NULL_NATIVE_ARGUMENT(TypedData, buffer, arguments->NativeArgAt(1));
  GET_NON_NULL_NATIVE_ARGUMENT(Smi, offset_obj, arguments->NativeArgAt(2));

  intptr_t offset = offset_obj.Value();
  intptr_t buf_len = buffer.LengthInBytes();
  if (offset < 0 || offset >= buf_len) {
    return Smi::New(0);
  }

  uint8_t* dest = reinterpret_cast<uint8_t*>(buffer.DataAddr(offset));
  intptr_t max_write = buf_len - offset;
  intptr_t cursor = 0;

  auto write_byte = [&](uint8_t b) -> bool {
    if (cursor < max_write) {
      dest[cursor++] = b;
      return true;
    }
    return false;
  };

  if (!write_byte('"')) return Smi::New(0);

  intptr_t str_len = value_str.Length();
  for (intptr_t i = 0; i < str_len; i++) {
    int32_t c = value_str.CharAt(i);
    switch (c) {
      case '"':
        if (!write_byte('\\') || !write_byte('"')) return Smi::New(0);
        break;
      case '\\':
        if (!write_byte('\\') || !write_byte('\\')) return Smi::New(0);
        break;
      case '\b':
        if (!write_byte('\\') || !write_byte('b')) return Smi::New(0);
        break;
      case '\f':
        if (!write_byte('\\') || !write_byte('f')) return Smi::New(0);
        break;
      case '\n':
        if (!write_byte('\\') || !write_byte('n')) return Smi::New(0);
        break;
      case '\r':
        if (!write_byte('\\') || !write_byte('r')) return Smi::New(0);
        break;
      case '\t':
        if (!write_byte('\\') || !write_byte('t')) return Smi::New(0);
        break;
      default:
        if (c < 0x20) {
          static const char hex_digits[] = "0123456789abcdef";
          if (!write_byte('\\') || !write_byte('u') || !write_byte('0') ||
              !write_byte('0') || !write_byte(hex_digits[(c >> 4) & 0xF]) ||
              !write_byte(hex_digits[c & 0xF])) {
            return Smi::New(0);
          }
        } else if (c <= 0x7F) {
          if (!write_byte(static_cast<uint8_t>(c))) return Smi::New(0);
        } else if (c <= 0x7FF) {
          if (!write_byte(static_cast<uint8_t>(0xC0 | (c >> 6))) ||
              !write_byte(static_cast<uint8_t>(0x80 | (c & 0x3F)))) {
            return Smi::New(0);
          }
        } else if (c >= 0xD800 && c <= 0xDBFF) {
          // Surrogate pair
          if (i + 1 < str_len) {
            int32_t c2 = value_str.CharAt(i + 1);
            if (c2 >= 0xDC00 && c2 <= 0xDFFF) {
              i++;
              int32_t code_point =
                  0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00);
              if (!write_byte(
                      static_cast<uint8_t>(0xF0 | (code_point >> 18))) ||
                  !write_byte(static_cast<uint8_t>(
                      0x80 | ((code_point >> 12) & 0x3F))) ||
                  !write_byte(static_cast<uint8_t>(
                      0x80 | ((code_point >> 6) & 0x3F))) ||
                  !write_byte(static_cast<uint8_t>(0x80 | (code_point & 0x3F)))) {
                return Smi::New(0);
              }
              break;
            }
          }
          // Unpaired surrogate -> replacement char U+FFFD (0xEF, 0xBF, 0xBD)
          if (!write_byte(0xEF) || !write_byte(0xBF) || !write_byte(0xBD)) {
            return Smi::New(0);
          }
        } else {
          // 3-byte UTF-8
          if (!write_byte(static_cast<uint8_t>(0xE0 | (c >> 12))) ||
              !write_byte(static_cast<uint8_t>(0x80 | ((c >> 6) & 0x3F))) ||
              !write_byte(static_cast<uint8_t>(0x80 | (c & 0x3F)))) {
            return Smi::New(0);
          }
        }
        break;
    }
  }

  if (!write_byte('"')) return Smi::New(0);

  return Smi::New(cursor);
}

}  // namespace dart
