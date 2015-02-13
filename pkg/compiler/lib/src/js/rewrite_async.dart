// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library rewrite_async;

// TODO(sigurdm): Throws in catch-handlers are handled wrong.
// TODO(sigurdm): Avoid using variables in templates. It could blow up memory
// use.

import "dart:math" show max;
import 'dart:collection';

import "js.dart" as js;

import '../util/util.dart';
import '../dart2jslib.dart' show DiagnosticListener;

import "../helpers/helpers.dart";

/// Rewrites a [js.Fun] with async/sync*/async* functions and await and yield
/// (with dart-like semantics) to an equivalent function without these.
/// await-for is not handled and must be rewritten before. (Currently handled
/// in ssa/builder.dart).
///
/// When generating the input to this, special care must be taken that
/// parameters to sync* functions that are mutated in the body must be boxed.
/// (Currently handled in closure.dart).
///
/// Look at [visitFun], [visitDartYield] and [visitAwait] for more explanation.
class AsyncRewriter extends js.NodeVisitor {

  // Local variables are hoisted to the top of the function, so they are
  // collected here.
  List<js.VariableDeclaration> localVariables =
      new List<js.VariableDeclaration>();

  Map<js.Node, int> continueLabels = new Map<js.Node, int>();
  Map<js.Node, int> breakLabels = new Map<js.Node, int>();
  Map<js.Node, int> finallyLabels = new Map<js.Node, int>();
  int exitLabel;

  // A stack of all enclosing jump targets (including the function for
  // representing the target of a return, and all enclosing try-blocks that have
  // finally part, this way ensuring all the finally blocks between a jump and
  // its target are run before the jump.
  List<js.Node> targetsAndTries = new List<js.Node>();

  List<int> continueStack = new List<int>();
  List<int> breakStack = new List<int>();
  List<int> returnStack = new List<int>();

  List<Pair<String, String>> variableRenamings =
      new List<Pair<String, String>>();

  PreTranslationAnalysis analysis;

  List<int> errorHandlerLabels = new List<int>();

  final Function safeVariableName;

  // All the <x>Name variables are names of Javascript variables used in the
  // transformed code.

  /// Contains the result of an awaited expression, or a conditional or
  /// lazy boolean operator.
  ///
  /// For example a conditional expression is roughly translated like:
  /// [[cond ? a : b]]
  ///
  /// Becomes:
  ///
  /// while true { // outer while loop
  ///   switch (goto) { // Simulates goto
  ///     ...
  ///       goto = [[cond]] ? thenLabel : elseLabel
  ///       break;
  ///     case thenLabel:
  ///       result = [[a]];
  ///       goto = joinLabel;
  ///     case elseLabel:
  ///       result = [[b]];
  ///     case joinLabel:
  ///       // Now the result of computing the condition is in result.
  ///     ....
  ///   }
  /// }
  ///
  /// It is a parameter to the [helperName] function, so that [thenHelper] and
  /// [streamHelper] can call [helperName] with the result of an awaited Future.
  String resultName;

  /// The name of the inner function that is scheduled to do each await/yield,
  /// and called to do a new iteration for sync*.
  String helperName;

  /// The Completer that will finish an async function.
  ///
  /// Not used for sync* or async* functions.
  String completerName;

  /// The StreamController that controls an async* function.
  ///
  /// Not used for async and sync* functions
  String controllerName;

  /// Used to simulate a goto.
  ///
  /// To "goto" a label, the label is assigned to this
  /// variable, and break out of the switch to take another iteration in the
  /// while loop. See [addGoto]
  String gotoName;

  /// The label of the current error handler.
  String handlerName;

  /// Current caught error.
  String errorName;

  /// A stack of labels of finally blocks to visit, and the label to go to after
  /// the last.
  String nextName;

  /// The current returned value (a finally block may overwrite it).
  String returnValueName;

  /// The label of the outer loop.
  ///
  /// Used if there are untransformed loops containing break or continues to
  /// targets outside the loop.
  String outerLabelName;

  /// If javascript `this` is used, it is accessed via this variable, in the
  /// [helperName] function.
  String selfName;

  // These expressions are hooks for communicating with the runtime.

  /// The function called by an async function to simulate an await or return.
  ///
  /// For an await it is called with:
  ///
  /// - The value to await
  /// - The [helperName]
  /// - The [completerName]
  /// - A JavaScript function that is executed if the future completed with
  ///   an error. That function is responsible for executing the right error
  ///   handler and/or finally blocks).
  ///
  /// For a return it is called with:
  ///
  /// - The value to complete the completer with.
  /// - null
  /// - The [completerName]
  /// - null.
  final js.Expression thenHelper;

  /// The function called by an async* function to simulate an await, yield or
  /// yield*.
  ///
  /// For an await/yield/yield* it is called with:
  ///
  /// - The value to await/yieldExpression(value to yield)/
  /// yieldStarExpression(stream to yield)
  /// - The [helperName]
  /// - The [controllerName]
  /// - A JavaScript function that is executed if the future completed with
  ///   an error. That function is responsible for executing the right error
  ///   handler and/or finally blocks).
  ///
  /// For a return it is called with:
  ///
  /// - null
  /// - null
  /// - The [controllerName]
  /// - null.
  final js.Expression streamHelper;

  /// Contructor used to initialize the [completerName] variable.
  ///
  /// Specific to async methods.
  final js.Expression newCompleter;

  /// Contructor used to initialize the [controllerName] variable.
  ///
  /// Specific to async* methods.
  final js.Expression newController;

  /// Used to get the `Stream` out of the [controllerName] variable.
  ///
  /// Specific to async* methods.
  final js.Expression streamOfController;

  /// Contructor creating the Iterable for a sync* method. Called with
  /// [helperName].
  final js.Expression newIterable;

  /// A JS Expression that creates a marker showing that iteration is over.
  ///
  /// Called without arguments.
  final js.Expression endOfIteration;

  /// A JS Expression that creates a marker indicating a 'yield' statement.
  ///
  /// Called with the value to yield.
  final js.Expression yieldExpression;

  /// A JS Expression that creates a marker indication a 'yield*' statement.
  ///
  /// Called with the stream to yield from.
  final js.Expression yieldStarExpression;

  final DiagnosticListener diagnosticListener;
  // For error reporting only.
  Spannable get spannable {
    return (_spannable == null) ? NO_LOCATION_SPANNABLE : _spannable;
  }

  Spannable _spannable;

  int _currentLabel = 0;

  // The highest temporary variable index currently in use.
  int currentTempVarIndex = 0;
  // The highest temporary variable index ever in use in this function.
  int tempVarHighWaterMark = 0;
  Map<int, js.Expression> tempVarNames = new Map<int, js.Expression>();

  js.AsyncModifier async;

  bool get isSync => async == const js.AsyncModifier.sync();
  bool get isAsync => async == const js.AsyncModifier.async();
  bool get isSyncStar => async == const js.AsyncModifier.syncStar();
  bool get isAsyncStar => async == const js.AsyncModifier.asyncStar();

  AsyncRewriter(this.diagnosticListener,
                spannable,
                {this.thenHelper,
                 this.streamHelper,
                 this.streamOfController,
                 this.newCompleter,
                 this.newController,
                 this.endOfIteration,
                 this.newIterable,
                 this.yieldExpression,
                 this.yieldStarExpression,
                 this.safeVariableName})
      : _spannable = spannable;

  /// Main entry point.
  /// Rewrites a sync*/async/async* function to an equivalent normal function.
  ///
  /// [spannable] can be passed to have a location for error messages.
  js.Fun rewrite(js.Fun node, [Spannable spannable]) {
    _spannable = spannable;

    async = node.asyncModifier;
    assert(!isSync);

    analysis = new PreTranslationAnalysis(unsupported);
    analysis.analyze(node);

    // To avoid name collisions with existing names, the fresh names are
    // generated after the analysis.
    resultName = freshName("result");
    completerName = freshName("completer");
    controllerName = freshName("controller");
    helperName = freshName("helper");
    gotoName = freshName("goto");
    handlerName = freshName("handler");
    errorName = freshName("error");
    nextName = freshName("next");
    returnValueName = freshName("returnValue");
    outerLabelName = freshName("outer");
    selfName = freshName("self");

    return node.accept(this);
  }

  js.Expression get currentErrorHandler {
    return errorHandlerLabels.isEmpty
        ? new js.LiteralNull()
        : js.number(errorHandlerLabels.last);
  }

  int allocateTempVar() {
    assert(tempVarHighWaterMark >= currentTempVarIndex);
    currentTempVarIndex++;
    tempVarHighWaterMark = max(currentTempVarIndex, tempVarHighWaterMark);
    return currentTempVarIndex;
  }

  js.VariableUse useTempVar(int i) {
    return tempVarNames.putIfAbsent(
        i, () => new js.VariableUse(freshName("temp$i")));
  }

  /// Generates a variable name with [safeVariableName] based on [originalName]
  /// with a suffix to guarantee it does not collide with already used names.
  String freshName(String originalName) {
    String safeName = safeVariableName(originalName);
    String result = safeName;
    int counter = 1;
    while (analysis.usedNames.contains(result)) {
      result = "$safeName$counter";
      ++counter;
    }
    analysis.usedNames.add(result);
    return result;
  }

  /// All the pieces are collected in this map, to create a switch with a case
  /// for each label.
  ///
  /// The order is important, therefore the type is explicitly LinkedHashMap.
  LinkedHashMap<int, List<js.Statement>> labelledParts =
      new LinkedHashMap<int, List<js.Statement>>();

  /// Description of each label for readability of the non-minified output.
  Map<int, String> labelComments = new Map<int, String>();

  /// True if the function has any try blocks containing await.
  bool hasTryBlocks = false;

  /// True if any return, break or continue passes through a finally.
  bool hasJumpThroughFinally = false;

  /// True if the traversion currently is inside a loop or switch for which
  /// [shouldTransform] is false.
  bool insideUntranslatedBreakable = false;

  /// True if a label is used to break to an outer switch-statement.
  bool hasJumpThoughOuterLabel = false;

  /// True if there is a catch-handler protected by a finally with no enclosing
  /// catch-handlers.
  bool needsRethrow = false;

  /// Buffer for collecting translated statements belonging to the same switch
  /// case.
  List<js.Statement> currentStatementBuffer;

  // Labels will become cases in the big switch expression, and `goto label`
  // is expressed by assigning to the switch key [gotoName] and breaking out of
  // the switch.

  int newLabel([String comment]) {
    int result = _currentLabel;
    _currentLabel++;
    if (comment != null) {
      labelComments[result] = comment;
    }
    return result;
  }

  /// Begins outputting statements to a new buffer with label [label].
  ///
  /// Each buffer ends up as its own case part in the big state-switch.
  void beginLabel(int label) {
    assert(!labelledParts.containsKey(label));
    currentStatementBuffer = new List<js.Statement>();
    labelledParts[label] = currentStatementBuffer;
    addStatement(new js.Comment(labelComments[label]));
  }

  /// Returns a statement assigning to the variable named [gotoName].
  /// This should be followed by a break for the goto to be executed. Use
  /// [gotoWithBreak] or [addGoto] for this.
  js.Statement setGotoVariable(int label) {
    return new js.ExpressionStatement(
        new js.Assignment(new js.VariableUse(gotoName), js.number(label)));
  }

  /// Returns a block that has a goto to [label] including the break.
  ///
  /// Also inserts a comment describing the label if available.
  js.Block gotoAndBreak(int label) {
    List<js.Statement> statements = new List<js.Statement>();
    if (labelComments.containsKey(label)) {
      statements.add(new js.Comment("goto ${labelComments[label]}"));
    }
    statements.add(setGotoVariable(label));
    if (insideUntranslatedBreakable) {
      hasJumpThoughOuterLabel = true;
      statements.add(new js.Break(outerLabelName));
    } else {
      statements.add(new js.Break(null));
    }
    return new js.Block(statements);
  }

  /// Adds a goto to [label] including the break.
  ///
  /// Also inserts a comment describing the label if available.
  void addGoto(int label) {
    if (labelComments.containsKey(label)) {
      addStatement(new js.Comment("goto ${labelComments[label]}"));
    }
    addStatement(setGotoVariable(label));

    addBreak();
  }

  void addStatement(js.Statement node) {
    currentStatementBuffer.add(node);
  }

  void addExpressionStatement(js.Expression node) {
    addStatement(new js.ExpressionStatement(node));
  }

  /// True if there is an await or yield in [node] or some subexpression.
  bool shouldTransform(js.Node node) {
    return analysis.hasAwaitOrYield.contains(node);
  }

  void unsupported(js.Node node) {
    throw new UnsupportedError(
        "Node $node cannot be transformed by the await-sync transformer");
  }

  void unreachable(js.Node node) {
    diagnosticListener.internalError(
        spannable, "Internal error, trying to visit $node");
  }

  visitStatement(js.Statement node) {
    node.accept(this);
  }

  /// Visits [node] to ensure its sideeffects are performed, but throwing away
  /// the result.
  ///
  /// If the return value of visiting [node] is an expression guaranteed to have
  /// no side effect, it is dropped.
  void visitExpressionIgnoreResult(js.Expression node) {
    js.Expression result = node.accept(this);
    if (!(result is js.Literal || result is js.VariableUse)) {
      addExpressionStatement(result);
    }
  }

  js.Expression visitExpression(js.Expression node) {
    return node.accept(this);
  }


  /// Calls [fn] with the value of evaluating [node1] and [node2].
  ///
  /// Both nodes are evaluated in order.
  ///
  /// If node2 must be transformed (see [shouldTransform]), then the evaluation
  /// of node1 is added to the current statement-list and the result is stored
  /// in a temporary variable. The evaluation of node2 is then free to emit
  /// statements without affecting the result of node1.
  ///
  /// This is necessary, because await or yield expressions have to emit
  /// statements, and these statements could affect the value of node1.
  ///
  /// For example:
  ///
  /// - _storeIfNecessary(someLiteral) returns someLiteral.
  /// - _storeIfNecessary(someVariable)
  ///   inserts: var tempX = someVariable
  ///   returns: tempX
  ///   where tempX is a fresh temporary variable.
  js.Expression _storeIfNecessary(js.Expression result) {
    // Note that RegExes, js.ArrayInitializer and js.ObjectInitializer are not
    // [js.Literal]s.
    if (result is js.Literal) return result;
    js.Expression tempVar = useTempVar(allocateTempVar());
    addExpressionStatement(new js.Assignment(tempVar, result));
    return tempVar;
  }

  withExpression(js.Expression node, fn(js.Expression result), {bool store}) {
    int oldTempVarIndex = currentTempVarIndex;
    js.Expression visited = visitExpression(node);
    if (store) {
      visited = _storeIfNecessary(visited);
    }
    var result = fn(visited);
    currentTempVarIndex = oldTempVarIndex;
    return result;
  }

  /// Calls [fn] with the value of evaluating [node1] and [node2].
  ///
  /// If `shouldTransform(node2)` the first expression is stored in a temporary
  /// variable.
  ///
  /// This is because node1 must be evaluated before visiting node2,
  /// because the evaluation of an await or yield cannot be expressed as
  /// an expression, visiting node2 it will output statements that
  /// might have an influence on the value of node1.
  withExpression2(js.Expression node1, js.Expression node2,
      fn(js.Expression result1, js.Expression result2)) {
    int oldTempVarIndex = currentTempVarIndex;
    js.Expression r1 = visitExpression(node1);
    if (shouldTransform(node2)) {
      r1 = _storeIfNecessary(r1);
    }
    js.Expression r2 = visitExpression(node2);
    var result = fn(r1, r2);
    currentTempVarIndex = oldTempVarIndex;
    return result;
  }

  /// Calls [fn] with the value of evaluating all [nodes].
  ///
  /// All results before the last node where `shouldTransform(node)` are stored
  /// in temporary variables.
  ///
  /// See more explanation on [withExpression2].
  ///
  /// If any of the nodes are null, they are ignored, and a null is passed to
  /// [fn] in that place.
  withExpressions(List<js.Expression> nodes, fn(List<js.Expression> results)) {
    int oldTempVarIndex = currentTempVarIndex;
    // Find last occurence of a 'transform' expression in [nodes].
    // All expressions before that must be stored in temp-vars.
    int lastTransformIndex = 0;
    for (int i = nodes.length - 1; i >= 0; --i) {
      if (nodes[i] == null) continue;
      if (shouldTransform(nodes[i])) {
        lastTransformIndex = i;
        break;
      }
    }
    List<js.Node> visited = nodes.take(lastTransformIndex).map((js.Node node) {
      return node == null ? null : _storeIfNecessary(visitExpression(node));
    }).toList();
    visited.addAll(nodes.skip(lastTransformIndex).map((js.Node node) {
      return node == null ? null : visitExpression(node);
    }));
    var result = fn(visited);
    currentTempVarIndex = oldTempVarIndex;
    return result;
  }

  /// Emits the return block that all returns should jump to (after going
  /// through all the enclosing finally blocks). The jump to here is made in
  /// [visitReturn].
  ///
  /// Returning from an async method calls the [thenHelper] with the result.
  /// (the result might have been stored in [returnValueName] by some finally
  /// block).
  ///
  /// Returning from a sync* function returns an [endOfIteration] marker.
  ///
  /// Returning from an async* function calls the [streamHelper] with an
  /// [endOfIteration] marker.
  void addExit() {
    if (analysis.hasExplicitReturns || isAsyncStar) {
      beginLabel(exitLabel);
    } else {
      addStatement(new js.Comment("implicit return"));
    }
    switch (async) {
      case const js.AsyncModifier.async():
        String returnValue =
            analysis.hasExplicitReturns ? returnValueName : "null";
        addStatement(js.js.statement(
            "return #thenHelper($returnValue, null, $completerName, null)", {
          "thenHelper": thenHelper
        }));
        break;
      case const js.AsyncModifier.syncStar():
        addStatement(new js.Return(new js.Call(endOfIteration, [])));
        break;
      case const js.AsyncModifier.asyncStar():
        addStatement(js.js.statement(
            "return #streamHelper(null, null, $controllerName, null)", {
          "streamHelper": streamHelper
        }));
        break;
      default:
        diagnosticListener.internalError(
            spannable, "Internal error, unexpected asyncmodifier $async");
    }
  }

  /// The initial call to [thenHelper]/[streamHelper].
  ///
  /// There is no value to await/yield, so the first argument is `null` and
  /// also the errorCallback is `null`.
  ///
  /// Returns the [Future]/[Stream] coming from [completerName]/
  /// [controllerName].
  js.Statement generateInitializer() {
    if (isAsync) {
      return js.js.statement(
          "return #thenHelper(null, $helperName, $completerName, null);", {
        "thenHelper": thenHelper
      });
    } else if (isAsyncStar) {
      return js.js.statement(
          "return #streamOfController($controllerName);", {
        "streamOfController": streamOfController
      });
    } else {
      throw diagnosticListener.internalError(
          spannable, "Unexpected asyncModifier: $async");
    }
  }

  /// Rewrites an async/sync*/async* function to a normal Javascript function.
  ///
  /// The control flow is flattened by simulating 'goto' using a switch in a
  /// loop and a state variable [gotoName] inside a helper-function that can be
  /// called back by [thenHelper]/[streamHelper]/the [Iterator].
  ///
  /// Local variables are hoisted outside the helper.
  ///
  /// Awaits in async/async* are translated to code that remembers the current
  /// location (so the function can resume from where it was) followed by a call
  /// to the [thenHelper]. The helper sets up the waiting for the awaited value
  /// and returns a future which is immediately returned by the translated
  /// await.
  /// Yields in async* are translated to a call to the [streamHelper]. They,
  /// too, need to be prepared to be interrupted in case the stream is paused or
  /// canceled. (Currently we always suspend - this is different from the spec,
  /// see `streamHelper` in `js_helper.dart`).
  ///
  /// Yield/yield* in a sync* function is translated to a return of the value,
  /// wrapped into a "IterationMarker" that signals the type (yield or yield*).
  /// Sync* functions are executed on demand (when the user requests a value) by
  /// the Iterable that knows how to handle these values.
  ///
  /// Simplified examples (not the exact translation, but intended to show the
  /// ideas):
  ///
  /// function (x, y, z) async {
  ///   var p = await foo();
  ///   return bar(p);
  /// }
  ///
  /// Becomes:
  ///
  /// function(x, y, z) {
  ///   var goto = 0, returnValue, completer = new Completer(), p;
  ///   function helper(result) {
  ///     while (true) {
  ///       switch (goto) {
  ///         case 0:
  ///           goto = 1 // Remember where to continue when the future succeeds.
  ///           return thenHelper(foo(), helper, completer, null);
  ///         case 1:
  ///           p = result;
  ///           returnValue = bar(p);
  ///           goto = 2;
  ///           break;
  ///         case 2:
  ///           return thenHelper(returnValue, null, completer, null)
  ///       }
  ///     }
  ///     return thenHelper(null, helper, completer, null);
  ///   }
  /// }
  ///
  /// Try/catch is implemented by maintaining [handlerName] to contain the label
  /// of the current handler. The switch is nested inside a try/catch that will
  /// redirect the flow to the current handler.
  ///
  /// A `finally` clause is compiled similar to normal code, with the additional
  /// complexity that `finally` clauses need to know where to jump to after the
  /// clause is done. In the translation, each flow-path that enters a `finally`
  /// sets up the variable [nextName] with a stack of finally-blocks and a final
  /// jump-target (exit, catch, ...).
  ///
  /// function (x, y, z) async {
  ///   try {
  ///     try {
  ///       throw "error";
  ///     } finally {
  ///       finalize1();
  ///     }
  ///   } catch (e) {
  ///     handle(e);
  ///   } finally {
  ///     finalize2();
  ///   }
  /// }
  ///
  /// Translates into (besides the fact that structures not containing
  /// await/yield/yield* are left intact):
  ///
  /// function(x, y, z) {
  ///   var goto = 0;
  ///   var returnValue;
  ///   var completer = new Completer();
  ///   var handler = null;
  ///   var p;
  ///   // The result can be either the result of an awaited future, or an
  ///   // error if the future completed with an error.
  ///   function helper(result) {
  ///     while (true) {
  ///       try {
  ///         switch (goto) {
  ///           case 0:
  ///             handler = 4; // The outer catch-handler
  ///             handler = 1; // The inner (implicit) catch-handler
  ///             throw "error";
  ///             next = [3];
  ///             // After the finally (2) continue normally after the try.
  ///             goto = 2;
  ///             break;
  ///           case 1: // (implicit) catch handler for inner try.
  ///             next = [3]; // destination after the finally.
  ///             // fall-though to the finally handler.
  ///           case 2: // finally for inner try
  ///             handler = 4; // catch-handler for outer try.
  ///             finalize1();
  ///             goto = next.pop();
  ///             break;
  ///           case 3: // exiting inner try.
  ///             next = [6];
  ///             goto = 5; // finally handler for outer try.
  ///             break;
  ///           case 4: // catch handler for outer try.
  ///             e = result;
  ///             handle(e);
  ///             // Fall through to finally.
  ///           case 5: // finally handler for outer try.
  ///             handler = null;
  ///             finalize2();
  ///             goto = next.pop();
  ///             break;
  ///           case 6: // Exiting outer try.
  ///           case 7: // return
  ///             return thenHelper(returnValue, null, completer, null);
  ///         }
  ///       } catch (error) {
  ///         result = error;
  ///         goto = handler;
  ///       }
  ///     }
  ///     return thenHelper(null, helper, completer, null);
  ///   }
  /// }
  ///
  @override
  js.Expression visitFun(js.Fun node) {
    if (isSync) return node;

    beginLabel(newLabel("Function start"));
    // AsyncStar needs a returnlabel for its handling of cancelation. See
    // [visitDartYield].
    exitLabel =
        analysis.hasExplicitReturns || isAsyncStar ? newLabel("return") : null;
    js.Statement body = node.body;
    targetsAndTries.add(node);
    visitStatement(body);
    targetsAndTries.removeLast();
    addExit();

    List<js.SwitchClause> clauses = labelledParts.keys.map((label) {
      return new js.Case(js.number(label), new js.Block(labelledParts[label]));
    }).toList();
    js.Statement helperBody =
        new js.Switch(new js.VariableUse(gotoName), clauses);
    if (hasJumpThoughOuterLabel) {
      helperBody = js.js.statement("$outerLabelName: #", [helperBody]);
    }
    if (hasTryBlocks) {
      helperBody = js.js.statement("""
          try {
            #body
          } catch ($errorName){
            if ($handlerName === null)
              throw $errorName;
            $resultName = $errorName;
            $gotoName = $handlerName;
          }""", {"body": helperBody});
    }
    List<js.VariableInitialization> inits = <js.VariableInitialization>[];

    js.VariableInitialization makeInit(String name, js.Expression initValue) {
      return new js.VariableInitialization(
          new js.VariableDeclaration(name), initValue);
    }

    inits.add(makeInit(gotoName, js.number(0)));
    if (isAsync) {
      inits.add(makeInit(completerName, new js.New(newCompleter, [])));
    } else if (isAsyncStar) {
      inits.add(makeInit(controllerName,
          new js.Call(newController, [new js.VariableUse(helperName)])));
    }
    if (hasTryBlocks) {
      inits.add(makeInit(handlerName, new js.LiteralNull()));
    }
    if (hasJumpThroughFinally || analysis.hasYield) {
      inits.add(makeInit(nextName, null));
    }
    if (analysis.hasExplicitReturns && isAsync) {
      inits.add(makeInit(returnValueName, null));
    }
    if (analysis.hasThis && !isSyncStar) {
      // Sync* functions must remember `this` on the level of the outer
      // function.
      inits.add(makeInit(selfName, new js.This()));
    }
    inits.addAll(localVariables.map((js.VariableDeclaration decl) {
      return new js.VariableInitialization(decl, null);
    }));
    inits.addAll(new Iterable.generate(tempVarHighWaterMark,
        (int i) => makeInit(useTempVar(i + 1).name, null)));
    js.VariableDeclarationList varDecl = new js.VariableDeclarationList(inits);
    if (isSyncStar) {
      return js.js("""
          function (#params) {
            if (#needsThis)
              var $selfName = this;
            return new #newIterable(function () {
              #varDecl;
              return function $helperName($resultName) {
                while (true)
                  #helperBody;
              };
            });
          }
          """, {
        "params": node.params,
        "needsThis": analysis.hasThis,
        "helperBody": helperBody,
        "varDecl": varDecl,
        "newIterable": newIterable
      });
    }
    return js.js("""
        function (#params) {
          #varDecl;
          function $helperName($resultName) {
            while (true)
              #helperBody;
          }
          #init;
        }""", {
      "params": node.params,
      "helperBody": helperBody,
      "varDecl": varDecl,
      "init": generateInitializer()
    });
  }

  @override
  js.Expression visitAccess(js.PropertyAccess node) {
    return withExpression2(node.receiver, node.selector,
        (receiver, selector) => new js.PropertyAccess(receiver, selector));
  }

  @override
  js.Expression visitArrayHole(js.ArrayHole node) {
    return node;
  }

  @override
  js.Expression visitArrayInitializer(js.ArrayInitializer node) {
    return withExpressions(node.elements, (elements) {
      return new js.ArrayInitializer(elements);
    });
  }

  @override
  js.Expression visitAssignment(js.Assignment node) {
    if (!shouldTransform(node)) {
      return new js.Assignment.compound(visitExpression(node.leftHandSide),
          node.op, visitExpression(node.value));
    }
    js.Expression leftHandSide = node.leftHandSide;
    if (leftHandSide is js.VariableUse) {
      return withExpression(node.value, (js.Expression value) {
        return new js.Assignment(leftHandSide, value);
      }, store: false);
    } else if (leftHandSide is js.PropertyAccess) {
      return withExpressions([
        leftHandSide.receiver,
        leftHandSide.selector,
        node.value
      ], (evaluated) {
        return new js.Assignment.compound(
            new js.PropertyAccess(evaluated[0], evaluated[1]), node.op,
            evaluated[2]);
      });
    } else {
      throw "Unexpected assignment left hand side $leftHandSide";
    }
  }

  /// An await is translated to a call to [thenHelper]/[streamHelper].
  ///
  /// See the comments of [visitFun] for an example.
  @override
  js.Expression visitAwait(js.Await node) {
    assert(isAsync || isAsyncStar);
    int afterAwait = newLabel("returning from await.");
    withExpression(node.expression, (js.Expression value) {
      addStatement(setGotoVariable(afterAwait));
      js.Expression errorCallback = errorHandlerLabels.isEmpty
          ? new js.LiteralNull()
          : js.js("""
            function($errorName) {
              $gotoName = #currentHandler;
              $helperName($errorName);
            }""", {"currentHandler": currentErrorHandler});

      addStatement(js.js.statement("""
          return #thenHelper(#value,
                             $helperName,
                             ${isAsync ? completerName : controllerName},
                             #errorCallback);
          """, {
        "thenHelper": isAsync ? thenHelper : streamHelper,
        "value": value,
        "errorCallback": errorCallback
      }));
    }, store: false);
    beginLabel(afterAwait);
    return new js.VariableUse(resultName);
  }

  /// Checks if [node] is the variable named [resultName].
  ///
  /// [resultName] is used to hold the result of a transformed computation
  /// for example the result of awaiting, or the result of a conditional or
  /// short-circuiting expression.
  /// If the subexpression of some transformed node already is transformed and
  /// visiting it returns [resultName], it is not redundantly assigned to itself
  /// again.
  bool isResult(js.Expression node) {
    return node is js.VariableUse && node.name == resultName;
  }

  @override
  js.Expression visitBinary(js.Binary node) {
    if (shouldTransform(node.right) && (node.op == "||" || node.op == "&&")) {
      int thenLabel = newLabel("then");
      int joinLabel = newLabel("join");
      withExpression(node.left, (js.Expression left) {
        js.Statement assignLeft = isResult(left)
            ? new js.Block.empty()
            : new js.ExpressionStatement(
                new js.Assignment(new js.VariableUse(resultName), left));
        if (node.op == "||") {
          addStatement(new js.If(left, gotoAndBreak(thenLabel), assignLeft));
        } else {
          assert(node.op == "&&");
          addStatement(new js.If(left, assignLeft, gotoAndBreak(thenLabel)));
        }
      }, store: true);
      addGoto(joinLabel);
      beginLabel(thenLabel);
      withExpression(node.right, (js.Expression value) {
        if (!isResult(value)) {
          addExpressionStatement(
              new js.Assignment(new js.VariableUse(resultName), value));
        }
      }, store: false);
      beginLabel(joinLabel);
      return new js.VariableUse(resultName);
    }

    return withExpression2(node.left, node.right,
        (left, right) => new js.Binary(node.op, left, right));
  }

  @override
  void visitBlock(js.Block node) {
    for (js.Statement statement in node.statements) {
      visitStatement(statement);
    }
  }

  @override
  void visitBreak(js.Break node) {
    js.Node target = analysis.targets[node];
    if (!shouldTransform(target)) {
      addStatement(node);
      return;
    }
    translateJump(target, breakLabels[target]);
  }

  @override
  js.Expression visitCall(js.Call node) {
    bool storeTarget = node.arguments.any(shouldTransform);
    return withExpression(node.target, (target) {
      return withExpressions(node.arguments, (List<js.Expression> arguments) {
        return new js.Call(target, arguments);
      });
    }, store: storeTarget);
  }

  @override
  void visitCase(js.Case node) {
    return unreachable(node);
  }

  @override
  void visitCatch(js.Catch node) {
    return unreachable(node);
  }

  @override
  void visitComment(js.Comment node) {
    addStatement(node);
  }

  @override
  js.Expression visitConditional(js.Conditional node) {
    if (!shouldTransform(node.then) && !shouldTransform(node.otherwise)) {
      return withExpression(node.condition, (js.Expression condition) {
        return new js.Conditional(condition, node.then, node.otherwise);
      });
    }
    int thenLabel = newLabel("then");
    int joinLabel = newLabel("join");
    int elseLabel = newLabel("else");
    withExpression(node.condition, (js.Expression condition) {
      addExpressionStatement(new js.Assignment(new js.VariableUse(gotoName),
          new js.Conditional(
              condition, js.number(thenLabel), js.number(elseLabel))));
    }, store: false);
    addBreak();
    beginLabel(thenLabel);
    withExpression(node.then, (js.Expression value) {
      if (!isResult(value)) {
        addExpressionStatement(
            new js.Assignment(new js.VariableUse(resultName), value));
      }
    }, store: false);
    addGoto(joinLabel);
    beginLabel(elseLabel);
    withExpression(node.otherwise, (js.Expression value) {
      if (!isResult(value)) {
        addExpressionStatement(
            new js.Assignment(new js.VariableUse(resultName), value));
      }
    }, store: false);
    beginLabel(joinLabel);
    return new js.VariableUse(resultName);
  }

  @override
  void visitContinue(js.Continue node) {
    js.Node target = analysis.targets[node];
    if (!shouldTransform(target)) {
      addStatement(node);
      return;
    }
    translateJump(target, continueLabels[target]);
  }

  /// Emits a break statement that exits the big switch statement.
  void addBreak() {
    if (insideUntranslatedBreakable) {
      hasJumpThoughOuterLabel = true;
      addStatement(new js.Break(outerLabelName));
    } else {
      addStatement(new js.Break(null));
    }
  }

  /// Common code for handling break, continue, return.
  ///
  /// It is necessary to run all nesting finally-handlers between the jump and
  /// the target. For that [nextName] is used as a stack of places to go.
  ///
  /// See also [visitFun].
  void translateJump(js.Node target, int targetLabel) {
    // Compute a stack of all the 'finally' nodes that must be visited before
    // the jump.
    // The bottom of the stack is the label where the jump goes to.
    List<int> jumpStack = new List<int>();
    for (js.Node node in targetsAndTries.reversed) {
      if (node is js.Try) {
        assert(node.finallyPart != null);
        jumpStack.add(finallyLabels[node]);
      } else if (node == target) {
        jumpStack.add(targetLabel);
        break;
      }
      // Ignore other nodes.
    }
    jumpStack = jumpStack.reversed.toList();
    // As the program jumps directly to the top of the stack, it is taken off
    // now.
    int firstTarget = jumpStack.removeLast();
    if (jumpStack.isNotEmpty) {
      hasJumpThroughFinally = true;
      js.Expression jsJumpStack = new js.ArrayInitializer(
          jumpStack.map((int label) => js.number(label)).toList());
      addStatement(js.js.statement("$nextName = #", [jsJumpStack]));
    }
    addGoto(firstTarget);
  }

  @override
  void visitDefault(js.Default node) => unreachable(node);

  @override
  void visitDo(js.Do node) {
    if (!shouldTransform(node)) {
      bool oldInsideUntranslatedBreakable = insideUntranslatedBreakable;
      insideUntranslatedBreakable = true;
      withExpression(node.condition, (js.Expression condition) {
        addStatement(new js.Do(translateInBlock(node.body), condition));
      }, store: false);
      insideUntranslatedBreakable = oldInsideUntranslatedBreakable;
      return;
    }
    int startLabel = newLabel("do body");

    int continueLabel = newLabel("do condition");
    continueLabels[node] = continueLabel;

    int afterLabel = newLabel("after do");
    breakLabels[node] = afterLabel;

    beginLabel(startLabel);

    targetsAndTries.add(node);
    visitStatement(node.body);
    targetsAndTries.removeLast();

    beginLabel(continueLabel);
    withExpression(node.condition, (js.Expression condition) {
      addStatement(new js.If.noElse(condition, gotoAndBreak(startLabel)));
    }, store: false);
    beginLabel(afterLabel);
  }

  @override
  void visitEmptyStatement(js.EmptyStatement node) {
    addStatement(node);
  }

  void visitExpressionInStatementContext(js.Expression node) {
    if (node is js.VariableDeclarationList) {
      // Treat js.VariableDeclarationList as a statement.
      visitVariableDeclarationList(node);
    } else {
      visitExpressionIgnoreResult(node);
    }
  }

  @override
  void visitExpressionStatement(js.ExpressionStatement node) {
    visitExpressionInStatementContext(node.expression);
  }

  @override
  void visitFor(js.For node) {
    if (!shouldTransform(node)) {
      bool oldInsideUntranslated = insideUntranslatedBreakable;
      insideUntranslatedBreakable = true;
      // Note that node.init, node.condition, node.update all can be null, but
      // withExpressions handles that.
      withExpressions([
        node.init,
        node.condition,
        node.update
      ], (List<js.Expression> transformed) {
        addStatement(new js.For(transformed[0], transformed[1], transformed[2],
            translateInBlock(node.body)));
      });
      insideUntranslatedBreakable = oldInsideUntranslated;
      return;
    }

    if (node.init != null) {
      visitExpressionInStatementContext(node.init);
    }
    int startLabel = newLabel("for condition");
    // If there is no update, continuing the loop is the same as going to the
    // start.
    int continueLabel =
        (node.update == null) ? startLabel : newLabel("for update");
    continueLabels[node] = continueLabel;
    int afterLabel = newLabel("after for");
    breakLabels[node] = afterLabel;
    beginLabel(startLabel);
    js.Expression condition = node.condition;
    if (condition == null ||
        (condition is js.LiteralBool && condition.value == true)) {
      addStatement(new js.Comment("trivial condition"));
    } else {
      withExpression(condition, (js.Expression condition) {
        addStatement(new js.If.noElse(
            new js.Prefix("!", condition), gotoAndBreak(afterLabel)));
      }, store: false);
    }
    targetsAndTries.add(node);
    visitStatement(node.body);
    targetsAndTries.removeLast();
    if (node.update != null) {
      beginLabel(continueLabel);
      visitExpressionIgnoreResult(node.update);
    }
    addGoto(startLabel);
    beginLabel(afterLabel);
  }

  @override
  void visitForIn(js.ForIn node) {
    // The dart output currently never uses for-in loops.
    throw "Javascript for-in not implemented yet in the await transformation";
  }

  @override
  void visitFunctionDeclaration(js.FunctionDeclaration node) {
    unsupported(node);
  }

  // Only used for code where `!shouldTransform(node)`.
  js.Block translateInBlock(js.Statement node) {
    assert(!shouldTransform(node));
    List<js.Statement> oldBuffer = currentStatementBuffer;
    currentStatementBuffer = new List();
    List<js.Statement> resultBuffer = currentStatementBuffer;
    visitStatement(node);
    currentStatementBuffer = oldBuffer;
    return new js.Block(resultBuffer);
  }

  @override
  void visitIf(js.If node) {
    if (!shouldTransform(node.then) && !shouldTransform(node.otherwise)) {
      withExpression(node.condition, (js.Expression condition) {
        addStatement(new js.If(condition, translateInBlock(node.then),
            translateInBlock(node.otherwise)));
      }, store: false);
      return;
    }
    int thenLabel = newLabel("then");
    int joinLabel = newLabel("join");
    int elseLabel =
        node.otherwise is js.EmptyStatement ? joinLabel : newLabel("else");

    withExpression(node.condition, (js.Expression condition) {
      addExpressionStatement(
          new js.Assignment(
              new js.VariableUse(gotoName),
              new js.Conditional(
                  condition,
                  js.number(thenLabel),
                  js.number(elseLabel))));
    }, store: false);
    addBreak();
    beginLabel(thenLabel);
    visitStatement(node.then);
    if (node.otherwise is! js.EmptyStatement) {
      addGoto(joinLabel);
      beginLabel(elseLabel);
      visitStatement(node.otherwise);
    }
    beginLabel(joinLabel);
  }

  @override
  visitInterpolatedExpression(js.InterpolatedExpression node) {
    return unsupported(node);
  }

  @override
  visitInterpolatedLiteral(js.InterpolatedLiteral node) => unsupported(node);

  @override
  visitInterpolatedParameter(js.InterpolatedParameter node) {
    return unsupported(node);
  }

  @override
  visitInterpolatedSelector(js.InterpolatedSelector node) {
    return unsupported(node);
  }

  @override
  visitInterpolatedStatement(js.InterpolatedStatement node) {
    return unsupported(node);
  }

  @override
  void visitLabeledStatement(js.LabeledStatement node) {
    if (!shouldTransform(node)) {
      addStatement(
          new js.LabeledStatement(node.label, translateInBlock(node.body)));
      return;
    }
    int breakLabel = newLabel("break ${node.label}");
    int continueLabel = newLabel("continue ${node.label}");
    breakLabels[node] = breakLabel;
    continueLabels[node] = continueLabel;

    beginLabel(continueLabel);
    targetsAndTries.add(node);
    visitStatement(node.body);
    targetsAndTries.removeLast();
    beginLabel(breakLabel);
  }

  @override
  js.Expression visitLiteralBool(js.LiteralBool node) => node;

  @override
  visitLiteralExpression(js.LiteralExpression node) => unsupported(node);

  @override
  js.Expression visitLiteralNull(js.LiteralNull node) => node;

  @override
  js.Expression visitLiteralNumber(js.LiteralNumber node) => node;

  @override
  visitLiteralStatement(js.LiteralStatement node) => unsupported(node);

  @override
  js.Expression visitLiteralString(js.LiteralString node) => node;

  @override
  visitNamedFunction(js.NamedFunction node) {
    unsupported(node);
  }

  @override
  js.Expression visitNew(js.New node) {
    bool storeTarget = node.arguments.any(shouldTransform);
    return withExpression(node.target, (target) {
      return withExpressions(node.arguments, (List<js.Expression> arguments) {
        return new js.New(target, arguments);
      });
    }, store: storeTarget);
  }

  @override
  js.Expression visitObjectInitializer(js.ObjectInitializer node) {
    return withExpressions(
        node.properties.map((js.Property property) => property.value).toList(),
        (List<js.Node> values) {
      List<js.Property> properties = new List.generate(values.length, (int i) {
        return new js.Property(node.properties[i].name, values[i]);
      });
      return new js.ObjectInitializer(properties);
    });
  }

  @override
  visitParameter(js.Parameter node) => unreachable(node);

  @override
  js.Expression visitPostfix(js.Postfix node) {
    if (node.op == "++" || node.op == "--") {
      js.Expression argument = node.argument;
      if (argument is js.VariableUse) {
        return new js.Postfix(node.op, argument);
      } else if (argument is js.PropertyAccess) {
        return withExpression2(argument.receiver, argument.selector,
            (receiver, selector) {
          return new js.Postfix(
              node.op, new js.PropertyAccess(receiver, selector));
        });
      } else {
        throw "Unexpected postfix ${node.op} "
            "operator argument ${node.argument}";
      }
    }
    return withExpression(node.argument,
        (js.Expression argument) => new js.Postfix(node.op, argument),
        store: false);
  }

  @override
  js.Expression visitPrefix(js.Prefix node) {
    if (node.op == "++" || node.op == "--") {
      js.Expression argument = node.argument;
      if (argument is js.VariableUse) {
        return new js.Prefix(node.op, argument);
      } else if (argument is js.PropertyAccess) {
        return withExpression2(argument.receiver, argument.selector,
            (receiver, selector) {
          return new js.Prefix(
              node.op, new js.PropertyAccess(receiver, selector));
        });
      } else {
        throw "Unexpected prefix ${node.op} operator "
            "argument ${node.argument}";
      }
    }
    return withExpression(node.argument,
        (js.Expression argument) => new js.Prefix(node.op, argument),
        store: false);
  }

  @override
  visitProgram(js.Program node) => unsupported(node);

  @override
  js.Property visitProperty(js.Property node) {
    return withExpression(
        node.value, (js.Expression value) => new js.Property(node.name, value),
        store: false);
  }

  @override
  js.Expression visitRegExpLiteral(js.RegExpLiteral node) => node;

  @override
  void visitReturn(js.Return node) {
    assert(node.value == null || !isSyncStar && !isAsyncStar);
    js.Node target = analysis.targets[node];
    if (node.value != null) {
      withExpression(node.value, (js.Expression value) {
        addStatement(js.js.statement("$returnValueName = #", [value]));
      }, store: false);
    }
    translateJump(target, exitLabel);
  }

  @override
  void visitSwitch(js.Switch node) {
    if (!node.cases.any(shouldTransform)) {
      // If only the key has an await, translation can be simplified.
      bool oldInsideUntranslated = insideUntranslatedBreakable;
      insideUntranslatedBreakable = true;
      withExpression(node.key, (js.Expression key) {
        List<js.SwitchClause> cases = node.cases.map((js.SwitchClause clause) {
          if (clause is js.Case) {
            return new js.Case(
                clause.expression, translateInBlock(clause.body));
          } else if (clause is js.Default) {
            return new js.Default(translateInBlock(clause.body));
          }
        }).toList();
        addStatement(new js.Switch(key, cases));
      }, store: false);
      insideUntranslatedBreakable = oldInsideUntranslated;
      return;
    }
    int before = newLabel("switch");
    int after = newLabel("after switch");
    breakLabels[node] = after;

    beginLabel(before);
    List<int> labels = new List<int>(node.cases.length);

    bool anyCaseExpressionTransformed = node.cases.any(
        (js.SwitchClause x) => x is js.Case && shouldTransform(x.expression));
    if (anyCaseExpressionTransformed) {
      int defaultIndex = null; // Null means no default was found.
      // If there is an await in one of the keys, a chain of ifs has to be used.

      withExpression(node.key, (js.Expression key) {
        int i = 0;
        for (js.SwitchClause clause in node.cases) {
          if (clause is js.Default) {
            // The goto for the default case is added after all non-default
            // clauses have been handled.
            defaultIndex = i;
            labels[i] = newLabel("default");
            continue;
          } else if (clause is js.Case) {
            labels[i] = newLabel("case");
            withExpression(clause.expression, (expression) {
              addStatement(new js.If.noElse(
                  new js.Binary("===", key, expression),
                  gotoAndBreak(labels[i])));
            }, store: false);
          }
          i++;
        }
      }, store: true);

      if (defaultIndex == null) {
        addGoto(after);
      } else {
        addGoto(labels[defaultIndex]);
      }
    } else {
      bool hasDefault = false;
      int i = 0;
      List<js.SwitchClause> clauses = new List<js.SwitchClause>();
      for (js.SwitchClause clause in node.cases) {
        if (clause is js.Case) {
          labels[i] = newLabel("case");
          clauses.add(new js.Case(clause.expression, gotoAndBreak(labels[i])));
        } else if (i is js.Default) {
          labels[i] = newLabel("default");
          clauses.add(new js.Default(gotoAndBreak(labels[i])));
          hasDefault = true;
        } else {
          diagnosticListener.internalError(
              spannable, "Unknown clause type $clause");
        }
        i++;
      }
      withExpression(node.key, (js.Expression key) {
        addStatement(new js.Switch(key, clauses));
      }, store: false);
      if (!hasDefault) {
        addGoto(after);
      }
    }

    targetsAndTries.add(node);
    for (int i = 0; i < labels.length; i++) {
      beginLabel(labels[i]);
      visitStatement(node.cases[i].body);
    }
    beginLabel(after);
    targetsAndTries.removeLast();
  }

  @override
  js.Expression visitThis(js.This node) {
    return new js.VariableUse(selfName);
  }

  @override
  void visitThrow(js.Throw node) {
    withExpression(node.expression, (js.Expression expression) {
      addStatement(new js.Throw(expression));
    }, store: false);
  }

  setErrorHandler() {
    addExpressionStatement(new js.Assignment(
        new js.VariableUse(handlerName), currentErrorHandler));
  }

  @override
  void visitTry(js.Try node) {
    if (!shouldTransform(node)) {
      js.Block body = translateInBlock(node.body);
      js.Catch catchPart = (node.catchPart == null)
          ? null
          : new js.Catch(node.catchPart.declaration,
              translateInBlock(node.catchPart.body));
      js.Block finallyPart = (node.finallyPart == null)
          ? null
          : translateInBlock(node.finallyPart);
      addStatement(new js.Try(body, catchPart, finallyPart));
      return;
    }
    hasTryBlocks = true;
    int handlerLabel = newLabel("catch");
    int finallyLabel = newLabel("finally");
    int afterFinallyLabel = newLabel("after finally");
    errorHandlerLabels.add(handlerLabel);
    // Set the error handler here. It must be cleared on every path out;
    // normal and error exit.
    setErrorHandler();
    if (node.finallyPart != null) {
      finallyLabels[node] = finallyLabel;
      targetsAndTries.add(node);
    }
    visitStatement(node.body);
    errorHandlerLabels.removeLast();
    addStatement(
        js.js.statement("$nextName = [#];", [js.number(afterFinallyLabel)]));
    if (node.finallyPart == null) {
      setErrorHandler();
      addGoto(afterFinallyLabel);
    } else {
      // The handler is set as the first thing in the finally block.
      addGoto(finallyLabel);
    }
    beginLabel(handlerLabel);
    if (node.catchPart != null) {
      setErrorHandler();
      // The catch declaration name can shadow outer variables, so a fresh name
      // is needed to avoid collisions.  See Ecma 262, 3rd edition,
      // section 12.14.
      String errorRename = freshName(node.catchPart.declaration.name);
      localVariables.add(new js.VariableDeclaration(errorRename));
      variableRenamings
          .add(new Pair(node.catchPart.declaration.name, errorRename));
      addExpressionStatement(new js.Assignment(
          new js.VariableUse(errorRename), new js.VariableUse(resultName)));
      visitStatement(node.catchPart.body);
      variableRenamings.removeLast();
    }
    if (node.finallyPart != null) {
      targetsAndTries.removeLast();
      setErrorHandler();
      // This belongs to the catch-part, but is only needed if there is a
      // `finally`. Therefore it is in this branch.
      // This is needed even if there is no explicit catch-branch, because
      // if an exception is raised the finally part has to be run.
      addStatement(
          js.js.statement("$nextName = [#];", [js.number(afterFinallyLabel)]));
      beginLabel(finallyLabel);
      setErrorHandler();
      visitStatement(node.finallyPart);
      addStatement(new js.Comment("// goto the next finally handler"));
      addStatement(js.js.statement("$gotoName = $nextName.pop();"));
      addBreak();
    }
    beginLabel(afterFinallyLabel);
  }

  @override
  visitVariableDeclaration(js.VariableDeclaration node) {
    unreachable(node);
  }

  @override
  void visitVariableDeclarationList(js.VariableDeclarationList node) {
    // Declaration of local variables is hoisted outside the helper but the
    // initialization is done here.
    for (js.VariableInitialization initialization in node.declarations) {
      js.VariableDeclaration declaration = initialization.declaration;
      localVariables.add(declaration);
      if (initialization.value != null) {
        withExpression(initialization.value, (js.Expression value) {
          addStatement(new js.ExpressionStatement(
              new js.Assignment(new js.VariableUse(declaration.name), value)));
        }, store: false);
      }
    }
  }

  @override
  void visitVariableInitialization(js.VariableInitialization node) {
    unreachable(node);
  }

  @override
  js.Expression visitVariableUse(js.VariableUse node) {
    Pair<String, String> renaming = variableRenamings.lastWhere(
        (Pair renaming) => renaming.a == node.name, orElse: () => null);
    if (renaming == null) return node;
    return new js.VariableUse(renaming.b);
  }

  @override
  void visitWhile(js.While node) {
    if (!shouldTransform(node)) {
      bool oldInsideUntranslated = insideUntranslatedBreakable;
      insideUntranslatedBreakable = true;
      withExpression(node.condition, (js.Expression condition) {
        addStatement(new js.While(condition, translateInBlock(node.body)));
      }, store: false);
      insideUntranslatedBreakable = oldInsideUntranslated;
      return;
    }
    int continueLabel = newLabel("while condition");
    continueLabels[node] = continueLabel;
    beginLabel(continueLabel);

    int afterLabel = newLabel("after while");
    breakLabels[node] = afterLabel;
    js.Expression condition = node.condition;
    // If the condition is `true`, a test is not needed.
    if (!(condition is js.LiteralBool && condition.value == true)) {
      withExpression(node.condition, (js.Expression condition) {
        addStatement(new js.If.noElse(
            new js.Prefix("!", condition), gotoAndBreak(afterLabel)));
      }, store: false);
    }
    targetsAndTries.add(node);
    visitStatement(node.body);
    targetsAndTries.removeLast();
    addGoto(continueLabel);
    beginLabel(afterLabel);
  }

  /// Translates a yield/yield* in an sync*.
  ///
  /// `yield` in a sync* function just returns [value].
  /// `yield*` wraps [value] in a [yieldStarExpression] and returns it.
  void addSyncYield(js.DartYield node, js.Expression expression) {
    assert(isSyncStar);
    if (node.hasStar) {
      addStatement(
          new js.Return(new js.Call(yieldStarExpression, [expression])));
    } else {
      addStatement(new js.Return(expression));
    }
  }

  /// Translates a yield/yield* in an async* function.
  ///
  /// yield/yield* in an async* function is translated much like the `await` is
  /// translated in [visitAwait], only the object is wrapped in a
  /// [yieldExpression]/[yieldStarExpression] to let [streamHelper] distinguish.
  ///
  /// Because there is no Future that can fail (as there is in await) null is
  /// passed as the errorCallback.
  void addAsyncYield(js.DartYield node, js.Expression expression) {
    assert(isAsyncStar);
    // Find all the finally blocks that should be performed if the stream is
    // canceled during the yield.
    // At the bottom of the stack is the return label.
    List<int> enclosingFinallyLabels = <int>[exitLabel];
    enclosingFinallyLabels.addAll(targetsAndTries
        .where((js.Node node) => node is js.Try)
        .map((js.Try node) => finallyLabels[node]));
    int destinationOnCancel = enclosingFinallyLabels.removeLast();
    js.ArrayInitializer finallyListInitializer = new js.ArrayInitializer(
        enclosingFinallyLabels.map(js.number).toList());
    addStatement(js.js.statement("""
        return #streamHelper(#yieldExpression(#expression),
            $helperName, $controllerName, function () {
              if (#notEmptyFinallyList)
                $nextName = #finallyList;
              $gotoName = #destinationOnCancel;
              $helperName();
            });""", {
      "streamHelper": streamHelper,
      "yieldExpression": node.hasStar ? yieldStarExpression : yieldExpression,
      "expression": expression,
      "notEmptyFinallyList": enclosingFinallyLabels.isNotEmpty,
      "finallyList": finallyListInitializer,
      "destinationOnCancel": js.number(destinationOnCancel)
    }));
  }

  @override
  void visitDartYield(js.DartYield node) {
    assert(isSyncStar || isAsyncStar);
    int label = newLabel("after yield");
    // Don't do a break here for the goto, but instead a return in either
    // addSynYield or addAsyncYield.
    withExpression(node.expression, (js.Expression expression) {
      addStatement(setGotoVariable(label));
      if (isSyncStar) {
        addSyncYield(node, expression);
      } else {
        addAsyncYield(node, expression);
      }
    }, store: false);
    beginLabel(label);
  }
}

/// Finds out
///
/// - which expressions have yield or await nested in them.
/// - targets of jumps
/// - a set of used names.
/// - if any [This]-expressions are used.
class PreTranslationAnalysis extends js.NodeVisitor<bool> {
  Set<js.Node> hasAwaitOrYield = new Set<js.Node>();

  Map<js.Node, js.Node> targets = new Map<js.Node, js.Node>();
  List<js.Node> loopsAndSwitches = new List<js.Node>();
  List<js.LabeledStatement> labelledStatements =
      new List<js.LabeledStatement>();
  Set<String> usedNames = new Set<String>();

  bool hasExplicitReturns = false;

  bool hasThis = false;

  bool hasYield = false;

  // The function currently being analyzed.
  js.Fun currentFunction;

  // For error messages.
  final Function unsupported;

  PreTranslationAnalysis(void this.unsupported(js.Node node));

  bool visit(js.Node node) {
    bool containsAwait = node.accept(this);
    if (containsAwait) {
      hasAwaitOrYield.add(node);
    }
    return containsAwait;
  }

  analyze(js.Fun node) {
    currentFunction = node;
    node.params.forEach(visit);
    visit(node.body);
  }

  @override
  bool visitAccess(js.PropertyAccess node) {
    bool receiver = visit(node.receiver);
    bool selector = visit(node.selector);
    return receiver || selector;
  }

  @override
  bool visitArrayHole(js.ArrayHole node) {
    return false;
  }

  @override
  bool visitArrayInitializer(js.ArrayInitializer node) {
    bool containsAwait = false;
    for (js.Expression element in node.elements) {
      if (visit(element)) containsAwait = true;
    }
    return containsAwait;
  }

  @override
  bool visitAssignment(js.Assignment node) {
    bool leftHandSide = visit(node.leftHandSide);
    bool value = (node.value == null) ? false : visit(node.value);
    return leftHandSide || value;
  }

  @override
  bool visitAwait(js.Await node) {
    visit(node.expression);
    return true;
  }

  @override
  bool visitBinary(js.Binary node) {
    bool left = visit(node.left);
    bool right = visit(node.right);
    return left || right;
  }

  @override
  bool visitBlock(js.Block node) {
    bool containsAwait = false;
    for (js.Statement statement in node.statements) {
      if (visit(statement)) containsAwait = true;
    }
    return containsAwait;
  }

  @override
  bool visitBreak(js.Break node) {
    if (node.targetLabel != null) {
      targets[node] = labelledStatements.lastWhere(
          (js.LabeledStatement statement) {
        return statement.label == node.targetLabel;
      });
    } else {
      targets[node] = loopsAndSwitches.last;
    }
    return false;
  }

  @override
  bool visitCall(js.Call node) {
    bool containsAwait = visit(node.target);
    for (js.Expression argument in node.arguments) {
      if (visit(argument)) containsAwait = true;
    }
    return containsAwait;
  }

  @override
  bool visitCase(js.Case node) {
    bool expression = visit(node.expression);
    bool body = visit(node.body);
    return expression || body;
  }

  @override
  bool visitCatch(js.Catch node) {
    bool declaration = visit(node.declaration);
    bool body = visit(node.body);
    return declaration || body;
  }

  @override
  bool visitComment(js.Comment node) {
    return false;
  }

  @override
  bool visitConditional(js.Conditional node) {
    bool condition = visit(node.condition);
    bool then = visit(node.then);
    bool otherwise = visit(node.otherwise);
    return condition || then || otherwise;
  }

  @override
  bool visitContinue(js.Continue node) {
    if (node.targetLabel != null) {
      targets[node] = labelledStatements.lastWhere(
          (js.LabeledStatement stm) => stm.label == node.targetLabel);
    } else {
      targets[node] =
          loopsAndSwitches.lastWhere((js.Node node) => node is! js.Switch);
    }
    assert(() {
      js.Node target = targets[node];
      return target is js.Loop ||
          (target is js.LabeledStatement && target.body is js.Loop);
    });
    return false;
  }

  @override
  bool visitDefault(js.Default node) {
    return visit(node.body);
  }

  @override
  bool visitDo(js.Do node) {
    loopsAndSwitches.add(node);
    bool body = visit(node.body);
    bool condition = visit(node.condition);
    loopsAndSwitches.removeLast();
    return body || condition;
  }

  @override
  bool visitEmptyStatement(js.EmptyStatement node) {
    return false;
  }

  @override
  bool visitExpressionStatement(js.ExpressionStatement node) {
    return visit(node.expression);
  }

  @override
  bool visitFor(js.For node) {
    bool init = (node.init == null) ? false : visit(node.init);
    bool condition = (node.condition == null) ? false : visit(node.condition);
    bool update = (node.update == null) ? false : visit(node.update);
    loopsAndSwitches.add(node);
    bool body = visit(node.body);
    loopsAndSwitches.removeLast();
    return init || condition || update || body;
  }

  @override
  bool visitForIn(js.ForIn node) {
    bool object = visit(node.object);
    loopsAndSwitches.add(node);
    bool body = visit(node.body);
    loopsAndSwitches.removeLast();
    return object || body;
  }

  @override
  bool visitFun(js.Fun node) {
    return false;
  }

  @override
  bool visitFunctionDeclaration(js.FunctionDeclaration node) {
    return false;
  }

  @override
  bool visitIf(js.If node) {
    bool condition = visit(node.condition);
    bool then = visit(node.then);
    bool otherwise = visit(node.otherwise);
    return condition || then || otherwise;
  }

  @override
  bool visitInterpolatedExpression(js.InterpolatedExpression node) {
    return unsupported(node);
  }

  @override
  bool visitInterpolatedLiteral(js.InterpolatedLiteral node) {
    return unsupported(node);
  }

  @override
  bool visitInterpolatedParameter(js.InterpolatedParameter node) {
    return unsupported(node);
  }

  @override
  bool visitInterpolatedSelector(js.InterpolatedSelector node) {
    return unsupported(node);
  }

  @override
  bool visitInterpolatedStatement(js.InterpolatedStatement node) {
    return unsupported(node);
  }

  @override
  bool visitLabeledStatement(js.LabeledStatement node) {
    usedNames.add(node.label);
    labelledStatements.add(node);
    bool containsAwait = visit(node.body);
    labelledStatements.removeLast();
    return containsAwait;
  }

  @override
  bool visitLiteralBool(js.LiteralBool node) {
    return false;
  }

  @override
  bool visitLiteralExpression(js.LiteralExpression node) {
    return unsupported(node);
  }

  @override
  bool visitLiteralNull(js.LiteralNull node) {
    return false;
  }

  @override
  bool visitLiteralNumber(js.LiteralNumber node) {
    return false;
  }

  @override
  bool visitLiteralStatement(js.LiteralStatement node) {
    return unsupported(node);
  }

  @override
  bool visitLiteralString(js.LiteralString node) {
    return false;
  }

  @override
  bool visitNamedFunction(js.NamedFunction node) {
    return false;
  }

  @override
  bool visitNew(js.New node) {
    return visitCall(node);
  }

  @override
  bool visitObjectInitializer(js.ObjectInitializer node) {
    bool containsAwait = false;
    for (js.Property property in node.properties) {
      if (visit(property)) containsAwait = true;
    }
    return containsAwait;
  }

  @override
  bool visitParameter(js.Parameter node) {
    usedNames.add(node.name);
    return false;
  }

  @override
  bool visitPostfix(js.Postfix node) {
    return visit(node.argument);
  }

  @override
  bool visitPrefix(js.Prefix node) {
    return visit(node.argument);
  }

  @override
  bool visitProgram(js.Program node) {
    throw "Unexpected";
  }

  @override
  bool visitProperty(js.Property node) {
    return visit(node.value);
  }

  @override
  bool visitRegExpLiteral(js.RegExpLiteral node) {
    return false;
  }

  @override
  bool visitReturn(js.Return node) {
    hasExplicitReturns = true;
    targets[node] = currentFunction;
    if (node.value == null) return false;
    return visit(node.value);
  }

  @override
  bool visitSwitch(js.Switch node) {
    loopsAndSwitches.add(node);
    bool result = visit(node.key);
    for (js.SwitchClause clause in node.cases) {
      if (visit(clause)) result = true;
    }
    loopsAndSwitches.removeLast();
    return result;
  }

  @override
  bool visitThis(js.This node) {
    hasThis = true;
    return false;
  }

  @override
  bool visitThrow(js.Throw node) {
    return visit(node.expression);
  }

  @override
  bool visitTry(js.Try node) {
    bool body = visit(node.body);
    bool catchPart = (node.catchPart == null) ? false : visit(node.catchPart);
    bool finallyPart =
        (node.finallyPart == null) ? false : visit(node.finallyPart);
    return body || catchPart || finallyPart;
  }

  @override
  bool visitVariableDeclaration(js.VariableDeclaration node) {
    usedNames.add(node.name);
    return false;
  }

  @override
  bool visitVariableDeclarationList(js.VariableDeclarationList node) {
    bool result = false;
    for (js.VariableInitialization init in node.declarations) {
      if (visit(init)) result = true;
    }
    return result;
  }

  @override
  bool visitVariableInitialization(js.VariableInitialization node) {
    return visitAssignment(node);
  }

  @override
  bool visitVariableUse(js.VariableUse node) {
    usedNames.add(node.name);
    return false;
  }

  @override
  bool visitWhile(js.While node) {
    loopsAndSwitches.add(node);
    bool condition = visit(node.condition);
    bool body = visit(node.body);
    loopsAndSwitches.removeLast();
    return condition || body;
  }

  @override
  bool visitDartYield(js.DartYield node) {
    hasYield = true;
    visit(node.expression);
    return true;
  }
}