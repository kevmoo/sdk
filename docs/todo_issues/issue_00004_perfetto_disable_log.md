# Issue 00004: Set PERFETTO_DISABLE_LOG for Dart's protozero-only perfetto use

## Problem

Dart vendors and uses only Perfetto's protozero serialization library — not
its tracing/logging stack. But protozero's `.cc` sources call
`PERFETTO_DLOG`/`PERFETTO_CHECK`/`PERFETTO_FATAL`, which all expand to a
`perfetto::base::LogMessage(...)` call unless the
`PERFETTO_DISABLE_LOG` macro is defined at compile time.

Dart's GN does not define this macro. Concretely, in
`third_party/perfetto/src/include/perfetto/base/logging.h`:

```cpp
#if defined(PERFETTO_ANDROID_ASYNC_SAFE_LOG)
  #define PERFETTO_XLOG(level, fmt, ...) async_safe_format_log(...)
#elif defined(PERFETTO_DISABLE_LOG)
  #define PERFETTO_XLOG(level, fmt, ...) \
      ::perfetto::base::ignore_result(level, fmt, ##__VA_ARGS__)
#else
  #define PERFETTO_XLOG(level, fmt, ...) \
      ::perfetto::base::LogMessage(level, ...)
#endif
```

Today's build doesn't notice the resulting `LogMessage` symbol reference
because:

- protozero `.cc` files reference `LogMessage` only inside `PERFETTO_CHECK`
  branches that aren't exercised on Dart's link path, and
- The static linker tolerates the unresolved-but-untouched symbol in this
  specific configuration (archive-with-no-callsite-in-live-section).

Both conditions are accidents of the current build. Either could break with
a perfetto roll, a different optimizer, or a tighter linker mode.

## Why this is an improvement on its own

- Eliminates dead code paths: logging-machinery code that can never be reached
  is removed from the build product.
- Smaller compiled output for `libprotozero` and its dependents.
- Declares intent explicitly: "Dart uses Perfetto for serialization only, not
  tracing." Today's behavior is a hidden assumption; the define makes it a
  contract.
- Removes fragility — a Perfetto upstream change to how `PERFETTO_CHECK`
  expands, or a Dart change to link configuration, won't silently produce
  unresolved symbols.

## How it makes Bazel (and any other non-GN build) easier

Without the define, any non-GN build of the same source set has to either:

- Pull in Perfetto's full `src/base/` tree (logging.cc + crash_keys.cc +
  log_ring_buffer.cc + time.cc + string_utils.cc + transitive deps), or
- Supply a stub `perfetto::base::LogMessage` function

Dart's Bazel migration chose the stub. Setting `PERFETTO_DISABLE_LOG` removes
the need for either workaround, in any build system.

## Proposed change

In `third_party/perfetto/BUILD.gn`'s `libprotozero_config`:

```gn
defines = [ "PERFETTO_DISABLE_LOG" ]
```

## Affected code

- `third_party/perfetto/BUILD.gn` — `libprotozero_config` defines
- `third_party/perfetto/src/include/perfetto/base/logging.h:150–157` — the
  `#elif defined(PERFETTO_DISABLE_LOG)` branch this enables

## Notes

Discovered during the Bazel migration when `libprotozero` failed to link
without a `perfetto::base::LogMessage` symbol. The Bazel-side workaround
(`third_party/perfetto/perfetto_log_stub.cc`) provides a no-op stub. The
structural fix is to enable the upstream-supported no-log mode.
