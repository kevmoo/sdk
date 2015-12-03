// Copyright (c) 2015, <your name>. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

main(List<String> arguments) {
  // make sure current dir is the root of the dart sdk
  var gypFiles = Directory.current
      .listSync(recursive: false, followLinks: false)
      .where((fse) => p.basename(fse.path) == 'dart.gyp')
      .toList();

  if (gypFiles.length != 1 || gypFiles.single is! File) {
    throw 'Not at the root of the sdk';
  }

  var result = Process.runSync('git', ['ls-files', '*.status']);

  if (result.exitCode != 0) {
    print(result.stdout);
    print(result.stderr);
    print(result.exitCode);
    throw 'git failed!';
  }

  var issues = <String, List<IssueMatch>>{};

  for (var filePath in LineSplitter.split(result.stdout)) {
    issues[filePath] = parseStatusFile(filePath).toList();
  }
}

Iterable<IssueMatch> parseStatusFile(String statusFilePath) sync* {
  var lines = new File(statusFilePath).readAsLinesSync();
  int lineNumber = 0;
  for (var line in lines) {
    var match = parseStatusFileLine(++lineNumber, line);
    if (match != null) {
      yield match;
    }
  }
}

final RegExp _issueLineMatch =
    new RegExp(r':.*issue\s(\d+)', caseSensitive: false);

IssueMatch parseStatusFileLine(int line, String lineContent) {
  var matches = _issueLineMatch.allMatches(lineContent);

  if (matches.isEmpty) return null;

  var match = matches.single;

  return new IssueMatch(line, lineContent, int.parse(match[1]));
}

class IssueMatch {
  final int lineNumber;
  final String lineContents;
  final int issue;

  IssueMatch(this.lineNumber, this.lineContents, this.issue);
}
