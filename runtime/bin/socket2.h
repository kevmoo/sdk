#ifndef RUNTIME_BIN_SOCKET2_H_
#define RUNTIME_BIN_SOCKET2_H_

#include "bin/builtin.h"
#include "bin/utils.h"

namespace dart {
namespace bin {

class Socket2 {
 public:
  static intptr_t CreateConnect(const char* host, intptr_t port);
  static void Close(intptr_t id);

 private:
  DISALLOW_ALLOCATION();
  DISALLOW_IMPLICIT_CONSTRUCTORS(Socket2);
};

}  // namespace bin
}  // namespace dart

#endif  // RUNTIME_BIN_SOCKET2_H_
