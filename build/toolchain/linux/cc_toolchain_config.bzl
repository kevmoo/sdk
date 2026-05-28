"""Bazel C++ toolchain config for the in-tree clang at buildtools/linux-x64.

Mirrors the GN `clang_x64` suite in build/toolchain/linux/BUILD.gn. Per-target
compile / link flags are NOT defined here — they ride in via cc_library.copts
produced by the gn-desc-driven translator (M2/M3). M1 scope is just tool paths
plus Bazel's legacy feature set, which auto-supplies depfile + standard
compile/link flag plumbing.
"""

load("@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl", "tool_path")
load("@dart_linux_x64_clang//:paths.bzl", "CLANG_BIN")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")
load("@rules_cc//cc/common:cc_info.bzl", "CcInfo")  # noqa: F401 (sibling load)

# Absolute paths emitted by the @dart_linux_x64_clang repo rule at fetch
# time (see build/toolchain/linux/clang_repo.bzl). tool_paths must be
# forward-only (no `..`) when relative; absolute paths are accepted.
_CLANG_BIN = CLANG_BIN

def _impl(ctx):
    tool_paths = [
        tool_path(name = "gcc", path = _CLANG_BIN + "/clang"),
        tool_path(name = "ld", path = _CLANG_BIN + "/clang++"),
        tool_path(name = "ar", path = _CLANG_BIN + "/llvm-ar"),
        tool_path(name = "cpp", path = _CLANG_BIN + "/clang-cpp"),
        tool_path(name = "gcov", path = "/bin/false"),
        tool_path(name = "nm", path = _CLANG_BIN + "/llvm-nm"),
        tool_path(name = "objdump", path = _CLANG_BIN + "/llvm-objdump"),
        tool_path(name = "strip", path = _CLANG_BIN + "/llvm-strip"),
        tool_path(name = "dwp", path = "/bin/false"),
        tool_path(name = "llvm-cov", path = "/bin/false"),
        tool_path(name = "llvm-profdata", path = "/bin/false"),
    ]

    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "clang_x64",
        host_system_name = "x86_64-linux-gnu",
        target_system_name = "x86_64-linux-gnu",
        target_cpu = "x86_64",
        target_libc = "glibc",
        compiler = "clang",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        tool_paths = tool_paths,
    )

cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {},
)
