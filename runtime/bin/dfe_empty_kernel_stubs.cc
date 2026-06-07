// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// This file is linked into the Dart VM binary when the Compiler Frontend (CFE)
// and Kernel platform are excluded from the build (e.g., in some AOT or
// minimal runtime configurations).
//
// It provides empty/stub definitions for the Dill symbol blobs to satisfy the
// linker, matching the types declared in dfe.cc exactly to avoid type-mismatch
// hazards.

#include <stdint.h>

extern "C" {
// Define as arrays of size 1 to match the "extern const uint8_t kFoo[]"
// declarations in dfe.cc. We must explicitly use the "extern" keyword here
// to give these const definitions external linkage (otherwise they default to
// internal linkage and are not visible to the linker, triggering unused
// variable compiler warnings).
extern const uint8_t kKernelServiceDill[1] = {0};
intptr_t kKernelServiceDillSize = 0;
extern const uint8_t kPlatformDill[1] = {0};
intptr_t kPlatformDillSize = 0;
}
