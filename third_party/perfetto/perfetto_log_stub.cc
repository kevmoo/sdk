// Minimal stub for perfetto::base::LogMessage so libprotozero links without
// pulling in Perfetto's full src/base (crash_keys, log_ring_buffer, time,
// string_utils). PERFETTO_CHECK/PERFETTO_FATAL still trap via __builtin_trap;
// only the user-facing log text is dropped.

#include <cstdarg>
#include <cstdio>

#include "perfetto/base/logging.h"

namespace perfetto {
namespace base {

void LogMessage(LogLev /*level*/,
                const char* file,
                int line,
                const char* fmt,
                ...) {
  std::fprintf(stderr, "[perfetto %s:%d] ", file, line);
  std::va_list args;
  va_start(args, fmt);
  std::vfprintf(stderr, fmt, args);
  va_end(args);
  std::fputc('\n', stderr);
}

}  // namespace base
}  // namespace perfetto
