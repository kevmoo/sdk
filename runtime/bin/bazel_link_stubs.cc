// Bazel link-time stubs for symbols that GN normally provides via
// generated .S assemblies (gn type=action, see runtime/bin/BUILD.gn:
// core_snapshot_data_linkable, core_snapshot_text_linkable,
// kernel_service_dill_linkable, platform_dill_linkable, dart_icudata).
//
// Until the M5 genrules embed real snapshot/dill/icu blobs, this file
// supplies empty placeholders so cc_binary //runtime/bin:dartvm LINKS.
// The resulting binary will not have functional snapshot data, kernel
// service, platform dill, or icu data — invocations that depend on
// any of these will fail at runtime. The point of this stub is the
// M5 Path-1 link milestone, not a runnable VM.

#include <cstdint>

#include "platform/globals.h"

// In C++, top-level `const` has internal linkage by default. `extern` is
// needed to give these array stubs external linkage so downstream
// translation units that declare them via `extern const uint8_t kFoo[]`
// (see runtime/bin/{main_impl.cc,dfe.cc,icu.cc}) resolve at link time.
extern "C" {

extern const uint8_t kDartCoreSnapshotData[];
extern const uint8_t kDartCoreSnapshotText[];

const uint8_t kDartCoreSnapshotData[1] = {0};
const uint8_t kDartCoreSnapshotText[1] = {0};

// kIcuData, kKernelServiceDill, kPlatformDill are now provided by real
// genrule outputs; see runtime/bin/BUILD.bazel
// :icudtl_linkable, :kernel_service_dill_linkable, :platform_dill_linkable.

}  // extern "C"
