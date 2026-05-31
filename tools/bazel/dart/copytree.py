#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
"""Bazel action helper for the `copy_tree` rule (rules_dart Step 5, sdk/ assembly).

Stages a source directory tree into an output directory, reproducing the GN
`copy_tree` template (build/dart/copy_tree.gni -> tools/copy_tree.py) byte for
byte: the same `shutil.copytree(..., ignore=shutil.ignore_patterns(*patterns))`
filtering, where `patterns` is the comma-separated `--exclude` list. We do NOT
emit GN's depfile/stamp — Bazel tracks the populated declare_directory tree
artifact directly.

`dirs_exist_ok=True` lets us copy into the (possibly Bazel-precreated) output
tree path without removing it first; the resulting file set is identical to GN's
rmtree-then-copytree, which is what byte-identity is about.
"""

import argparse
import os
import shutil
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--from", dest="copy_from", required=True,
                        help="Source directory to copy from.")
    parser.add_argument("--to", dest="copy_to", required=True,
                        help="Destination directory to copy into.")
    parser.add_argument("--exclude", default="",
                        help="GN-style comma-separated ignore_patterns globs.")
    args = parser.parse_args()

    if not os.path.isdir(args.copy_from):
        sys.exit("--from must refer to a directory: %s" % args.copy_from)

    ignore = None
    if args.exclude:
        ignore = shutil.ignore_patterns(*args.exclude.split(","))

    shutil.copytree(args.copy_from, args.copy_to, ignore=ignore,
                    dirs_exist_ok=True)


if __name__ == "__main__":
    main()
