// Copyright (c) 2013, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of 'dart:async';

class _ZoneFunction<T extends Function> {
  final _Zone zone;
  final T function;
  const _ZoneFunction(this.zone, this.function);
}

/// A zone represents an environment that remains stable across asynchronous
/// calls.
///
/// All code is executed in the context of a zone,
/// available to the code as [Zone.current].
/// The initial `main` function runs in the context of
/// the default zone ([Zone.root]).
/// Code can be run in a different zone using either
///  [runZoned] or [runZonedGuarded] to create a new zone and run code in it,
/// or [Zone.run] to run code in the context of an existing zone
/// which may have been created earlier using [Zone.fork].
///
/// Developers can create a new zone that overrides some of the functionality of
/// an existing zone. For example, custom zones can replace or modify the
/// behavior of `print`, timers, microtasks or how uncaught errors are handled.
///
/// The [Zone] class is not subclassable, but users can provide custom zones by
/// forking an existing zone (usually [Zone.current]) with a [ZoneSpecification].
/// This is similar to creating a new class that extends the base `Zone` class
/// and that overrides some methods, except without actually creating a new
/// class. Instead the overriding methods are provided as functions that
/// explicitly take the equivalent of their own class, the "super" class and the
/// `this` object as parameters.
///
/// Asynchronous callbacks always run in the context of the zone where they were
/// scheduled. This is implemented using two steps:
/// 1. the callback is first registered using one of [registerCallback],
///   [registerUnaryCallback], or [registerBinaryCallback]. This allows the zone
///   to record that a callback exists and potentially modify it (by returning a
///   different callback). The code doing the registration (e.g., `Future.then`)
///   also remembers the current zone so that it can later run the callback in
///   that zone.
/// 2. At a later point the registered callback is run in the remembered zone,
///    using one of [run], [runUnary] or [runBinary].
///
/// This is all handled internally by the platform code and most users don't need
/// to worry about it. However, developers of new asynchronous operations,
/// provided by the underlying system, must follow the protocol to be zone
/// compatible.
///
/// For convenience, zones provide [bindCallback] (and the corresponding
/// [bindUnaryCallback] and [bindBinaryCallback]) to make it easier to respect
/// the zone contract: these functions first invoke the corresponding `register`
/// functions and then wrap the returned function so that it runs in the current
/// zone when it is later asynchronously invoked.
///
/// Similarly, zones provide [bindCallbackGuarded] (and the corresponding
/// [bindUnaryCallbackGuarded] and [bindBinaryCallbackGuarded]), when the
/// callback should be invoked through [Zone.runGuarded].
@vmIsolateUnsendable
abstract final class Zone {
  // Private constructor so that it is not possible instantiate a Zone class.
  Zone._();

  /// The root zone.
  ///
  /// All isolate entry functions (`main` or spawned functions) start running in
  /// the root zone (that is, [Zone.current] is identical to [Zone.root] when the
  /// entry function is called). If no custom zone is created, the rest of the
  /// program always runs in the root zone.
  ///
  /// The root zone implements the default behavior of all zone operations.
  /// Many methods, like [registerCallback] do the bare minimum required of the
  /// function, and are only provided as a hook for custom zones. Others, like
  /// [scheduleMicrotask], interact with the underlying system to implement the
  /// desired behavior.
  static const Zone root = _rootZone;

  /// The currently running zone.
  static _Zone _current = _rootZone;

  /// The zone that is currently active.
  static Zone get current => _current;

  /// Handles uncaught asynchronous errors.
  ///
  /// There are two kind of asynchronous errors that are handled by this
  /// function:
  /// 1. Uncaught errors that were thrown in asynchronous callbacks, for example,
  ///   a `throw` in the function passed to [Timer.run].
  /// 2. Asynchronous errors that are pushed through [Future] and [Stream]
  ///   chains, but for which nobody registered an error handler.
  ///   Most asynchronous classes, like [Future] or [Stream] push errors to their
  ///   listeners. Errors are propagated this way until either a listener handles
  ///   the error (for example with [Future.catchError]), or no listener is
  ///   available anymore. In the latter case, futures and streams invoke the
  ///   zone's [handleUncaughtError].
  ///
  /// By default, when handled by the root zone, uncaught asynchronous errors are
  /// treated like uncaught synchronous exceptions.
  void handleUncaughtError(Object error, StackTrace stackTrace);

  /// The parent zone of the this zone.
  ///
  /// Is `null` if `this` is the [root] zone.
  ///
  /// Zones are created by [fork] on an existing zone, or by [runZoned] which
  /// forks the [current] zone. The new zone's parent zone is the zone it was
  /// forked from.
  Zone? get parent;

  /// The error zone is responsible for dealing with uncaught errors.
  ///
  /// This is the closest parent zone of this zone that provides a
  /// [handleUncaughtError] method.
  ///
  /// Asynchronous errors in futures never cross zone boundaries
  /// between zones with different error handlers.
  ///
  /// Example:
  /// ```dart
  /// import 'dart:async';
  ///
  /// main() {
  ///   var future;
  ///   runZonedGuarded(() {
  ///     // The asynchronous error is caught by the custom zone which prints
  ///     // 'asynchronous error'.
  ///     future = Future.error("asynchronous error");
  ///   }, (error) { print(error); });  // Creates a zone with an error handler.
  ///   // The following `catchError` handler is never invoked, because the
  ///   // custom zone created by the call to `runZonedGuarded` provides an
  ///   // error handler.
  ///   future.catchError((error) { throw "is never reached"; });
  /// }
  /// ```
  ///
  /// Note that errors cannot enter a child zone with a different error handler
  /// either:
  /// ```dart
  /// import 'dart:async';
  ///
  /// main() {
  ///   runZonedGuarded(() {
  ///     // The following asynchronous error is *not* caught by the `catchError`
  ///     // in the nested zone, since errors are not to cross zone boundaries
  ///     // with different error handlers.
  ///     // Instead the error is handled by the current error handler,
  ///     // printing "Caught by outer zone: asynchronous error".
  ///     var future = Future.error("asynchronous error");
  ///     runZonedGuarded(() {
  ///       future.catchError((e) { throw "is never reached"; });
  ///     }, (error, stack) { throw "is never reached"; });
  ///   }, (error, stack) { print("Caught by outer zone: $error"); });
  /// }
  /// ```
  Zone get errorZone;

  /// Whether this zone and [otherZone] are in the same error zone.
  ///
  /// Two zones are in the same error zone if they have the same [errorZone].
  bool inSameErrorZone(Zone otherZone);

  /// Creates a new zone as a child zone of this zone.
  ///
  /// The new zone uses the closures in the given [specification] to override
  /// the parent zone's behavior. All specification entries that are `null`
  /// inherit the behavior from the parent zone (`this`).
  ///
  /// The new zone inherits the stored values (accessed through [operator []])
  /// of this zone and updates them with values from [zoneValues], which either
  /// adds new values or overrides existing ones.
  ///
  /// Note that the fork operation is interceptable. A zone can thus change
  /// the zone specification (or zone values), giving the parent zone full
  /// control over the child zone.
  Zone fork({
    ZoneSpecification? specification,
    Map<Object?, Object?>? zoneValues,
  });

  /// Executes [action] in this zone.
  ///
  /// By default (as implemented in the [root] zone), runs [action]
  /// with [current] set to this zone.
  ///
  /// If [action] throws, the synchronous exception is not caught by the zone's
  /// error handler. Use [runGuarded] to achieve that.
  ///
  /// Since the root zone is the only zone that can modify the value of
  /// [current], custom zones intercepting run should always delegate to their
  /// parent zone. They may take actions before and after the call.
  R run<R>(R action());

  /// Executes the given [action] with [argument] in this zone.
  ///
  /// As [run] except that [action] is called with one [argument] instead of
  /// none.
  R runUnary<R, T>(R action(T argument), T argument);

  /// Executes the given [action] with [argument1] and [argument2] in this
  /// zone.
  ///
  /// As [run] except that [action] is called with two arguments instead of none.
  R runBinary<R, T1, T2>(
    R action(T1 argument1, T2 argument2),
    T1 argument1,
    T2 argument2,
  );

  /// Executes the given [action] in this zone and catches synchronous
  /// errors.
  ///
  /// This function is equivalent to:
  /// ```dart
  /// try {
  ///   this.run(action);
  /// } catch (e, s) {
  ///   this.handleUncaughtError(e, s);
  /// }
  /// ```
  ///
  /// See [run].
  void runGuarded(void action());

  /// Executes the given [action] with [argument] in this zone and
  /// catches synchronous errors.
  ///
  /// See [runGuarded].
  void runUnaryGuarded<T>(void action(T argument), T argument);

  /// Executes the given [action] with [argument1] and [argument2] in this
  /// zone and catches synchronous errors.
  ///
  /// See [runGuarded].
  void runBinaryGuarded<T1, T2>(
    void action(T1 argument1, T2 argument2),
    T1 argument1,
    T2 argument2,
  );

  /// Registers the given callback in this zone.
  ///
  /// When implementing an asynchronous primitive that uses callbacks, the
  /// callback must be registered using [registerCallback] at the point where the
  /// user provides the callback. This allows zones to record other information
  /// that they need at the same time, perhaps even wrapping the callback, so
  /// that the callback is prepared when it is later run in the same zones
  /// (using [run]). For example, a zone may decide
  /// to store the stack trace (at the time of the registration) with the
  /// callback.
  ///
  /// Returns the callback that should be used in place of the provided
  /// [callback]. Frequently zones simply return the original callback.
  ///
  /// Custom zones may intercept this operation. The default implementation in
  /// [Zone.root] returns the original callback unchanged.
  ZoneCallback<R> registerCallback<R>(R callback());

  /// Registers the given callback in this zone.
  ///
  /// Similar to [registerCallback] but with a unary callback.
  ZoneUnaryCallback<R, T> registerUnaryCallback<R, T>(R callback(T arg));

  /// Registers the given callback in this zone.
  ///
  /// Similar to [registerCallback] but with a binary callback.
  ZoneBinaryCallback<R, T1, T2> registerBinaryCallback<R, T1, T2>(
    R callback(T1 arg1, T2 arg2),
  );

  /// Registers the provided [callback] and returns a function that will
  /// execute in this zone.
  ///
  /// Equivalent to:
  /// ```dart
  /// ZoneCallback registered = this.registerCallback(callback);
  /// return () => this.run(registered);
  /// ```
  ZoneCallback<R> bindCallback<R>(R callback());

  /// Registers the provided [callback] and returns a function that will
  /// execute in this zone.
  ///
  /// Equivalent to:
  /// ```dart
  /// ZoneCallback registered = this.registerUnaryCallback(callback);
  /// return (arg) => this.runUnary(registered, arg);
  /// ```
  ZoneUnaryCallback<R, T> bindUnaryCallback<R, T>(R callback(T argument));

  /// Registers the provided [callback] and returns a function that will
  /// execute in this zone.
  ///
  /// Equivalent to:
  /// ```dart
  /// ZoneCallback registered = registerBinaryCallback(callback);
  /// return (arg1, arg2) => this.runBinary(registered, arg1, arg2);
  /// ```
  ZoneBinaryCallback<R, T1, T2> bindBinaryCallback<R, T1, T2>(
    R callback(T1 argument1, T2 argument2),
  );

  /// Registers the provided [callback] and returns a function that will
  /// execute in this zone.
  ///
  /// When the function executes, errors are caught and treated as uncaught
  /// errors.
  ///
  /// Equivalent to:
  /// ```dart
  /// ZoneCallback registered = this.registerCallback(callback);
  /// return () => this.runGuarded(registered);
  /// ```
  void Function() bindCallbackGuarded(void Function() callback);

  /// Registers the provided [callback] and returns a function that will
  /// execute in this zone.
  ///
  /// When the function executes, errors are caught and treated as uncaught
  /// errors.
  ///
  /// Equivalent to:
  /// ```dart
  /// ZoneCallback registered = this.registerUnaryCallback(callback);
  /// return (arg) => this.runUnaryGuarded(registered, arg);
  /// ```
  void Function(T) bindUnaryCallbackGuarded<T>(void callback(T argument));

  ///  Registers the provided [callback] and returns a function that will
  ///  execute in this zone.
  ///
  ///  Equivalent to:
  /// ```dart
  ///  ZoneCallback registered = registerBinaryCallback(callback);
  ///  return (arg1, arg2) => this.runBinaryGuarded(registered, arg1, arg2);
  /// ```
  void Function(T1, T2) bindBinaryCallbackGuarded<T1, T2>(
    void callback(T1 argument1, T2 argument2),
  );

  /// Intercepts errors when added programmatically to a [Future] or [Stream].
  ///
  /// When calling [Completer.completeError], [StreamController.addError],
  /// or some [Future] constructors, the current zone is allowed to intercept
  /// and replace the error.
  ///
  /// Future constructors invoke this function when the error is received
  /// directly, for example with [Future.error], or when the error is caught
  /// synchronously, for example with [Future.sync].
  ///
  /// There is no guarantee that an error is only sent through [errorCallback]
  /// once. Libraries that use intermediate controllers or completers might
  /// end up invoking [errorCallback] multiple times.
  ///
  /// Returns `null` if no replacement is desired. Otherwise returns an instance
  /// of [AsyncError] holding the new pair of error and stack trace.
  ///
  /// Custom zones may intercept this operation.
  ///
  /// Implementations of a new asynchronous primitive that converts synchronous
  /// errors to asynchronous errors rarely need to invoke [errorCallback], since
  /// errors are usually reported through future completers or stream
  /// controllers.
  AsyncError? errorCallback(Object error, StackTrace? stackTrace);

  /// Runs [callback] asynchronously in this zone.
  ///
  /// The global `scheduleMicrotask` delegates to the [current] zone's
  /// [scheduleMicrotask]. The root zone's implementation interacts with the
  /// underlying system to schedule the given callback as a microtask.
  ///
  /// Custom zones may intercept this operation (for example to wrap the given
  /// [callback]), or to implement their own microtask scheduler.
  /// In the latter case, they will usually still use the parent zone's
  /// [ZoneDelegate.scheduleMicrotask] to attach themselves to the existing
  /// event loop.
  void scheduleMicrotask(void Function() callback);

  /// Creates a [Timer] where the callback is executed in this zone.
  Timer createTimer(Duration duration, void Function() callback);

  /// Creates a periodic [Timer] where the callback is executed in this zone.
  Timer createPeriodicTimer(Duration period, void callback(Timer timer));

  /// Prints the given [line].
  ///
  /// The global `print` function delegates to the current zone's [print]
  /// function which makes it possible to intercept printing.
  ///
  /// Example:
  /// ```dart
  /// import 'dart:async';
  ///
  /// main() {
  ///   runZoned(() {
  ///     // Ends up printing: "Intercepted: in zone".
  ///     print("in zone");
  ///   }, zoneSpecification: new ZoneSpecification(
  ///       print: (Zone self, ZoneDelegate parent, Zone zone, String line) {
  ///     parent.print(zone, "Intercepted: $line");
  ///   }));
  /// }
  /// ```
  void print(String line);

  /// Call to enter the [Zone].
  ///
  /// The previous current zone is returned.
  static _Zone _enter(_Zone zone) {
    assert(!identical(zone, _current));
    _Zone previous = _current;
    _current = zone;
    return previous;
  }

  /// Call to leave the [Zone].
  ///
  /// The previous [Zone] must be provided as `previous`.
  static void _leave(_Zone previous) {
    assert(previous != null);
    Zone._current = previous;
  }

  /// Retrieves the zone-value associated with [key].
  ///
  /// If this zone does not contain the value looks up the same key in the
  /// parent zone. If the [key] is not found returns `null`.
  ///
  /// Any object can be used as key, as long as it has compatible `operator ==`
  /// and `hashCode` implementations.
  /// By controlling access to the key, a zone can grant or deny access to the
  /// zone value.
  dynamic operator [](Object? key);
}

/// Base class for Zone implementations.
abstract base class _Zone implements Zone {
  const _Zone();

  _Zone get _runZone;
  RunHandler get _runHandler;
  _Zone get _runUnaryZone;
  RunUnaryHandler get _runUnaryHandler;
  _Zone get _runBinaryZone;
  RunBinaryHandler get _runBinaryHandler;
  _Zone get _registerCallbackZone;
  RegisterCallbackHandler get _registerCallbackHandler;
  _Zone get _registerUnaryCallbackZone;
  RegisterUnaryCallbackHandler get _registerUnaryCallbackHandler;
  _Zone get _registerBinaryCallbackZone;
  RegisterBinaryCallbackHandler get _registerBinaryCallbackHandler;
  _Zone get _errorCallbackZone;
  ErrorCallbackHandler get _errorCallbackHandler;
  _Zone get _scheduleMicrotaskZone;
  ScheduleMicrotaskHandler get _scheduleMicrotaskHandler;
  _Zone get _createTimerZone;
  CreateTimerHandler get _createTimerHandler;
  _Zone get _createPeriodicTimerZone;
  CreatePeriodicTimerHandler get _createPeriodicTimerHandler;
  _Zone get _printZone;
  PrintHandler get _printHandler;
  _Zone get _forkZone;
  ForkHandler get _forkHandler;
  _Zone get _handleUncaughtErrorZone;
  HandleUncaughtErrorHandler get _handleUncaughtErrorHandler;

  _ZoneFunction<RunHandler> get _run;
  _ZoneFunction<RunUnaryHandler> get _runUnary;
  _ZoneFunction<RunBinaryHandler> get _runBinary;
  _ZoneFunction<RegisterCallbackHandler> get _registerCallback;
  _ZoneFunction<RegisterUnaryCallbackHandler> get _registerUnaryCallback;
  _ZoneFunction<RegisterBinaryCallbackHandler> get _registerBinaryCallback;
  _ZoneFunction<ErrorCallbackHandler> get _errorCallback;
  _ZoneFunction<ScheduleMicrotaskHandler> get _scheduleMicrotask;
  _ZoneFunction<CreateTimerHandler> get _createTimer;
  _ZoneFunction<CreatePeriodicTimerHandler> get _createPeriodicTimer;
  _ZoneFunction<PrintHandler> get _print;
  _ZoneFunction<ForkHandler> get _fork;
  _ZoneFunction<HandleUncaughtErrorHandler> get _handleUncaughtError;

  _Zone? get parent;
  ZoneDelegate get _delegate;
  ZoneDelegate get _parentDelegate;
  Map<Object?, Object?> get _map;

  bool inSameErrorZone(Zone otherZone) {
    return identical(this, otherZone) ||
        identical(errorZone, otherZone.errorZone);
  }

  void _processUncaughtError(Zone zone, Object error, StackTrace stackTrace) {
    _Zone implZone = _handleUncaughtErrorZone;
    if (identical(implZone, _rootZone)) {
      _rootHandleError(error, stackTrace);
      return;
    }
    HandleUncaughtErrorHandler handler = _handleUncaughtErrorHandler;
    ZoneDelegate parentDelegate = implZone._parentDelegate;
    _Zone parentZone = implZone.parent!; // Not null for non-root zones.
    _Zone currentZone = Zone._current;
    try {
      Zone._current = parentZone;
      handler(implZone, parentDelegate, zone, error, stackTrace);
      Zone._current = currentZone;
    } catch (e, s) {
      Zone._current = currentZone;
      parentZone._processUncaughtError(
        implZone,
        e,
        identical(error, e) ? stackTrace : s,
      );
    }
  }
}

base class _CustomZone extends _Zone {
  _Zone _runZone;
  RunHandler _runHandler;
  _Zone _runUnaryZone;
  RunUnaryHandler _runUnaryHandler;
  _Zone _runBinaryZone;
  RunBinaryHandler _runBinaryHandler;
  _Zone _registerCallbackZone;
  RegisterCallbackHandler _registerCallbackHandler;
  _Zone _registerUnaryCallbackZone;
  RegisterUnaryCallbackHandler _registerUnaryCallbackHandler;
  _Zone _registerBinaryCallbackZone;
  RegisterBinaryCallbackHandler _registerBinaryCallbackHandler;
  _Zone _errorCallbackZone;
  ErrorCallbackHandler _errorCallbackHandler;
  _Zone _scheduleMicrotaskZone;
  ScheduleMicrotaskHandler _scheduleMicrotaskHandler;
  _Zone _createTimerZone;
  CreateTimerHandler _createTimerHandler;
  _Zone _createPeriodicTimerZone;
  CreatePeriodicTimerHandler _createPeriodicTimerHandler;
  _Zone _printZone;
  PrintHandler _printHandler;
  _Zone _forkZone;
  ForkHandler _forkHandler;
  _Zone _handleUncaughtErrorZone;
  HandleUncaughtErrorHandler _handleUncaughtErrorHandler;

  ZoneDelegate? _delegateCache;

  final _Zone parent;

  final Map<Object?, Object?> _map;

  ZoneDelegate get _delegate => _delegateCache ??= _ZoneDelegate(this);
  ZoneDelegate get _parentDelegate => parent._delegate;

  _ZoneFunction<RunHandler> get _run => identical(_runZone, _rootZone)
      ? _RootZone._rootRunFunc
      : _ZoneFunction(_runZone, _runHandler);
  _ZoneFunction<RunUnaryHandler> get _runUnary =>
      identical(_runUnaryZone, _rootZone)
      ? _RootZone._rootRunUnaryFunc
      : _ZoneFunction(_runUnaryZone, _runUnaryHandler);
  _ZoneFunction<RunBinaryHandler> get _runBinary =>
      identical(_runBinaryZone, _rootZone)
      ? _RootZone._rootRunBinaryFunc
      : _ZoneFunction(_runBinaryZone, _runBinaryHandler);
  _ZoneFunction<RegisterCallbackHandler> get _registerCallback =>
      identical(_registerCallbackZone, _rootZone)
      ? _RootZone._rootRegisterCallbackFunc
      : _ZoneFunction(_registerCallbackZone, _registerCallbackHandler);
  _ZoneFunction<RegisterUnaryCallbackHandler> get _registerUnaryCallback =>
      identical(_registerUnaryCallbackZone, _rootZone)
      ? _RootZone._rootRegisterUnaryCallbackFunc
      : _ZoneFunction(
          _registerUnaryCallbackZone,
          _registerUnaryCallbackHandler,
        );
  _ZoneFunction<RegisterBinaryCallbackHandler> get _registerBinaryCallback =>
      identical(_registerBinaryCallbackZone, _rootZone)
      ? _RootZone._rootRegisterBinaryCallbackFunc
      : _ZoneFunction(
          _registerBinaryCallbackZone,
          _registerBinaryCallbackHandler,
        );
  _ZoneFunction<ErrorCallbackHandler> get _errorCallback =>
      identical(_errorCallbackZone, _rootZone)
      ? _RootZone._rootErrorCallbackFunc
      : _ZoneFunction(_errorCallbackZone, _errorCallbackHandler);
  _ZoneFunction<ScheduleMicrotaskHandler> get _scheduleMicrotask =>
      identical(_scheduleMicrotaskZone, _rootZone)
      ? _RootZone._rootScheduleMicrotaskFunc
      : _ZoneFunction(_scheduleMicrotaskZone, _scheduleMicrotaskHandler);
  _ZoneFunction<CreateTimerHandler> get _createTimer =>
      identical(_createTimerZone, _rootZone)
      ? _RootZone._rootCreateTimerFunc
      : _ZoneFunction(_createTimerZone, _createTimerHandler);
  _ZoneFunction<CreatePeriodicTimerHandler> get _createPeriodicTimer =>
      identical(_createPeriodicTimerZone, _rootZone)
      ? _RootZone._rootCreatePeriodicTimerFunc
      : _ZoneFunction(_createPeriodicTimerZone, _createPeriodicTimerHandler);
  _ZoneFunction<PrintHandler> get _print => identical(_printZone, _rootZone)
      ? _RootZone._rootPrintFunc
      : _ZoneFunction(_printZone, _printHandler);
  _ZoneFunction<ForkHandler> get _fork => identical(_forkZone, _rootZone)
      ? _RootZone._rootForkFunc
      : _ZoneFunction(_forkZone, _forkHandler);
  _ZoneFunction<HandleUncaughtErrorHandler> get _handleUncaughtError =>
      identical(_handleUncaughtErrorZone, _rootZone)
      ? _RootZone._rootHandleUncaughtErrorFunc
      : _ZoneFunction(_handleUncaughtErrorZone, _handleUncaughtErrorHandler);

  _CustomZone(this.parent, ZoneSpecification specification, this._map)
    : _runZone = parent._runZone,
      _runHandler = parent._runHandler,
      _runUnaryZone = parent._runUnaryZone,
      _runUnaryHandler = parent._runUnaryHandler,
      _runBinaryZone = parent._runBinaryZone,
      _runBinaryHandler = parent._runBinaryHandler,
      _registerCallbackZone = parent._registerCallbackZone,
      _registerCallbackHandler = parent._registerCallbackHandler,
      _registerUnaryCallbackZone = parent._registerUnaryCallbackZone,
      _registerUnaryCallbackHandler = parent._registerUnaryCallbackHandler,
      _registerBinaryCallbackZone = parent._registerBinaryCallbackZone,
      _registerBinaryCallbackHandler = parent._registerBinaryCallbackHandler,
      _errorCallbackZone = parent._errorCallbackZone,
      _errorCallbackHandler = parent._errorCallbackHandler,
      _scheduleMicrotaskZone = parent._scheduleMicrotaskZone,
      _scheduleMicrotaskHandler = parent._scheduleMicrotaskHandler,
      _createTimerZone = parent._createTimerZone,
      _createTimerHandler = parent._createTimerHandler,
      _createPeriodicTimerZone = parent._createPeriodicTimerZone,
      _createPeriodicTimerHandler = parent._createPeriodicTimerHandler,
      _printZone = parent._printZone,
      _printHandler = parent._printHandler,
      _forkZone = parent._forkZone,
      _forkHandler = parent._forkHandler,
      _handleUncaughtErrorZone = parent._handleUncaughtErrorZone,
      _handleUncaughtErrorHandler = parent._handleUncaughtErrorHandler {
    var run = specification.run;
    if (run != null) {
      _runZone = this;
      _runHandler = run;
    }
    var runUnary = specification.runUnary;
    if (runUnary != null) {
      _runUnaryZone = this;
      _runUnaryHandler = runUnary;
    }
    var runBinary = specification.runBinary;
    if (runBinary != null) {
      _runBinaryZone = this;
      _runBinaryHandler = runBinary;
    }
    var registerCallback = specification.registerCallback;
    if (registerCallback != null) {
      _registerCallbackZone = this;
      _registerCallbackHandler = registerCallback;
    }
    var registerUnaryCallback = specification.registerUnaryCallback;
    if (registerUnaryCallback != null) {
      _registerUnaryCallbackZone = this;
      _registerUnaryCallbackHandler = registerUnaryCallback;
    }
    var registerBinaryCallback = specification.registerBinaryCallback;
    if (registerBinaryCallback != null) {
      _registerBinaryCallbackZone = this;
      _registerBinaryCallbackHandler = registerBinaryCallback;
    }
    var errorCallback = specification.errorCallback;
    if (errorCallback != null) {
      _errorCallbackZone = this;
      _errorCallbackHandler = errorCallback;
    }
    var scheduleMicrotask = specification.scheduleMicrotask;
    if (scheduleMicrotask != null) {
      _scheduleMicrotaskZone = this;
      _scheduleMicrotaskHandler = scheduleMicrotask;
    }
    var createTimer = specification.createTimer;
    if (createTimer != null) {
      _createTimerZone = this;
      _createTimerHandler = createTimer;
    }
    var createPeriodicTimer = specification.createPeriodicTimer;
    if (createPeriodicTimer != null) {
      _createPeriodicTimerZone = this;
      _createPeriodicTimerHandler = createPeriodicTimer;
    }
    var print = specification.print;
    if (print != null) {
      _printZone = this;
      _printHandler = print;
    }
    var fork = specification.fork;
    if (fork != null) {
      _forkZone = this;
      _forkHandler = fork;
    }
    var handleUncaughtError = specification.handleUncaughtError;
    if (handleUncaughtError != null) {
      _handleUncaughtErrorZone = this;
      _handleUncaughtErrorHandler = handleUncaughtError;
    }
  }

  Zone get errorZone => _handleUncaughtErrorZone;

  void runGuarded(void f()) {
    try {
      run(f);
    } catch (e, s) {
      handleUncaughtError(e, s);
    }
  }

  void runUnaryGuarded<T>(void f(T arg), T arg) {
    try {
      runUnary(f, arg);
    } catch (e, s) {
      handleUncaughtError(e, s);
    }
  }

  void runBinaryGuarded<T1, T2>(void f(T1 arg1, T2 arg2), T1 arg1, T2 arg2) {
    try {
      runBinary(f, arg1, arg2);
    } catch (e, s) {
      handleUncaughtError(e, s);
    }
  }

  ZoneCallback<R> bindCallback<R>(R f()) {
    var registered = registerCallback(f);
    return () => this.run(registered);
  }

  ZoneUnaryCallback<R, T> bindUnaryCallback<R, T>(R f(T arg)) {
    var registered = registerUnaryCallback(f);
    return (arg) => this.runUnary(registered, arg);
  }

  ZoneBinaryCallback<R, T1, T2> bindBinaryCallback<R, T1, T2>(
    R f(T1 arg1, T2 arg2),
  ) {
    var registered = registerBinaryCallback(f);
    return (arg1, arg2) => this.runBinary(registered, arg1, arg2);
  }

  void Function() bindCallbackGuarded(void f()) {
    var registered = registerCallback(f);
    return () => this.runGuarded(registered);
  }

  void Function(T) bindUnaryCallbackGuarded<T>(void f(T arg)) {
    var registered = registerUnaryCallback(f);
    return (arg) => this.runUnaryGuarded(registered, arg);
  }

  void Function(T1, T2) bindBinaryCallbackGuarded<T1, T2>(
    void f(T1 arg1, T2 arg2),
  ) {
    var registered = registerBinaryCallback(f);
    return (arg1, arg2) => this.runBinaryGuarded(registered, arg1, arg2);
  }

  dynamic operator [](Object? key) {
    var result = _map[key];
    if (result != null || _map.containsKey(key)) return result;
    var value = parent[key];
    if (value != null &&
        !identical(_map, parent._map) &&
        !identical(_map, _RootZone._rootMap)) {
      _map[key] = value;
    }
    return value;
  }

  void handleUncaughtError(Object error, StackTrace stackTrace) {
    _processUncaughtError(this, error, stackTrace);
  }

  Zone fork({
    ZoneSpecification? specification,
    Map<Object?, Object?>? zoneValues,
  }) {
    if (identical(_forkZone, _rootZone)) {
      return _rootFork(null, null, this, specification, zoneValues);
    }
    return _forkHandler(
      _forkZone,
      _forkZone._parentDelegate,
      this,
      specification,
      zoneValues,
    );
  }

  R run<R>(R f()) {
    if (identical(_runZone, _rootZone)) {
      if (identical(Zone._current, this)) return f();
      return _rootRun(null, null, this, f);
    }
    return _runHandler(_runZone, _runZone._parentDelegate, this, f);
  }

  R runUnary<R, T>(R f(T arg), T arg) {
    if (identical(_runUnaryZone, _rootZone)) {
      if (identical(Zone._current, this)) return f(arg);
      return _rootRunUnary(null, null, this, f, arg);
    }
    return _runUnaryHandler(
      _runUnaryZone,
      _runUnaryZone._parentDelegate,
      this,
      f,
      arg,
    );
  }

  R runBinary<R, T1, T2>(R f(T1 arg1, T2 arg2), T1 arg1, T2 arg2) {
    if (identical(_runBinaryZone, _rootZone)) {
      if (identical(Zone._current, this)) return f(arg1, arg2);
      return _rootRunBinary(null, null, this, f, arg1, arg2);
    }
    return _runBinaryHandler(
      _runBinaryZone,
      _runBinaryZone._parentDelegate,
      this,
      f,
      arg1,
      arg2,
    );
  }

  ZoneCallback<R> registerCallback<R>(R callback()) {
    if (identical(_registerCallbackZone, _rootZone)) return callback;
    return _registerCallbackHandler(
      _registerCallbackZone,
      _registerCallbackZone._parentDelegate,
      this,
      callback,
    );
  }

  ZoneUnaryCallback<R, T> registerUnaryCallback<R, T>(R callback(T arg)) {
    if (identical(_registerUnaryCallbackZone, _rootZone)) return callback;
    return _registerUnaryCallbackHandler(
      _registerUnaryCallbackZone,
      _registerUnaryCallbackZone._parentDelegate,
      this,
      callback,
    );
  }

  ZoneBinaryCallback<R, T1, T2> registerBinaryCallback<R, T1, T2>(
    R callback(T1 arg1, T2 arg2),
  ) {
    if (identical(_registerBinaryCallbackZone, _rootZone)) return callback;
    return _registerBinaryCallbackHandler(
      _registerBinaryCallbackZone,
      _registerBinaryCallbackZone._parentDelegate,
      this,
      callback,
    );
  }

  AsyncError? errorCallback(Object error, StackTrace? stackTrace) {
    if (identical(_errorCallbackZone, _rootZone)) return null;
    return _errorCallbackHandler(
      _errorCallbackZone,
      _errorCallbackZone._parentDelegate,
      this,
      error,
      stackTrace,
    );
  }

  void scheduleMicrotask(void f()) {
    if (identical(_scheduleMicrotaskZone, _rootZone)) {
      _rootScheduleMicrotask(null, null, this, f);
      return;
    }
    _scheduleMicrotaskHandler(
      _scheduleMicrotaskZone,
      _scheduleMicrotaskZone._parentDelegate,
      this,
      f,
    );
  }

  Timer createTimer(Duration duration, void f()) {
    if (identical(_createTimerZone, _rootZone)) {
      if (!identical(_rootZone, this)) {
        f = bindCallback(f);
      }
      return Timer._createTimer(duration, f);
    }
    return _createTimerHandler(
      _createTimerZone,
      _createTimerZone._parentDelegate,
      this,
      duration,
      f,
    );
  }

  Timer createPeriodicTimer(Duration duration, void f(Timer timer)) {
    if (identical(_createPeriodicTimerZone, _rootZone)) {
      if (!identical(_rootZone, this)) {
        f = bindUnaryCallback<void, Timer>(f);
      }
      return Timer._createPeriodicTimer(duration, f);
    }
    return _createPeriodicTimerHandler(
      _createPeriodicTimerZone,
      _createPeriodicTimerZone._parentDelegate,
      this,
      duration,
      f,
    );
  }

  void print(String line) {
    if (identical(_printZone, _rootZone)) {
      printToConsole(line);
      return;
    }
    _printHandler(_printZone, _printZone._parentDelegate, this, line);
  }
}

base class _RootZone extends _Zone {
  const _RootZone();

  _Zone get _runZone => _rootZone;
  RunHandler get _runHandler => _rootRun;
  _Zone get _runUnaryZone => _rootZone;
  RunUnaryHandler get _runUnaryHandler => _rootRunUnary;
  _Zone get _runBinaryZone => _rootZone;
  RunBinaryHandler get _runBinaryHandler => _rootRunBinary;
  _Zone get _registerCallbackZone => _rootZone;
  RegisterCallbackHandler get _registerCallbackHandler => _rootRegisterCallback;
  _Zone get _registerUnaryCallbackZone => _rootZone;
  RegisterUnaryCallbackHandler get _registerUnaryCallbackHandler =>
      _rootRegisterUnaryCallback;
  _Zone get _registerBinaryCallbackZone => _rootZone;
  RegisterBinaryCallbackHandler get _registerBinaryCallbackHandler =>
      _rootRegisterBinaryCallback;
  _Zone get _errorCallbackZone => _rootZone;
  ErrorCallbackHandler get _errorCallbackHandler => _rootErrorCallback;
  _Zone get _scheduleMicrotaskZone => _rootZone;
  ScheduleMicrotaskHandler get _scheduleMicrotaskHandler =>
      _rootScheduleMicrotask;
  _Zone get _createTimerZone => _rootZone;
  CreateTimerHandler get _createTimerHandler => _rootCreateTimer;
  _Zone get _createPeriodicTimerZone => _rootZone;
  CreatePeriodicTimerHandler get _createPeriodicTimerHandler =>
      _rootCreatePeriodicTimer;
  _Zone get _printZone => _rootZone;
  PrintHandler get _printHandler => _rootPrint;
  _Zone get _forkZone => _rootZone;
  ForkHandler get _forkHandler => _rootFork;
  _Zone get _handleUncaughtErrorZone => _rootZone;
  HandleUncaughtErrorHandler get _handleUncaughtErrorHandler =>
      _rootHandleUncaughtError;

  static const _rootRunFunc = _ZoneFunction<RunHandler>(_rootZone, _rootRun);
  static const _rootRunUnaryFunc = _ZoneFunction<RunUnaryHandler>(
    _rootZone,
    _rootRunUnary,
  );
  static const _rootRunBinaryFunc = _ZoneFunction<RunBinaryHandler>(
    _rootZone,
    _rootRunBinary,
  );
  static const _rootRegisterCallbackFunc =
      _ZoneFunction<RegisterCallbackHandler>(_rootZone, _rootRegisterCallback);
  static const _rootRegisterUnaryCallbackFunc =
      _ZoneFunction<RegisterUnaryCallbackHandler>(
        _rootZone,
        _rootRegisterUnaryCallback,
      );
  static const _rootRegisterBinaryCallbackFunc =
      _ZoneFunction<RegisterBinaryCallbackHandler>(
        _rootZone,
        _rootRegisterBinaryCallback,
      );
  static const _rootErrorCallbackFunc = _ZoneFunction<ErrorCallbackHandler>(
    _rootZone,
    _rootErrorCallback,
  );
  static const _rootScheduleMicrotaskFunc =
      _ZoneFunction<ScheduleMicrotaskHandler>(
        _rootZone,
        _rootScheduleMicrotask,
      );
  static const _rootCreateTimerFunc = _ZoneFunction<CreateTimerHandler>(
    _rootZone,
    _rootCreateTimer,
  );
  static const _rootCreatePeriodicTimerFunc =
      _ZoneFunction<CreatePeriodicTimerHandler>(
        _rootZone,
        _rootCreatePeriodicTimer,
      );
  static const _rootPrintFunc = _ZoneFunction<PrintHandler>(
    _rootZone,
    _rootPrint,
  );
  static const _rootForkFunc = _ZoneFunction<ForkHandler>(_rootZone, _rootFork);
  static const _rootHandleUncaughtErrorFunc =
      _ZoneFunction<HandleUncaughtErrorHandler>(
        _rootZone,
        _rootHandleUncaughtError,
      );

  _ZoneFunction<RunHandler> get _run => _rootRunFunc;
  _ZoneFunction<RunUnaryHandler> get _runUnary => _rootRunUnaryFunc;
  _ZoneFunction<RunBinaryHandler> get _runBinary => _rootRunBinaryFunc;
  _ZoneFunction<RegisterCallbackHandler> get _registerCallback =>
      _rootRegisterCallbackFunc;
  _ZoneFunction<RegisterUnaryCallbackHandler> get _registerUnaryCallback =>
      _rootRegisterUnaryCallbackFunc;
  _ZoneFunction<RegisterBinaryCallbackHandler> get _registerBinaryCallback =>
      _rootRegisterBinaryCallbackFunc;
  _ZoneFunction<ErrorCallbackHandler> get _errorCallback =>
      _rootErrorCallbackFunc;
  _ZoneFunction<ScheduleMicrotaskHandler> get _scheduleMicrotask =>
      _rootScheduleMicrotaskFunc;
  _ZoneFunction<CreateTimerHandler> get _createTimer => _rootCreateTimerFunc;
  _ZoneFunction<CreatePeriodicTimerHandler> get _createPeriodicTimer =>
      _rootCreatePeriodicTimerFunc;
  _ZoneFunction<PrintHandler> get _print => _rootPrintFunc;
  _ZoneFunction<ForkHandler> get _fork => _rootForkFunc;
  _ZoneFunction<HandleUncaughtErrorHandler> get _handleUncaughtError =>
      _rootHandleUncaughtErrorFunc;

  _Zone? get parent => null;

  Map<Object?, Object?> get _map => _rootMap;

  static const Map<Object?, Object?> _rootMap = {};

  static const ZoneDelegate _rootDelegate = _ZoneDelegate(_rootZone);

  ZoneDelegate get _delegate => _rootDelegate;
  ZoneDelegate get _parentDelegate => _rootDelegate;

  Zone get errorZone => this;

  // Zone interface.

  void runGuarded(void f()) {
    try {
      if (identical(_rootZone, Zone._current)) {
        f();
        return;
      }
      _rootRun(null, null, this, f);
    } catch (e, s) {
      handleUncaughtError(e, s);
    }
  }

  void runUnaryGuarded<T>(void f(T arg), T arg) {
    try {
      if (identical(_rootZone, Zone._current)) {
        f(arg);
        return;
      }
      _rootRunUnary(null, null, this, f, arg);
    } catch (e, s) {
      handleUncaughtError(e, s);
    }
  }

  void runBinaryGuarded<T1, T2>(void f(T1 arg1, T2 arg2), T1 arg1, T2 arg2) {
    try {
      if (identical(_rootZone, Zone._current)) {
        f(arg1, arg2);
        return;
      }
      _rootRunBinary(null, null, this, f, arg1, arg2);
    } catch (e, s) {
      handleUncaughtError(e, s);
    }
  }

  ZoneCallback<R> bindCallback<R>(R f()) {
    return () => this.run<R>(f);
  }

  ZoneUnaryCallback<R, T> bindUnaryCallback<R, T>(R f(T arg)) {
    return (arg) => this.runUnary<R, T>(f, arg);
  }

  ZoneBinaryCallback<R, T1, T2> bindBinaryCallback<R, T1, T2>(
    R f(T1 arg1, T2 arg2),
  ) {
    return (arg1, arg2) => this.runBinary<R, T1, T2>(f, arg1, arg2);
  }

  void Function() bindCallbackGuarded(void f()) {
    return () => this.runGuarded(f);
  }

  void Function(T) bindUnaryCallbackGuarded<T>(void f(T arg)) {
    return (arg) => this.runUnaryGuarded(f, arg);
  }

  void Function(T1, T2) bindBinaryCallbackGuarded<T1, T2>(
    void f(T1 arg1, T2 arg2),
  ) {
    return (arg1, arg2) => this.runBinaryGuarded(f, arg1, arg2);
  }

  dynamic operator [](Object? key) => null;

  // Methods that can be customized by the zone specification.

  void handleUncaughtError(Object error, StackTrace stackTrace) {
    _rootHandleError(error, stackTrace);
  }

  Zone fork({
    ZoneSpecification? specification,
    Map<Object?, Object?>? zoneValues,
  }) {
    return _rootFork(null, null, this, specification, zoneValues);
  }

  R run<R>(R f()) {
    if (identical(Zone._current, _rootZone)) return f();
    return _rootRun(null, null, this, f);
  }

  @pragma('vm:invisible')
  R runUnary<R, T>(R f(T arg), T arg) {
    if (identical(Zone._current, _rootZone)) return f(arg);
    return _rootRunUnary(null, null, this, f, arg);
  }

  R runBinary<R, T1, T2>(R f(T1 arg1, T2 arg2), T1 arg1, T2 arg2) {
    if (identical(Zone._current, _rootZone)) return f(arg1, arg2);
    return _rootRunBinary(null, null, this, f, arg1, arg2);
  }

  ZoneCallback<R> registerCallback<R>(R f()) => f;

  ZoneUnaryCallback<R, T> registerUnaryCallback<R, T>(R f(T arg)) => f;

  ZoneBinaryCallback<R, T1, T2> registerBinaryCallback<R, T1, T2>(
    R f(T1 arg1, T2 arg2),
  ) => f;

  AsyncError? errorCallback(Object error, StackTrace? stackTrace) => null;

  void scheduleMicrotask(void f()) {
    _rootScheduleMicrotask(null, null, this, f);
  }

  Timer createTimer(Duration duration, void f()) {
    return Timer._createTimer(duration, f);
  }

  Timer createPeriodicTimer(Duration duration, void f(Timer timer)) {
    return Timer._createPeriodicTimer(duration, f);
  }

  void print(String line) {
    printToConsole(line);
  }
}
