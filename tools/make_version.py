#!/usr/bin/env python3
# Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
#
# This python script creates a version string in a C++ file.

from __future__ import print_function

import argparse
import hashlib
import os
import sys
import utils

# When these files change, snapshots created by the VM are potentially no longer
# backwards-compatible.
# This list must be kept in sync with the inputs to generate_version_cc_file in
# runtime/BUILD.gn.
VM_SNAPSHOT_FILES = [
    'app_snapshot.cc',
    'app_snapshot.h',
    'dart.cc',
    'dart_api_impl.cc',
    'datastream.h',
    'image_snapshot.cc',
    'image_snapshot.h',
    'object.cc',
    'object.h',
    'raw_object.cc',
    'raw_object.h',
    'snapshot.cc',
    'snapshot.h',
    'symbols.cc',
    'symbols.h',
]


def MakeSnapshotHashString(snapshot_files=None):
    vmhash = hashlib.md5()
    files = snapshot_files if snapshot_files is not None else VM_SNAPSHOT_FILES
    for vmfilename in files:
        if os.path.exists(vmfilename):
            vmfilepath = vmfilename
        else:
            vmfilepath = os.path.join(utils.DART_DIR, 'runtime', 'vm', vmfilename)
        with open(vmfilepath, 'rb') as vmfile:
            vmhash.update(vmfile.read())
    return vmhash.hexdigest()


def GetSemanticVersionFormat(no_git_hash):
    version_format = '{{SEMANTIC_SDK_VERSION}}'
    return version_format


def FormatVersionString(version, no_git_hash, no_sdk_hash, version_file=None, git_hash=None, snapshot_files=None):
    semantic_sdk_version = utils.GetVersion(no_git_hash, version_file, git_hash)
    semantic_version_format = GetSemanticVersionFormat(no_git_hash)
    version_str = (semantic_sdk_version
                   if version_file else semantic_version_format)

    version = version.replace('{{VERSION_STR}}', version_str)

    version = version.replace('{{SEMANTIC_SDK_VERSION}}', semantic_sdk_version)

    git_hash_val = git_hash
    if git_hash_val is not None:
        if len(git_hash_val) > 10:
            git_hash_val = git_hash_val[:10]
    else:
        if not no_sdk_hash and not no_git_hash:
            git_hash_val = utils.GetShortGitHash()
    if git_hash_val is None or len(git_hash_val) != 10:
        git_hash_val = '0000000000'
    version = version.replace('{{GIT_HASH}}', git_hash_val)

    channel = utils.GetChannel()
    version = version.replace('{{CHANNEL}}', channel)

    version_time = None
    if not no_git_hash:
        version_time = utils.GetGitTimestamp()
    if version_time == None:
        version_time = 'Unknown timestamp'
    version = version.replace('{{COMMIT_TIME}}', version_time)

    if '{{SNAPSHOT_HASH}}' in version:
        snapshot_hash = MakeSnapshotHashString(snapshot_files)
        version = version.replace('{{SNAPSHOT_HASH}}', snapshot_hash)

    return version


def main():
    try:
        # Parse input.
        parser = argparse.ArgumentParser()
        parser.add_argument('--input', help='Input template file.')
        parser.add_argument(
            '--no-git-hash',
            action='store_true',
            default=False,
            help=('Don\'t try to call git to derive things like '
                  'git revision hash.'))
        parser.add_argument(
            '--no-sdk-hash',
            action='store_true',
            default=False,
            help='Use null SDK hash to disable SDK verification in the VM')
        parser.add_argument('--output', help='output file name')
        parser.add_argument('-q',
                            '--quiet',
                            action='store_true',
                            default=False,
                            help='DEPRECATED: Does nothing!')
        parser.add_argument('--version-file', help='Path to the VERSION file.')
        parser.add_argument(
            '--format',
            default='{{VERSION_STR}}',
            help='Version format used if no input template is given.')
        parser.add_argument('--dart-dir', help='Path to the DART_DIR.')
        parser.add_argument('--git-hash', help='Explicit SDK git hash.')
        parser.add_argument('--snapshot-files', help='Comma-separated list of snapshot files.')

        args = parser.parse_args()

        if args.dart_dir:
            utils.DART_DIR = os.path.abspath(args.dart_dir)
            utils.VERSION_FILE = os.path.join(utils.DART_DIR, 'tools', 'VERSION')

        snapshot_files = None
        if args.snapshot_files:
            snapshot_files = [f.strip() for f in args.snapshot_files.split(',') if f.strip()]

        # If there is no input template, then write the bare version string to
        # args.output. If there is no args.output, then write the version
        # string to stdout.

        version_template = ''
        if args.input:
            version_template = open(args.input).read()
        elif not args.format is None:
            version_template = args.format
        else:
            raise 'No version template given! Set either --input or --format.'

        version = FormatVersionString(version_template, args.no_git_hash,
                                       args.no_sdk_hash, args.version_file,
                                       git_hash=args.git_hash,
                                       snapshot_files=snapshot_files)

        if args.output:
            # If the output already exists and there is no change, don't even
            # write to the file. Ninja will notice the output's modified time
            # is unchanged and avoid rebuilding dependents.
            if not os.path.exists(args.output) or open(
                    args.output).read() != version:
                with open(args.output, 'w') as fh:
                    fh.write(version)
        else:
            sys.stdout.write(version)

        return 0

    except Exception as inst:
        sys.stderr.write('make_version.py exception\n')
        sys.stderr.write(str(inst))
        sys.stderr.write('\n')

        return -1


if __name__ == '__main__':
    sys.exit(main())
