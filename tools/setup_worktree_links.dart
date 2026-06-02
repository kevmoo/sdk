// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import "dart:io";

/// A cross-platform bootstrap tool to establish dynamic symlinks for gclient dependencies.
///
/// **Important:** This script must be run from the root of your newly created secondary Git worktree.
///
/// In secondary Git worktrees, downloading duplicate copies of massive dependencies like
/// `third_party/`, `buildtools/`, and prebuilt SDKs is extremely slow and wasteful. This
/// script resolves the path of the main SDK repository (reading Git worktree metadata)
/// and establishes lightweight symbolic links (or junctions on Windows) for those folders
/// inside the secondary worktree.
///
/// This script is completely dependency-free, relying only on `dart:io` so it can run
/// before package resolution is initialized in a newly created worktree.
///
/// ### Usage:
/// ```bash
/// tools/sdks/dart-sdk/bin/dart tools/setup_worktree_links.dart
/// ```
///
/// If run inside the main SDK repository, this tool prints a message and exits with `0`
/// without performing any actions.
void main() {
  final scriptPath = Platform.script.toFilePath();
  final scriptFile = File(scriptPath);
  final toolsDir = scriptFile.parent;
  final worktreeDir = toolsDir.parent;
  final worktree = _normalizePath(worktreeDir.path);

  final gitPath = _joinPaths(worktree, ".git");
  final gitStat = FileSystemEntity.typeSync(gitPath, followLinks: false);

  String mainSdk = worktree;
  if (gitStat == FileSystemEntityType.directory) {
    mainSdk = worktree;
  } else if (gitStat == FileSystemEntityType.file) {
    try {
      final contents = File(gitPath).readAsStringSync().trim();
      final match = RegExp(
        r"^gitdir:\s*(.*)[/\\\\]\.git[/\\\\]worktrees[/\\].*$",
      ).firstMatch(contents);
      if (match != null) {
        mainSdk = match.group(1)!;
      } else {
        if (contents.startsWith("gitdir:")) {
          final gitDir = contents.substring(7).trim();
          final idx = gitDir.indexOf("/.git/worktrees/");
          if (idx != -1) {
            mainSdk = gitDir.substring(0, idx);
          } else {
            final idxWin = gitDir.indexOf("\\.git\\worktrees\\");
            if (idxWin != -1) {
              mainSdk = gitDir.substring(0, idxWin);
            }
          }
        }
      }
    } catch (e) {
      print("Warning: Failed to read .git file: $e. Assuming main SDK.");
    }
  }

  mainSdk = _normalizePath(mainSdk);

  print("WORKTREE: $worktree");
  print("MAIN_SDK: $mainSdk");

  if (worktree == mainSdk) {
    print("Running inside main SDK repo. No worktree symlinks needed!");
    exit(0);
  }

  print("=== Symlinking gclient dependencies dynamically ===");

  final worktreeSdk = _joinPaths(worktree, "tools/sdks/dart-sdk");
  final mainSdkSdk = _joinPaths(mainSdk, "tools/sdks/dart-sdk");
  if (Directory(mainSdkSdk).existsSync()) {
    if (FileSystemEntity.typeSync(worktreeSdk, followLinks: false) ==
        FileSystemEntityType.notFound) {
      _safeLink(mainSdkSdk, worktreeSdk, isDirectory: true);
    }
  } else {
    print("Warning: Main SDK prebuilt SDK not found at $mainSdkSdk");
  }

  final mainThirdParty = Directory(_joinPaths(mainSdk, "third_party"));
  final worktreeThirdParty = Directory(_joinPaths(worktree, "third_party"));

  if (mainThirdParty.existsSync()) {
    worktreeThirdParty.createSync(recursive: true);
    final specialItems = {"icu", "boringssl", "perfetto", "zlib", "pkg"};

    for (final entity in mainThirdParty.listSync(followLinks: false)) {
      final name = _getBasename(entity.path);
      if (specialItems.contains(name)) continue;

      final target = entity.path;
      final linkPath = _joinPaths(worktreeThirdParty.path, name);
      final isDir = FileSystemEntity.isDirectorySync(target);

      final workType = FileSystemEntity.typeSync(linkPath, followLinks: false);

      if (workType == FileSystemEntityType.notFound) {
        _safeLink(target, linkPath, isDirectory: isDir);
      } else if (workType == FileSystemEntityType.directory && isDir) {
        final mainSubDir = Directory(target);
        for (final subEntity in mainSubDir.listSync(followLinks: false)) {
          final subName = _getBasename(subEntity.path);
          final subTarget = subEntity.path;
          final subLinkPath = _joinPaths(linkPath, subName);
          final subIsDir = FileSystemEntity.isDirectorySync(subTarget);

          if (FileSystemEntity.typeSync(subLinkPath, followLinks: false) ==
              FileSystemEntityType.notFound) {
            _safeLink(subTarget, subLinkPath, isDirectory: subIsDir);
          }
        }
      }
    }
  }

  final mainIcu = _joinPaths(mainSdk, "third_party/icu");
  final worktreeIcu = _joinPaths(worktree, "third_party/icu");

  if (Directory(mainIcu).existsSync()) {
    Directory(worktreeIcu).createSync(recursive: true);
    for (final entity in Directory(mainIcu).listSync(followLinks: false)) {
      final name = _getBasename(entity.path);
      if (name == "BUILD.bazel" || name == ".git") continue;

      final target = entity.path;
      final linkPath = _joinPaths(worktreeIcu, name);
      final isDir = FileSystemEntity.isDirectorySync(target);

      final exists = FileSystemEntity.typeSync(linkPath, followLinks: false) !=
          FileSystemEntityType.notFound;
      final isLink = FileSystemEntity.isLinkSync(linkPath);

      if (exists && !isLink) {
        print(
          "Removing existing non-symlink directory/file $linkPath to replace with symlink",
        );
        _safeDelete(linkPath);
      }

      _safeLink(target, linkPath, isDirectory: isDir);
    }
  }

  final mainBoring = _joinPaths(mainSdk, "third_party/boringssl/src");
  final worktreeBoring = _joinPaths(worktree, "third_party/boringssl/src");
  if (Directory(mainBoring).existsSync()) {
    if (FileSystemEntity.typeSync(worktreeBoring, followLinks: false) ==
        FileSystemEntityType.notFound) {
      _safeLink(mainBoring, worktreeBoring, isDirectory: true);
    }
  }

  final mainPerfetto = _joinPaths(mainSdk, "third_party/perfetto/src");
  final worktreePerfetto = _joinPaths(worktree, "third_party/perfetto/src");

  if (Directory(mainPerfetto).existsSync()) {
    Directory(worktreePerfetto).createSync(recursive: true);
    for (final entity in Directory(mainPerfetto).listSync(followLinks: false)) {
      final name = _getBasename(entity.path);
      if (name == ".git") continue;

      final target = entity.path;
      final linkPath = _joinPaths(worktreePerfetto, name);
      final isDir = FileSystemEntity.isDirectorySync(target);

      if (name != "build_config") {
        final exists =
            FileSystemEntity.typeSync(linkPath, followLinks: false) !=
                FileSystemEntityType.notFound;
        final isLink = FileSystemEntity.isLinkSync(linkPath);
        if (exists && !isLink) {
          print(
            "Removing existing non-symlink directory/file $linkPath to replace with symlink",
          );
          _safeDelete(linkPath);
        }
      }

      _safeLink(target, linkPath, isDirectory: isDir);
    }
  }

  final mainZlib = _joinPaths(mainSdk, "third_party/zlib");
  final worktreeZlib = _joinPaths(worktree, "third_party/zlib");

  if (Directory(mainZlib).existsSync()) {
    Directory(worktreeZlib).createSync(recursive: true);
    for (final entity in Directory(mainZlib).listSync(followLinks: false)) {
      final name = _getBasename(entity.path);
      if (name == "BUILD.bazel") continue;

      final target = entity.path;
      final linkPath = _joinPaths(worktreeZlib, name);
      final isDir = FileSystemEntity.isDirectorySync(target);

      if (FileSystemEntity.typeSync(linkPath, followLinks: false) ==
          FileSystemEntityType.notFound) {
        _safeLink(target, linkPath, isDirectory: isDir);
      }
    }
  }

  final mainPkg = _joinPaths(mainSdk, "third_party/pkg");
  final worktreePkg = _joinPaths(worktree, "third_party/pkg");

  if (Directory(mainPkg).existsSync()) {
    Directory(worktreePkg).createSync(recursive: true);
    for (final entity in Directory(mainPkg).listSync(followLinks: false)) {
      final name = _getBasename(entity.path);
      final target = entity.path;
      final linkPath = _joinPaths(worktreePkg, name);
      final isDir = FileSystemEntity.isDirectorySync(target);

      if (FileSystemEntity.typeSync(linkPath, followLinks: false) ==
          FileSystemEntityType.notFound) {
        _safeLink(target, linkPath, isDirectory: isDir);
      }
    }
  }

  final mainBuildtools = _joinPaths(mainSdk, "buildtools");
  final worktreeBuildtools = _joinPaths(worktree, "buildtools");
  if (Directory(mainBuildtools).existsSync()) {
    if (FileSystemEntity.typeSync(worktreeBuildtools, followLinks: false) ==
        FileSystemEntityType.notFound) {
      _safeLink(mainBuildtools, worktreeBuildtools, isDirectory: true);
    }
  }

  final mainVersion = _joinPaths(mainSdk, "sdk/version");
  final worktreeVersion = _joinPaths(worktree, "sdk/version");
  if (File(mainVersion).existsSync()) {
    if (FileSystemEntity.typeSync(worktreeVersion, followLinks: false) ==
        FileSystemEntityType.notFound) {
      _safeLink(mainVersion, worktreeVersion, isDirectory: false);
    }
  }

  final mainPkgConfig = _joinPaths(mainSdk, ".dart_tool/package_config.json");
  final worktreeDartTool = _joinPaths(worktree, ".dart_tool");
  final worktreePkgConfig = _joinPaths(worktreeDartTool, "package_config.json");

  if (File(mainPkgConfig).existsSync()) {
    Directory(worktreeDartTool).createSync(recursive: true);
    if (FileSystemEntity.typeSync(worktreePkgConfig, followLinks: false) ==
        FileSystemEntityType.notFound) {
      _safeLink(mainPkgConfig, worktreePkgConfig, isDirectory: false);
    }
  }

  print("=== Finished Dynamic Symlinking ===");
}

// Platform-agnostic path helpers
String _joinPaths(String p1, String p2) {
  final cleanP1 = p1.replaceAll(RegExp(r"[/\\]+$"), "");
  final cleanP2 = p2.replaceAll(RegExp(r"^[/\\]+"), "");
  if (cleanP1.isEmpty) return cleanP2;
  if (cleanP2.isEmpty) return cleanP1;
  return "$cleanP1${Platform.pathSeparator}$cleanP2";
}

String _getBasename(String path) {
  final normalized = path.replaceAll("\\", "/");
  final parts = normalized.split("/");
  return parts.isNotEmpty ? parts.last : "";
}

String _normalizePath(String path) {
  var absPath = Directory(path).absolute.path;
  if ((absPath.endsWith("/") || absPath.endsWith("\\")) && absPath.length > 1) {
    absPath = absPath.substring(0, absPath.length - 1);
  }
  return absPath;
}

void _safeDelete(String path) {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;

  print("Deleting pre-existing entity at $path");
  try {
    if (type == FileSystemEntityType.directory) {
      Directory(path).deleteSync(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      File(path).deleteSync();
    } else if (type == FileSystemEntityType.link) {
      Link(path).deleteSync();
    }
  } catch (e) {
    print("Error deleting $path: $e. Attempting to proceed.");
  }
}

void _copyFile(String source, String destination) {
  print("Copying file: $source -> $destination (fallback)");
  _safeDelete(destination);
  File(destination).parent.createSync(recursive: true);
  File(source).copySync(destination);
}

void _safeLink(String target, String linkPath, {required bool isDirectory}) {
  final link = Link(linkPath);
  final normalizedTarget = _normalizePath(target);

  if (FileSystemEntity.isLinkSync(linkPath)) {
    try {
      final existingTarget = link.targetSync();
      if (_normalizePath(existingTarget) == normalizedTarget) {
        return;
      }
      print(
        "Link $linkPath points to $existingTarget, but should point to $target. Re-creating.",
      );
      link.deleteSync();
    } catch (e) {
      print("Link $linkPath is invalid or broken. Re-creating. Error: $e");
      try {
        link.deleteSync();
      } catch (_) {}
    }
  } else if (FileSystemEntity.typeSync(linkPath, followLinks: false) !=
      FileSystemEntityType.notFound) {
    print(
      "Removing existing non-link entity at $linkPath to replace with link",
    );
    _safeDelete(linkPath);
  }

  Directory(link.parent.path).createSync(recursive: true);

  try {
    print("Creating link: $linkPath -> $target");
    link.createSync(target);
  } catch (e) {
    if (Platform.isWindows &&
        e.toString().contains("ERROR_PRIVILEGE_NOT_HELD")) {
      if (isDirectory) {
        print(
          "Missing privilege for symlink on Windows. Falling back to Junction...",
        );
        try {
          final result = Process.runSync("cmd", [
            "/c",
            "mklink",
            "/j",
            linkPath,
            target,
          ]);
          if (result.exitCode == 0) {
            print("Created directory junction: $linkPath -> $target");
            return;
          } else {
            print("Junction fallback failed: ${result.stderr}");
          }
        } catch (fallbackErr) {
          print("Junction fallback exception: $fallbackErr");
        }
      } else {
        print(
          "Missing privilege for symlink on Windows. Falling back to file copy...",
        );
        try {
          _copyFile(target, linkPath);
          return;
        } catch (copyErr) {
          print("File copy fallback failed: $copyErr");
        }
      }
    }
    print("Failed to create link $linkPath -> $target: $e");
    rethrow;
  }
}
