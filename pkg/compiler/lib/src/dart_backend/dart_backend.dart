// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library dart_backend;

import 'dart:async' show Future;
import 'dart:math' show max;

import '../../compiler.dart' show
    CompilerOutputProvider;
import '../common/backend_api.dart' show
    Backend;
import '../common/codegen.dart' show
    CodegenWorkItem;
import '../common/names.dart' show
    Selectors,
    Uris;
import '../common/registry.dart' show
    Registry;
import '../common/resolution.dart' show
    ResolutionCallbacks;
import '../common/tasks.dart' show
    CompilerTask;
import '../compiler.dart' show
    Compiler;
import '../compile_time_constants.dart';
import '../constants/constant_system.dart';
import '../constants/expressions.dart';
import '../constants/values.dart';
import '../dart_types.dart';
import '../diagnostics/diagnostic_listener.dart';
import '../diagnostics/invariant.dart' show
    invariant;
import '../diagnostics/messages.dart' show
    MessageKind;
import '../diagnostics/spannable.dart' show
    NO_LOCATION_SPANNABLE,
    Spannable,
    SpannableAssertionFailure;
import '../elements/elements.dart';
import '../enqueue.dart' show
    Enqueuer,
    ResolutionEnqueuer,
    WorldImpact;
import '../library_loader.dart' show
    LoadedLibraries;
import '../mirror_renamer/mirror_renamer.dart';
import '../resolution/tree_elements.dart' show
    TreeElements,
    TreeElementMapping;
import '../tokens/keyword.dart' show
    Keyword;
import '../tree/tree.dart';
import '../universe/selector.dart' show
    Selector;
import '../universe/universe.dart' show
    UniverseSelector;
import '../util/util.dart';
import 'backend_ast_to_frontend_ast.dart' as backend2frontend;

part 'backend.dart';
part 'renamer.dart';
part 'placeholder_collector.dart';
part 'outputter.dart';
