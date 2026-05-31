"""Bazel C++ toolchain config for the in-tree clang at buildtools/linux-x64.

Mirrors the GN `clang_x64` suite in build/toolchain/linux/BUILD.gn. Per-target
compile / link flags are NOT defined here — they ride in via cc_library.copts
produced by the gn-desc-driven translator (M2/M3). M1 scope is just tool paths
plus Bazel's legacy feature set, which auto-supplies depfile + standard
compile/link flag plumbing.
"""

load("@bazel_tools//tools/build_defs/cc:action_names.bzl", "ACTION_NAMES")
load(
    "@bazel_tools//tools/cpp:cc_toolchain_config_lib.bzl",
    "feature",
    "flag_group",
    "flag_set",
    "tool_path",
)
load("@dart_linux_x64_clang//:paths.bzl", "CLANG_BIN")
load("@rules_cc//cc/common:cc_common.bzl", "cc_common")

# Absolute paths emitted by the @dart_linux_x64_clang repo rule at fetch
# time (see build/toolchain/linux/clang_repo.bzl). tool_paths must be
# forward-only (no `..`) when relative; absolute paths are accepted.
_CLANG_BIN = CLANG_BIN

def _impl(ctx):
    cpu = ctx.attr.cpu
    triple = ctx.attr.target_triple

    tool_paths = [
        # Use clang++ as the "gcc" driver so cc_binary links auto-pull
        # libc++/libm (libstdc++ implicit deps); clang++ still compiles
        # .c files as C based on extension.
        tool_path(name = "gcc", path = _CLANG_BIN + "/clang++"),
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

    # The "gcc" tool_path above is clang++. clang++ as the driver on a
    # .c file otherwise (a) errors with `-Werror,-Wdeprecated` ("treating
    # 'c' input as 'c++' when in C++ mode") and (b) applies C++ semantics
    # (e.g., rejects C-only `register`). Pass `-x c` for the C compile
    # action so the driver treats the input as C.
    force_c_language = feature(
        name = "dart_force_c_language",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [ACTION_NAMES.c_compile],
                flag_groups = [flag_group(flags = ["-x", "c"])],
            ),
        ],
    )

    # Target architecture specific flags (triple, ISA, sysroot)
    target_flags = ["--sysroot=buildtools/sysroot/linux"]
    target_linkopts = ["--sysroot=buildtools/sysroot/linux"]

    if cpu == "aarch64":
        target_flags.append("--target=" + triple)
        target_linkopts.extend([
            "--target=" + triple,
            "-Wl,--fix-cortex-a53-843419",
        ])
    else:
        target_flags.extend([
            "--target=" + triple,
            "-march=x86-64",
            "-m64",
            "-msse2",
        ])
        target_linkopts.extend([
            "--target=" + triple,
            "-m64",
        ])

    target_arch_feature = feature(
        name = "dart_target_arch_flags",
        enabled = True,
        flag_sets = [
            flag_set(
                actions = [
                    ACTION_NAMES.c_compile,
                    ACTION_NAMES.cpp_compile,
                    ACTION_NAMES.cpp_header_parsing,
                    ACTION_NAMES.cpp_module_compile,
                    ACTION_NAMES.cpp_module_codegen,
                    ACTION_NAMES.assemble,
                    ACTION_NAMES.preprocess_assemble,
                ],
                flag_groups = [flag_group(flags = target_flags)],
            ),
            flag_set(
                actions = [
                    ACTION_NAMES.cpp_link_executable,
                    ACTION_NAMES.cpp_link_dynamic_library,
                    ACTION_NAMES.cpp_link_nodeps_dynamic_library,
                ],
                flag_groups = [flag_group(flags = target_linkopts)],
            ),
        ],
    )

    # System include roots Bazel treats as toolchain-builtin (suppresses
    # the "absolute path inclusion(s) found" error from strict-includes).
    clang_root = CLANG_BIN.rstrip("/").rsplit("/", 1)[0]
    return cc_common.create_cc_toolchain_config_info(
        ctx = ctx,
        toolchain_identifier = "clang_" + cpu,
        host_system_name = "x86_64-linux-gnu",
        target_system_name = triple,
        target_cpu = cpu,
        target_libc = "glibc",
        compiler = "clang",
        abi_version = "unknown",
        abi_libc_version = "unknown",
        tool_paths = tool_paths,
        builtin_sysroot = "buildtools/sysroot/linux",
        features = [force_c_language, target_arch_feature],
        cxx_builtin_include_directories = [
            "/usr/include",
            "/usr/local/include",
            clang_root + "/include",
            clang_root + "/lib/clang",
            "%sysroot%/usr/include",
            "%sysroot%/usr/include/aarch64-linux-gnu",
            "%sysroot%/usr/include/x86_64-linux-gnu",
        ],
    )

cc_toolchain_config = rule(
    implementation = _impl,
    attrs = {
        "cpu": attr.string(mandatory = True),
        "target_triple": attr.string(mandatory = True),
    },
)
