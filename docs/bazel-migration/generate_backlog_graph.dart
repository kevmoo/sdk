// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

class SuccessCriterion {
  final String description;
  final bool verified;

  SuccessCriterion({required this.description, required this.verified});

  factory SuccessCriterion.fromJson(Map<String, dynamic> json) {
    return SuccessCriterion(
      description: json['description'] as String,
      verified: json['verified'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
    'description': description,
    'verified': verified,
  };
}

class Task {
  final String id;
  final String title;
  final String status;
  final List<String> prerequisites;
  final String owner;
  final String commit;
  final List<String> targetFiles;
  final String description;
  final String verificationCommand;
  final List<SuccessCriterion> successCriteria;

  Task({
    required this.id,
    required this.title,
    required this.status,
    required this.prerequisites,
    required this.owner,
    required this.commit,
    required this.targetFiles,
    required this.description,
    required this.verificationCommand,
    required this.successCriteria,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'] as String,
      title: json['title'] as String,
      status: json['status'] as String,
      prerequisites: List<String>.from(json['prerequisites'] as List),
      owner: json['owner'] as String,
      commit: json['commit'] as String,
      targetFiles: List<String>.from(json['target_files'] as List),
      description: json['description'] as String,
      verificationCommand: json['verification_command'] as String,
      successCriteria: (json['success_criteria'] as List)
          .map((e) => SuccessCriterion.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

void main() {
  final String scriptPath = Platform.script.toFilePath();
  final Directory scriptDir = File(scriptPath).parent;
  final File jsonFile = File('${scriptDir.path}/backlog.json');
  final File backlogFile = File('${scriptDir.path}/BACKLOG.md');
  final File historyFile = File('${scriptDir.path}/BACKLOG_HISTORY.md');

  if (!jsonFile.existsSync()) {
    print('Error: backlog.json not found in ${scriptDir.path}');
    exit(1);
  }

  final String jsonContent = jsonFile.readAsStringSync();
  final Map<String, dynamic> data =
      jsonDecode(jsonContent) as Map<String, dynamic>;
  final List<Task> tasks = (data['tasks'] as List)
      .map((e) => Task.fromJson(e as Map<String, dynamic>))
      .toList();

  // Validate Graph for missing prerequisites
  validateGraph(tasks);

  final List<Task> activeTasks = tasks
      .where((t) => t.status != 'COMPLETED')
      .toList();
  final List<Task> completedTasks = tasks
      .where((t) => t.status == 'COMPLETED')
      .toList();

  // Generate Mermaid (always use all tasks for the full graph)
  final String mermaid = generateMermaid(tasks);

  // Generate BACKLOG.md
  final String activeMarkdown = generateActiveMarkdown(
    activeTasks,
    completedTasks.length,
    tasks.length,
    mermaid,
  );
  backlogFile.writeAsStringSync(activeMarkdown);

  // Generate BACKLOG_HISTORY.md
  final String historyMarkdown = generateHistoryMarkdown(completedTasks);
  historyFile.writeAsStringSync(historyMarkdown);

  print(
    'Successfully compiled BACKLOG.md (${activeTasks.length} active tasks) and BACKLOG_HISTORY.md (${completedTasks.length} completed tasks).',
  );
}

void validateGraph(List<Task> tasks) {
  final Map<String, Task> taskMap = {for (var t in tasks) t.id: t};
  for (final Task task in tasks) {
    for (final String prereq in task.prerequisites) {
      if (!taskMap.containsKey(prereq)) {
        print('Warning: Task ${task.id} has missing prerequisite: $prereq');
      }
    }
  }
}

String generateMermaid(List<Task> tasks) {
  final StringBuffer sb = StringBuffer();
  sb.writeln('```mermaid');
  sb.writeln('graph TD');
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

  for (final Task task in tasks) {
    final String cleanTitle = task.title
        .replaceAll('"', '\\"')
        .replaceAll('[', '{')
        .replaceAll(']', '}')
        .replaceAll('(', '{')
        .replaceAll(')', '}');

    final String label = '${task.id}:<br>${cleanTitle}';

    String styleClass = 'pending';
    if (task.status == 'COMPLETED') {
      styleClass = 'completed';
    } else if (task.status == 'IN_PROGRESS') {
      styleClass = 'inProgress';
    } else if (task.status == 'BLOCKED') {
      styleClass = 'blocked';
    }

    sb.writeln('    ${task.id}["$label"]:::$styleClass');
  }

  sb.writeln();

  for (final Task task in tasks) {
    for (final String prereq in task.prerequisites) {
      sb.writeln('    $prereq --> ${task.id}');
    }
  }

  sb.writeln('```');
  return sb.toString();
}

String generateActiveMarkdown(
  List<Task> activeTasks,
  int completedCount,
  int totalCount,
  String mermaid,
) {
  final StringBuffer sb = StringBuffer();
  sb.writeln('# Dart SDK Bazel Migration: Active Backlog & Coordination Board');
  sb.writeln();
  sb.writeln(
    'This file is generated automatically from `backlog.json`. **Do not edit this file directly.**',
  );
  sb.writeln('To make changes, edit `backlog.json` and run:');
  sb.writeln(
    '`tools/sdks/dart-sdk/bin/dart docs/bazel-migration/generate_backlog_graph.dart`',
  );
  sb.writeln();
  sb.writeln('> 🚨 **AGENT PROTOCOL (Mandatory)**:');
  sb.writeln(
    '> 1. **Scan**: Read this file FIRST on arrival. Check for open `[PENDING]` tasks.',
  );
  sb.writeln(
    '> 2. **Claim**: Claim a task in `backlog.json` by setting status to `IN_PROGRESS` and owner, then run the generator script.',
  );
  sb.writeln(
    '> 3. **Verify**: Run the exact `Verification Command` in the task block.',
  );
  sb.writeln(
    '> 4. **Update**: Once verified green, update status to `COMPLETED` in `backlog.json`, run the script, and update the session log in `STATUS.md`.',
  );
  sb.writeln();
  sb.writeln('---');
  sb.writeln();
  sb.writeln('## 📊 Global State');
  sb.writeln();
  sb.writeln('- **Active Agent**: `[none]`');
  sb.writeln('- **Global Lock**: `[unlocked]`');
  sb.writeln(
    '- **Overall Progress**: $completedCount/$totalCount Tasks (Completed details in [BACKLOG_HISTORY.md](BACKLOG_HISTORY.md))',
  );
  sb.writeln();
  sb.writeln('---');
  sb.writeln();
  sb.writeln('## 🗺️ Dependency Graph');
  sb.writeln();
  sb.writeln('<!-- START_DEP_GRAPH -->');
  sb.writeln(mermaid);
  sb.writeln('<!-- END_DEP_GRAPH -->');
  sb.writeln();
  sb.writeln('---');
  sb.writeln();
  sb.writeln('## 📋 Active Backlog');
  sb.writeln();

  if (activeTasks.isEmpty) {
    sb.writeln('🎉 **All tasks completed!**');
  } else {
    for (final Task task in activeTasks) {
      sb.writeln(generateTaskMarkdown(task));
      sb.writeln('---');
      sb.writeln();
    }
  }

  return sb.toString();
}

String generateHistoryMarkdown(List<Task> completedTasks) {
  final StringBuffer sb = StringBuffer();
  sb.writeln('# Dart SDK Bazel Migration: Completed Tasks History');
  sb.writeln();
  sb.writeln(
    'This file lists all successfully completed tasks in the Bazel migration. It is generated automatically from `backlog.json`.',
  );
  sb.writeln();
  sb.writeln('---');
  sb.writeln();
  sb.writeln('## 📜 Completed Tasks');
  sb.writeln();

  if (completedTasks.isEmpty) {
    sb.writeln('No tasks completed yet.');
  } else {
    for (final Task task in completedTasks) {
      sb.writeln(generateTaskMarkdown(task));
      sb.writeln('---');
      sb.writeln();
    }
  }

  return sb.toString();
}

String generateTaskMarkdown(Task task) {
  final StringBuffer sb = StringBuffer();
  sb.writeln('### 🎯 [${task.id}] ${task.title}');
  sb.writeln('- **Status**: `[${task.status}]`');

  final String prereqs = task.prerequisites.isEmpty
      ? 'None'
      : task.prerequisites.map((p) => '`$p`').join(', ');
  sb.writeln('- **Prerequisites**: $prereqs');

  sb.writeln('- **Owner**: `[${task.owner}]`');
  sb.writeln('- **Commit**: `[${task.commit}]`');

  sb.writeln('- **Target Files**:');
  if (task.targetFiles.isEmpty) {
    sb.writeln('  - None');
  } else {
    for (final String file in task.targetFiles) {
      sb.writeln('  - `$file`');
    }
  }

  sb.writeln('- **Description**:');
  final String indentedDesc = task.description
      .split('\n')
      .map((line) => '  $line')
      .join('\n');
  sb.writeln(indentedDesc);

  if (task.verificationCommand.isNotEmpty) {
    sb.writeln('- **Verification Command**:');
    sb.writeln('  ```bash');
    final String indentedVer = task.verificationCommand
        .split('\n')
        .map((line) => '  $line')
        .join('\n');
    sb.writeln(indentedVer);
    sb.writeln('  ```');
  }

  sb.writeln('- **Success Criteria**:');
  for (final SuccessCriterion criterion in task.successCriteria) {
    final String box = criterion.verified ? '[x]' : '[ ]';
    sb.writeln('  - $box ${criterion.description}');
  }

  return sb.toString();
}
