#!/bin/bash
set -e

# 1. Determine workspace directories dynamically
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKTREE="$( cd "$SCRIPT_DIR/../../.." && pwd )"

if [ -f "$WORKTREE/.git" ]; then
  GITDIR_LINE=$(cat "$WORKTREE/.git")
  # GITDIR_LINE looks like: gitdir: /usr/local/google/home/kevmoo/github/sdk/.git/worktrees/subagent-...
  MAIN_SDK=$(echo "$GITDIR_LINE" | sed -E 's/^gitdir: (.*)\/\.git\/worktrees\/.*/\1/')
else
  MAIN_SDK="$WORKTREE"
fi

echo "=== Symlinking gclient dependencies dynamically ==="
echo "WORKTREE: $WORKTREE"
echo "MAIN_SDK: $MAIN_SDK"

if [ "$WORKTREE" = "$MAIN_SDK" ]; then
  echo "Running inside main SDK repo. No worktree symlinks needed!"
  exit 0
fi

# 1. Prebuilt SDK
if [ ! -d "$WORKTREE/tools/sdks/dart-sdk" ]; then
  echo "Symlinking tools/sdks/dart-sdk"
  ln -s "$MAIN_SDK/tools/sdks/dart-sdk" "$WORKTREE/tools/sdks/dart-sdk"
fi

# 2. third_party directories
for item in $(ls "$MAIN_SDK/third_party"); do
  # Skip special handling items
  if [ "$item" = "icu" ] || [ "$item" = "boringssl" ] || [ "$item" = "perfetto" ] || [ "$item" = "zlib" ] || [ "$item" = "pkg" ]; then
    continue
  fi
  
  # If it does not exist in worktree, symlink it
  if [ ! -e "$WORKTREE/third_party/$item" ]; then
    echo "Symlinking third_party/$item"
    ln -s "$MAIN_SDK/third_party/$item" "$WORKTREE/third_party/$item"
  else
    # If the folder already exists in worktree, make sure to symlink its missing sub-elements
    if [ -d "$MAIN_SDK/third_party/$item" ]; then
      for sub in $(ls -A "$MAIN_SDK/third_party/$item"); do
        if [ ! -e "$WORKTREE/third_party/$item/$sub" ]; then
          echo "Symlinking missing third_party/$item/$sub"
          ln -s "$MAIN_SDK/third_party/$item/$sub" "$WORKTREE/third_party/$item/$sub"
        fi
      done
    fi
  fi
done

# 3. ICU contents (except BUILD.bazel and .git)
mkdir -p "$WORKTREE/third_party/icu"
for sub in $(ls -A "$MAIN_SDK/third_party/icu"); do
  if [ "$sub" = "BUILD.bazel" ] || [ "$sub" = ".git" ]; then
    continue
  fi
  if [ -d "$WORKTREE/third_party/icu/$sub" ] && [ ! -L "$WORKTREE/third_party/icu/$sub" ]; then
    echo "Removing existing non-symlink directory $WORKTREE/third_party/icu/$sub to replace with symlink"
    rm -rf "$WORKTREE/third_party/icu/$sub"
  fi
  if [ ! -e "$WORKTREE/third_party/icu/$sub" ]; then
    echo "Symlinking third_party/icu/$sub"
    ln -s "$MAIN_SDK/third_party/icu/$sub" "$WORKTREE/third_party/icu/$sub"
  fi
done

# 4. BoringSSL src
if [ ! -d "$WORKTREE/third_party/boringssl/src" ]; then
  echo "Symlinking third_party/boringssl/src"
  ln -s "$MAIN_SDK/third_party/boringssl/src" "$WORKTREE/third_party/boringssl/src"
fi

# 5. Perfetto src contents (except .git)
mkdir -p "$WORKTREE/third_party/perfetto/src"
for sub in $(ls -A "$MAIN_SDK/third_party/perfetto/src"); do
  if [ "$sub" = ".git" ]; then
    continue
  fi
  if [ -d "$WORKTREE/third_party/perfetto/src/$sub" ] && [ ! -L "$WORKTREE/third_party/perfetto/src/$sub" ]; then
    if [ "$sub" = "build_config" ]; then
      continue
    fi
    echo "Removing existing non-symlink directory $WORKTREE/third_party/perfetto/src/$sub to replace with symlink"
    rm -rf "$WORKTREE/third_party/perfetto/src/$sub"
  fi
  if [ ! -e "$WORKTREE/third_party/perfetto/src/$sub" ]; then
    echo "Symlinking third_party/perfetto/src/$sub"
    ln -s "$MAIN_SDK/third_party/perfetto/src/$sub" "$WORKTREE/third_party/perfetto/src/$sub"
  fi
done

# 6. Zlib contents (except BUILD.bazel)
mkdir -p "$WORKTREE/third_party/zlib" 
for sub in $(ls "$MAIN_SDK/third_party/zlib"); do
  if [ "$sub" = "BUILD.bazel" ]; then
    continue
  fi
  if [ ! -e "$WORKTREE/third_party/zlib/$sub" ]; then
    echo "Symlinking third_party/zlib/$sub"
    ln -s "$MAIN_SDK/third_party/zlib/$sub" "$WORKTREE/third_party/zlib/$sub"
  fi
done

# 7. pkg subdirectories
mkdir -p "$WORKTREE/third_party/pkg" 
for sub in $(ls "$MAIN_SDK/third_party/pkg"); do
  if [ ! -e "$WORKTREE/third_party/pkg/$sub" ]; then
    echo "Symlinking third_party/pkg/$sub"
    ln -s "$MAIN_SDK/third_party/pkg/$sub" "$WORKTREE/third_party/pkg/$sub"
  fi
done

# 8. buildtools
if [ ! -d "$WORKTREE/buildtools" ]; then
  echo "Symlinking buildtools"
  ln -s "$MAIN_SDK/buildtools" "$WORKTREE/buildtools"
fi

# 9. sdk/version
if [ ! -e "$WORKTREE/sdk/version" ] && [ -e "$MAIN_SDK/sdk/version" ]; then
  echo "Symlinking sdk/version"
  ln -s "$MAIN_SDK/sdk/version" "$WORKTREE/sdk/version"
fi

# 10. .dart_tool/package_config.json
mkdir -p "$WORKTREE/.dart_tool"
if [ ! -e "$WORKTREE/.dart_tool/package_config.json" ] && [ -e "$MAIN_SDK/.dart_tool/package_config.json" ]; then
  echo "Symlinking .dart_tool/package_config.json"
  ln -s "$MAIN_SDK/.dart_tool/package_config.json" "$WORKTREE/.dart_tool/package_config.json"
fi

echo "=== Finished Dynamic Symlinking ==="
