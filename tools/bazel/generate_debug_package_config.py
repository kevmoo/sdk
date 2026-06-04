#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import os
import json

def main():
    sdk_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__))))
    dart_tool_dir = os.path.join(sdk_root, '.dart_tool')
    os.makedirs(dart_tool_dir, exist_ok=True)

    packages = []

    # 1. Scan pkg/ for workspace packages
    pkg_dir = os.path.join(sdk_root, 'pkg')
    if os.path.exists(pkg_dir):
        for name in os.listdir(pkg_dir):
            dir_path = os.path.join(pkg_dir, name)
            if os.path.isdir(dir_path) and os.path.exists(os.path.join(dir_path, 'pubspec.yaml')):
                pkg_name = name
                with open(os.path.join(dir_path, 'pubspec.yaml'), 'r') as f:
                    for line in f:
                        if line.startswith('name:'):
                            pkg_name = line.split(':', 1)[1].split('#', 1)[0].strip().strip("'").strip('"')
                            break
                packages.append({
                    "name": pkg_name,
                    "rootUri": f"../pkg/{name}",
                    "packageUri": "lib/",
                    "languageVersion": "3.13"
                })

    # 2. Parse root pubspec.yaml for overrides
    root_pubspec = os.path.join(sdk_root, 'pubspec.yaml')
    if os.path.exists(root_pubspec):
        with open(root_pubspec, 'r') as f:
            in_overrides = False
            curr_pkg = None
            for line in f:
                line = line.rstrip()
                if not line:
                    continue
                if line.startswith('dependency_overrides:'):
                    in_overrides = True
                    continue
                elif line and not line.startswith(' '):
                    in_overrides = False
                
                if in_overrides:
                    if line.startswith('  ') and not line.startswith('    '):
                        curr_pkg = line.split(':', 1)[0].strip()
                    elif line.startswith('    ') and curr_pkg:
                        parts = line.strip().split(':', 1)
                        if len(parts) == 2 and parts[0].strip() == 'path':
                            pkg_path = parts[1].split('#', 1)[0].strip().strip("'").strip('"')
                            packages.append({
                                "name": curr_pkg,
                                "rootUri": f"../{pkg_path}",
                                "packageUri": "lib/",
                                "languageVersion": "3.13"
                            })
                            curr_pkg = None

    config = {
        "configVersion": 2,
        "packages": packages,
        "generated": "2026-06-04T08:00:00Z",
        "generator": "generate_debug_package_config.py"
    }

    output_file = os.path.join(dart_tool_dir, 'package_config.json')
    with open(output_file, 'w') as f:
        json.dump(config, f, indent=2)
    print(f"Generated synthetic package config with {len(packages)} packages at {output_file}")

if __name__ == '__main__':
    main()
