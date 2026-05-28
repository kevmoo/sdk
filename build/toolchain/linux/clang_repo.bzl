"""Exposes the in-tree clang at buildtools/linux-x64/clang as an external repo.

Why: tool_paths in cc_toolchain_config can't contain `..` segments (Bazel
normalizes them and rejects un-normalized strings). And glob() can't escape
its package. Wrapping the clang dir in an external repo lets the cc_toolchain
reference `external/<canonical>/bin/clang` via forward-only paths.

The repository_rule symlinks the in-tree clang dir into the repo overlay and
generates a BUILD.bazel exposing the binaries as a filegroup.
"""

_BUILD_FILE = """
package(default_visibility = ["//visibility:public"])

filegroup(
    name = "all_files",
    srcs = glob(["bin/*", "lib/**", "include/**"], allow_empty = True),
)
"""

def _dart_linux_clang_impl(repo_ctx):
    # repo_ctx.workspace_root is the main repo root in Bazel 7+.
    src = repo_ctx.workspace_root.get_child("buildtools").get_child(
        "linux-x64",
    ).get_child("clang")
    for sub in ["bin", "lib", "include"]:
        child = src.get_child(sub)
        if child.exists:
            repo_ctx.symlink(child, sub)
    repo_ctx.file("BUILD.bazel", _BUILD_FILE)

    # Emit absolute paths so cc_toolchain_config can reference the in-tree
    # clang without `..` segments. tool_paths in cc_toolchain_config_info
    # accept absolute paths; this resolves them at repo-fetch time.
    repo_ctx.file(
        "paths.bzl",
        "CLANG_BIN = \"{}\"\n".format(str(src.get_child("bin"))),
    )

_dart_linux_clang = repository_rule(
    implementation = _dart_linux_clang_impl,
    local = True,
)

def _ext_impl(_ctx):
    _dart_linux_clang(name = "dart_linux_x64_clang")

dart_clang = module_extension(implementation = _ext_impl)
