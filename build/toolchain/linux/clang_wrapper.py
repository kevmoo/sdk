#!/usr/bin/env python3
import sys
import subprocess
import glob
import os


def main():
    args = sys.argv[1:]

    # Dynamically find clang++ in the sandbox execroot
    # It should be under external/<repo_name>/bin/clang++
    matches = glob.glob("external/*/bin/clang++")
    if matches:
        real_clang = matches[0]
    else:
        # Fallback to relative path from script location if not in sandbox, supporting arm64 hosts
        import platform
        machine = platform.machine()
        arch = "x64"
        if machine in ("aarch64", "arm64"):
            arch = "arm64"
        script_dir = os.path.dirname(os.path.realpath(__file__))
        real_clang = os.path.normpath(
            os.path.join(script_dir, "../../..",
                         f"buildtools/linux-{arch}/clang/bin/clang++"))
        if not os.path.exists(real_clang):
            print("Error: clang++ not found by wrapper at: " + real_clang,
                  file=sys.stderr)
            sys.exit(1)

    # Strip -fPIE if -fPIC is present
    if "-fPIC" in args:
        args = [arg for arg in args if arg != "-fPIE"]

    cmd = [real_clang] + args

    res = subprocess.run(cmd)
    sys.exit(res.returncode)


if __name__ == "__main__":
    main()
