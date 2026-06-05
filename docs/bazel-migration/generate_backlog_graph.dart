// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

class Task {
  final String id;
  final String title;
  final String status;
  final List<String> prerequisites;

  Task({
    required this.id,
    required this.title,
    required this.status,
    required this.prerequisites,
  });

  @override
  String toString() => '$id ($status) -> $prerequisites';
}

void main() {
  final String scriptPath = Platform.script.toFilePath();
  final Directory scriptDir = File(scriptPath).parent;
  final File file = File('${scriptDir.path}/BACKLOG.md');

  if (!file.existsSync()) {
    print(
      'Error: BACKLOG.md not found in the script directory (${scriptDir.path}).',
    );
    exit(1);
  }

  final String content = file.readAsStringSync();
  final List<Task> tasks = parseTasks(content);
  final String mermaid = generateMermaid(tasks);
  final String updatedContent = insertGraph(content, mermaid);

  file.writeAsStringSync(updatedContent);
  print(
    'Successfully updated BACKLOG.md with dependency graph (${tasks.length} tasks).',
  );
}

List<Task> parseTasks(String content) {
  final List<Task> tasks = [];
  final List<String> sections = content.split('### 🎯 ');

  for (int i = 1; i < sections.length; i++) {
    final String section = sections[i];
    final List<String> lines = section.split('\n');
    if (lines.isEmpty) continue;

    final String firstLine = lines[0].trim();
    final RegExpMatch? headerMatch = RegExp(
      r'^\[(TASK_\d+)\]\s*(.*)',
    ).firstMatch(firstLine);
    if (headerMatch == null) continue;

    final String id = headerMatch.group(1)!;
    final String title = headerMatch.group(2)!.trim();

    String status = 'UNKNOWN';
    List<String> prerequisites = [];

    for (final String line in lines) {
      final String trimmed = line.trim();
      if (trimmed.startsWith('- **Status**:')) {
        final RegExpMatch? statusMatch = RegExp(
          r'`\[(.*?)\]`',
        ).firstMatch(trimmed);
        if (statusMatch != null) {
          status = statusMatch.group(1)!;
        }
      } else if (trimmed.startsWith('- **Prerequisites**:')) {
        if (trimmed.contains('None')) {
          prerequisites = [];
        } else {
          final Iterable<RegExpMatch> matches = RegExp(
            r'TASK_\d+',
          ).allMatches(trimmed);
          prerequisites = matches.map((m) => m.group(0)!).toList();
        }
      }
    }

    tasks.add(
      Task(id: id, title: title, status: status, prerequisites: prerequisites),
    );
  }

  return tasks;
}

String generateMermaid(List<Task> tasks) {
  final StringBuffer sb = StringBuffer();
  sb.writeln('```mermaid');
  sb.writeln('graph TD');

  // Define styles matching GitHub Light theme colors
  sb.writeln(
    '    classDef completed fill:#d4edda,stroke:#28a745,stroke-width:2px,color:#155724;',
  );
  sb.writeln(
    '    classDef inProgress fill:#fff3cd,stroke:#ffc107,stroke-width:2px,color:#856404;',
  );
  sb.writeln(
    '    classDef pending fill:#f8f9fa,stroke:#6c757d,stroke-width:1px,stroke-dasharray: 5 5,color:#6c757d;',
  );
  sb.writeln(
    '    classDef blocked fill:#f8d7da,stroke:#dc3545,stroke-width:1px,stroke-dasharray: 5 5,color:#721c24;',
  );

  // Declare nodes with labels and inline classes
  for (final Task task in tasks) {
    // Sanitize title to remove brackets and parentheses that break the Mermaid parser
    final String cleanTitle = task.title
        .replaceAll('"', '\\"')
        .replaceAll('[', '{')
        .replaceAll(']', '}')
        .replaceAll('(', '{')
        .replaceAll(')', '}');

    // Avoid using brackets in the label itself
    final String label = '${task.id}:<br>${cleanTitle}';

    String styleClass = 'pending';
    if (task.status == 'COMPLETED') {
      styleClass = 'completed';
    } else if (task.status == 'IN_PROGRESS') {
      styleClass = 'inProgress';
    } else if (task.status == 'BLOCKED') {
      styleClass = 'blocked';
    }

    // Inline style binding syntax: NodeID["Label"]:::ClassName
    sb.writeln('    ${task.id}["$label"]:::$styleClass');
  }

  sb.writeln();

  // Declare edges
  for (final Task task in tasks) {
    for (final String prereq in task.prerequisites) {
      sb.writeln('    $prereq --> ${task.id}');
    }
  }

  sb.writeln('```');
  return sb.toString();
}

String insertGraph(String content, String graph) {
  final String startMarker = '<!-- START_DEP_GRAPH -->';
  final String endMarker = '<!-- END_DEP_GRAPH -->';

  final int startIndex = content.indexOf(startMarker);
  final int endIndex = content.indexOf(endMarker);

  if (startIndex == -1 || endIndex == -1 || startIndex >= endIndex) {
    print(
      'Warning: Markers not found or invalid in BACKLOG.md. Appending instead.',
    );
    return '$content\n\n$graph';
  }

  final String before = content.substring(0, startIndex + startMarker.length);
  final String after = content.substring(endIndex);

  return '$before\n$graph\n$after';
}
