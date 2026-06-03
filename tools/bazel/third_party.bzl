# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Bzlmod module extensions for staging external third-party dependencies non-invasively."""

def _local_overlay_repository_impl(repository_ctx):
    # Get source directory path and sandbox destination path
    src_dir = repository_ctx.path(str(repository_ctx.workspace_root) + "/" + repository_ctx.attr.path)
    dest_dir = repository_ctx.path(".")

    # Define a python script to recursively symlink the local directory,
    # supporting an optional subdirectory prefix, and skipping conflicting build files.
    prefix = repository_ctx.attr.prefix
    py_script = repository_ctx.path("symlink_exclude.py")
    repository_ctx.file(py_script, content = """
import os
import sys

src = sys.argv[1]
dest = sys.argv[2]
prefix = sys.argv[3]

for root, dirs, files in os.walk(src, followlinks=True):
    rel = os.path.relpath(root, src)
    if rel == ".":
        td = os.path.join(dest, prefix) if prefix else dest
    else:
        td = os.path.join(dest, prefix, rel) if prefix else os.path.join(dest, rel)
    os.makedirs(td, exist_ok=True)
    for f in files:
        if f in ["BUILD", "BUILD.bazel", "WORKSPACE", "MODULE.bazel"]:
            continue
        src_file = os.path.join(root, f)
        dest_file = os.path.join(td, f)
        try:
            os.symlink(src_file, dest_file)
        except FileExistsError:
            pass
""")

    # Run the symlinking script hermetically passing the prefix
    res = repository_ctx.execute(["python3", str(py_script), str(src_dir), str(dest_dir), prefix])
    if res.return_code != 0:
        fail("Failed to recursively symlink third-party directory: " + res.stderr)

    # Clean up the temporary script
    repository_ctx.delete(py_script)

    # Dynamic overlays and appends (Option 1 Custom Overlay System)
    if repository_ctx.attr.repo_type == "icu":
        # Resolve snapshot directory path from build_file label absolute path
        root_snap = repository_ctx.path(repository_ctx.attr.build_file)
        root_snap_dir = root_snap.dirname

        # 1. Stage root BUILD.bazel by reading snap and dynamically replacing package paths
        root_content = repository_ctx.read(root_snap)

        # Redirect all main-workspace package references to local external repository targets
        root_content = root_content.replace("//third_party/icu/", "//")
        root_content = root_content.replace("//tools/bazel:rules.bzl", "@//tools/bazel:rules.bzl")
        repository_ctx.file("BUILD.bazel", root_content)

        # 2. Apply custom sub-package exports_files append blocks dynamically
        for subpkg in ["common", "i18n", "stubdata"]:
            append_path = root_snap_dir.get_child("source").get_child(subpkg).get_child("BUILD.bazel.append")
            append_content = repository_ctx.read(append_path)

            upstream_build = src_dir.get_child("source").get_child(subpkg).get_child("BUILD.bazel")
            if upstream_build.exists:
                upstream_content = repository_ctx.read(upstream_build)
                repository_ctx.file("source/{}/BUILD.bazel".format(subpkg), upstream_content + "\n" + append_content)

        # 3. Stage flutter/BUILD.bazel overlay
        flutter_snap = root_snap_dir.get_child("flutter").get_child("BUILD.bazel.snap")
        repository_ctx.symlink(flutter_snap, "flutter/BUILD.bazel")

    elif repository_ctx.attr.repo_type == "zlib":
        # Stage root BUILD.bazel by reading snap and dynamically replacing package paths
        root_snap = repository_ctx.path(repository_ctx.attr.build_file)
        root_content = repository_ctx.read(root_snap)
        root_content = root_content.replace("//third_party/zlib:", ":")
        root_content = root_content.replace("//third_party/zlib", ":zlib")
        root_content = root_content.replace("//build/", "@//build/")
        root_content = root_content.replace("//tools/bazel:rules.bzl", "@//tools/bazel:rules.bzl")

        # Propagate include search paths to consumers and internal targets
        root_content = root_content.replace("name = \"zlib\",", "name = \"zlib\",\n    includes = [\".\", \"zlib\"],")
        root_content = root_content.replace("name = \"zlib_common_headers\",", "name = \"zlib_common_headers\",\n    includes = [\"zlib\"],")

        # Dynamically prefix all relative source/header paths inside the BUILD file with "zlib/"
        prefix_script = repository_ctx.path("prefix_build.py")
        temp_build = repository_ctx.path("temp_build.bazel")
        repository_ctx.file(temp_build, content = root_content)

        repository_ctx.file(prefix_script, content = """
import sys
import re

file_path = sys.argv[1]
with open(file_path, "r") as f:
    content = f.read()

# Surgical regex to identify relative source/header paths and prefix them with "zlib/"
modified = re.sub(r'"([^/@\\\\:-][^"]+\\.(c|h|S|cc))"', r'"zlib/\\1"', content)

with open(file_path, "w") as f:
    f.write(modified)
""")
        res = repository_ctx.execute(["python3", str(prefix_script), str(temp_build)])
        if res.return_code != 0:
            fail("Failed to prefix zlib BUILD file paths: " + res.stderr)

        root_content = repository_ctx.read(temp_build)
        repository_ctx.delete(prefix_script)
        repository_ctx.delete(temp_build)

        repository_ctx.file("BUILD.bazel", root_content)

local_overlay_repository = repository_rule(
    implementation = _local_overlay_repository_impl,
    local = True,
    attrs = {
        "repo_type": attr.string(mandatory = True),
        "path": attr.string(mandatory = True),
        "prefix": attr.string(default = ""),
        "build_file": attr.label(mandatory = True, allow_single_file = True),
    },
)

def _third_party_ext_impl(ctx):
    # 1. ICU Dynamic Overlay Repository
    local_overlay_repository(
        name = "icu",
        repo_type = "icu",
        path = "third_party/icu",
        build_file = "@//tools/bazel:out_of_band/snapshot/third_party/icu/BUILD.bazel.snap",
    )

    # 2. Zlib Dynamic Overlay Repository
    local_overlay_repository(
        name = "zlib",
        repo_type = "zlib",
        path = "third_party/zlib",
        prefix = "zlib",
        build_file = "@//tools/bazel:out_of_band/snapshot/third_party/zlib/BUILD.bazel.snap",
    )
    return ctx.extension_metadata(reproducible = True)

third_party_extension = module_extension(implementation = _third_party_ext_impl)
