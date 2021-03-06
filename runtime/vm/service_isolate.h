// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#ifndef VM_SERVICE_ISOLATE_H_
#define VM_SERVICE_ISOLATE_H_

#include "include/dart_api.h"

#include "vm/allocation.h"
#include "vm/os_thread.h"

namespace dart {

class ServiceIsolate : public AllStatic {
 public:
  static const char* kName;
  static bool NameEquals(const char* name);

  static bool Exists();
  static bool IsRunning();
  static bool IsServiceIsolate(Isolate* isolate);
  static bool IsServiceIsolateDescendant(Isolate* isolate);
  static Dart_Port Port();

  static Dart_Port WaitForLoadPort();
  static Dart_Port LoadPort();

  static void Run();
  static bool SendIsolateStartupMessage();
  static bool SendIsolateShutdownMessage();
  static void SendServiceExitMessage();
  static void Shutdown();

 private:
  static void KillServiceIsolate();

 protected:
  static void SetServicePort(Dart_Port port);
  static void SetServiceIsolate(Isolate* isolate);
  static void SetLoadPort(Dart_Port port);
  static void ConstructExitMessageAndCache(Isolate* isolate);
  static void FinishedExiting();
  static void FinishedInitializing();
  static void MaybeInjectVMServiceLibrary(Isolate* isolate);
  static Dart_IsolateCreateCallback create_callback() {
    return create_callback_;
  }

  static Dart_Handle GetSource(const char* name);
  static Dart_Handle LibraryTagHandler(Dart_LibraryTag tag, Dart_Handle library,
                                       Dart_Handle url);

  static Dart_IsolateCreateCallback create_callback_;
  static uint8_t* exit_message_;
  static intptr_t exit_message_length_;
  static Monitor* monitor_;
  static bool initializing_;
  static bool shutting_down_;
  static Isolate* isolate_;
  static Dart_Port port_;
  static Dart_Port load_port_;
  static Dart_Port origin_;

  friend class Dart;
  friend class RunServiceTask;
  friend class ServiceIsolateNatives;
};

}  // namespace dart

#endif  // VM_SERVICE_ISOLATE_H_
