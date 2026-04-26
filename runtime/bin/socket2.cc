#include "bin/socket2.h"
#include "bin/socket.h"
#include "bin/dartutils.h"

namespace dart {
namespace bin {

// We use the existing Socket_CreateConnect for connecting,
// so Socket2_CreateConnect is not strictly necessary if we use Socket_CreateConnect.
// But we'll provide the new Read/Write methods here.

void FUNCTION_NAME(Socket2_ReadInto)(Dart_NativeArguments args) {
  Socket* socket = Socket::GetSocketIdNativeField(Dart_GetNativeArgument(args, 0));
  Dart_Handle buffer_obj = Dart_GetNativeArgument(args, 1);
  intptr_t offset = DartUtils::GetIntptrValue(Dart_GetNativeArgument(args, 2));
  intptr_t length = DartUtils::GetIntptrValue(Dart_GetNativeArgument(args, 3));

  Dart_TypedData_Type type;
  uint8_t* buffer = nullptr;
  intptr_t buffer_length = 0;
  Dart_Handle result =
      Dart_TypedDataAcquireData(buffer_obj, &type, reinterpret_cast<void**>(&buffer), &buffer_length);
  if (Dart_IsError(result)) {
    Dart_PropagateError(result);
  }

  ASSERT((offset + length) <= buffer_length);

  intptr_t bytes_read =
      SocketBase::Read(socket->fd(), buffer + offset, length, SocketBase::kAsync);

  Dart_TypedDataReleaseData(buffer_obj);

  if (bytes_read >= 0) {
    Dart_SetIntegerReturnValue(args, bytes_read);
  } else {
    Dart_SetIntegerReturnValue(args, -1);
  }
}

void FUNCTION_NAME(Socket2_WriteFrom)(Dart_NativeArguments args) {
  Socket* socket = Socket::GetSocketIdNativeField(Dart_GetNativeArgument(args, 0));
  Dart_Handle buffer_obj = Dart_GetNativeArgument(args, 1);
  intptr_t offset = DartUtils::GetIntptrValue(Dart_GetNativeArgument(args, 2));
  intptr_t length = DartUtils::GetIntptrValue(Dart_GetNativeArgument(args, 3));

  Dart_TypedData_Type type;
  uint8_t* buffer = nullptr;
  intptr_t buffer_length = 0;
  Dart_Handle result =
      Dart_TypedDataAcquireData(buffer_obj, &type, reinterpret_cast<void**>(&buffer), &buffer_length);
  if (Dart_IsError(result)) {
    Dart_PropagateError(result);
  }

  ASSERT((offset + length) <= buffer_length);

  intptr_t bytes_written =
      SocketBase::Write(socket->fd(), buffer + offset, length, SocketBase::kAsync);

  Dart_TypedDataReleaseData(buffer_obj);

  if (bytes_written >= 0) {
    Dart_SetIntegerReturnValue(args, bytes_written);
  } else {
    Dart_SetIntegerReturnValue(args, -1);
  }
}

void FUNCTION_NAME(Socket2_WriteList)(Dart_NativeArguments args) {
  Socket* socket = Socket::GetSocketIdNativeField(Dart_GetNativeArgument(args, 0));
  Dart_Handle list_obj = Dart_GetNativeArgument(args, 1);

  intptr_t list_length = 0;
  Dart_Handle length_result = Dart_ListLength(list_obj, &list_length);
  if (Dart_IsError(length_result)) {
    Dart_PropagateError(length_result);
  }

  intptr_t total_written = 0;
  for (intptr_t i = 0; i < list_length; i++) {
    Dart_Handle buffer_obj = Dart_ListGetAt(list_obj, i);
    if (Dart_IsError(buffer_obj)) {
      Dart_PropagateError(buffer_obj);
    }

    Dart_TypedData_Type type;
    uint8_t* buffer = nullptr;
    intptr_t buffer_length = 0;
    Dart_Handle result = Dart_TypedDataAcquireData(
        buffer_obj, &type, reinterpret_cast<void**>(&buffer), &buffer_length);
    if (Dart_IsError(result)) {
      Dart_PropagateError(result);
    }

    intptr_t bytes_written =
        SocketBase::Write(socket->fd(), buffer, buffer_length, SocketBase::kAsync);

    Dart_TypedDataReleaseData(buffer_obj);

    if (bytes_written < 0) {
      if (total_written == 0) {
        Dart_SetIntegerReturnValue(args, -1);
      } else {
        Dart_SetIntegerReturnValue(args, total_written);
      }
      return;
    }

    total_written += bytes_written;
    if (bytes_written < buffer_length) {
      Dart_SetIntegerReturnValue(args, total_written);
      return;
    }
  }

  Dart_SetIntegerReturnValue(args, total_written);
}

}  // namespace bin
}  // namespace dart
