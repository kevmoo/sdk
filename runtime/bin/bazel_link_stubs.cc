// Bazel link-time stubs.
//
// All M5 Path-1 placeholder symbols have now been replaced by real blobs
// produced via runtime/bin/BUILD.bazel genrules:
//   - kIcuData              -> :icudtl_linkable
//   - kKernelServiceDill    -> :kernel_service_dill_linkable
//   - kPlatformDill         -> :platform_dill_linkable
//   - kDartCoreSnapshotData -> :core_snapshot_data_linkable
//   - kDartCoreSnapshotText -> :core_snapshot_text_linkable
//
// This TU is intentionally empty. It is retained (rather than the
// cc_library deleted) only because runtime/bin/BUILD.bazel still has a
// :bazel_link_stubs cc_library target; once that target has no callers
// the file and the cc_library can be removed together.
