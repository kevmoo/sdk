"""Custom rules wrapper to dynamically inject platform and architecture configuration flags.

Intercepts compiles and automatically injects target OS and target CPU defines and cflags,
enabling clean cross-compilation of targets across x86_64 and ARM64 (Apple Silicon/M-series).
"""

load("@rules_cc//cc:defs.bzl", _cc_binary = "cc_binary", _cc_library = "cc_library", _cc_shared_library = "cc_shared_library")

cc_shared_library = _cc_shared_library

def _filter_copts(copts, platform):
    if platform != "macos":
        return copts
    if type(copts) != "list":
        return copts
    cleaned = []
    for c in copts:
        # Strip Linux target cross-compilation flag
        if c.startswith("--target="):
            continue
        # Strip x86-specific flags on Mac (since host might be arm64/Apple Silicon)
        if c.startswith("-march=") or c.startswith("-msse") or c == "-mssse3" or c == "-msse4.1" or c == "-msse4.2" or c == "-mavx":
            continue
        # Strip PIE/PIC flags to let the host toolchain manage them
        if c == "-fPIE" or c == "-fpie" or c == "-fPIC" or c == "-fpic":
            continue
        cleaned.append(c)
    return cleaned

def _filter_linkopts(linkopts, platform):
    if platform != "macos":
        return linkopts
    if type(linkopts) != "list":
        return linkopts
    cleaned = []
    for l in linkopts:
        # Strip Linux-specific libs and linker options that fail or are redundant on macOS
        if l in ("-lrt", "-Wl,--gc-sections", "-lutil", "-ldl", "-lpthread", "-stdlib=libc++"):
            continue
        cleaned.append(l)
    return cleaned

def cc_library(name, defines = [], local_defines = [], copts = [], linkopts = [], **kwargs):
    # Automatically inject platform preprocessor defines (local to the target compile)
    custom_local_defines = local_defines + select({
        "@platforms//os:macos": ["DART_TARGET_OS_MACOS", "_DARWIN_C_SOURCE"],
        "@platforms//os:linux": ["DART_TARGET_OS_LINUX"],
        "//conditions:default": [],
    })

    # Check if the target has its own explicit target architecture defined
    has_target_arch = False
    if type(defines) == "list":
        for d in defines:
            if type(d) == "string" and d.startswith("TARGET_ARCH_"):
                has_target_arch = True
    if type(local_defines) == "list":
        for d in local_defines:
            if type(d) == "string" and d.startswith("TARGET_ARCH_"):
                has_target_arch = True

    if not has_target_arch:
        custom_local_defines = custom_local_defines + select({
            "@platforms//cpu:arm64": ["TARGET_ARCH_ARM64"],
            "@platforms//cpu:x86_64": ["TARGET_ARCH_X64"],
            "//conditions:default": [],
        })

    # Automatically inject platform-specific compiler options
    if type(copts) == "list":
        custom_copts = select({
            "@platforms//os:macos": _filter_copts(copts, "macos") + [
                "-mmacosx-version-min=14.0",
            ],
            "@platforms//os:linux": _filter_copts(copts, "linux") + [
                "-m64",
                "-march=x86-64",
                "-msse2",
                "--target=x86_64-linux-gnu",
            ],
            "//conditions:default": copts,
        })
    else:
        custom_copts = copts + select({
            "@platforms//os:macos": [
                "-mmacosx-version-min=14.0",
            ],
            "@platforms//os:linux": [
                "-m64",
                "-march=x86-64",
                "-msse2",
                "--target=x86_64-linux-gnu",
            ],
            "//conditions:default": [],
        })

    # Automatically inject platform-specific linker options
    if type(linkopts) == "list":
        custom_linkopts = select({
            "@platforms//os:macos": _filter_linkopts(linkopts, "macos"),
            "//conditions:default": linkopts,
        })
    else:
        custom_linkopts = linkopts

    _cc_library(
        name = name,
        defines = defines,
        local_defines = custom_local_defines,
        copts = custom_copts,
        linkopts = custom_linkopts,
        **kwargs
    )

def cc_binary(name, defines = [], local_defines = [], copts = [], linkopts = [], **kwargs):
    # Automatically inject platform preprocessor defines (local to the target compile)
    custom_local_defines = local_defines + select({
        "@platforms//os:macos": ["DART_TARGET_OS_MACOS", "_DARWIN_C_SOURCE"],
        "@platforms//os:linux": ["DART_TARGET_OS_LINUX"],
        "//conditions:default": [],
    })

    # Check if the target has its own explicit target architecture defined
    has_target_arch = False
    if type(defines) == "list":
        for d in defines:
            if type(d) == "string" and d.startswith("TARGET_ARCH_"):
                has_target_arch = True
    if type(local_defines) == "list":
        for d in local_defines:
            if type(d) == "string" and d.startswith("TARGET_ARCH_"):
                has_target_arch = True

    if not has_target_arch:
        custom_local_defines = custom_local_defines + select({
            "@platforms//cpu:arm64": ["TARGET_ARCH_ARM64"],
            "@platforms//cpu:x86_64": ["TARGET_ARCH_X64"],
            "//conditions:default": [],
        })

    # Automatically inject platform-specific compiler options
    if type(copts) == "list":
        custom_copts = select({
            "@platforms//os:macos": _filter_copts(copts, "macos") + [
                "-mmacosx-version-min=14.0",
            ],
            "@platforms//os:linux": _filter_copts(copts, "linux") + [
                "-m64",
                "-march=x86-64",
                "-msse2",
                "--target=x86_64-linux-gnu",
            ],
            "//conditions:default": copts,
        })
    else:
        custom_copts = copts + select({
            "@platforms//os:macos": [
                "-mmacosx-version-min=14.0",
            ],
            "@platforms//os:linux": [
                "-m64",
                "-march=x86-64",
                "-msse2",
                "--target=x86_64-linux-gnu",
            ],
            "//conditions:default": [],
        })

    # Automatically inject platform-specific linker options
    if type(linkopts) == "list":
        custom_linkopts = select({
            "@platforms//os:macos": _filter_linkopts(linkopts, "macos") + [
                "-mmacosx-version-min=14.0",
            ],
            "//conditions:default": linkopts,
        })
    else:
        custom_linkopts = linkopts + select({
            "@platforms//os:macos": [
                "-mmacosx-version-min=14.0",
            ],
            "//conditions:default": [],
        })

    _cc_binary(
        name = name,
        defines = defines,
        local_defines = custom_local_defines,
        copts = custom_copts,
        linkopts = custom_linkopts,
        **kwargs
    )
