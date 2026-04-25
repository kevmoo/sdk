part of dart.io;

/// A high-performance, ownership-based server socket.
///
/// [ServerSocket2] is an advanced, completion-based alternative to [ServerSocket].
/// It is designed for high-throughput applications that require precise control
/// over memory allocations and buffer lifecycle.
///
/// Use [bind] to create a new server socket.
abstract interface class ServerSocket2 {
  /// Binds to a given address and port.
  ///
  /// The [address] can be either a [String] or an [InternetAddress].
  ///
  /// The [backlog] parameter can be used to set the listen backlog for the
  /// underlying OS listen setup.
  ///
  /// If [v6Only] is `true`, only IPv6 connections will be accepted.
  ///
  /// If [shared] is `true`, multiple [ServerSocket2] instances can bind to the
  /// same address and port, allowing for load balancing across isolates.
  static Future<ServerSocket2> bind(
    Object address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) {
    return _ServerSocket2._bind(address, port, backlog, v6Only, shared);
  }

  /// Accepts the next incoming connection.
  ///
  /// Returns a [Future] that completes with a [Socket2] instance when a new
  /// connection is established. Only one accept operation can be pending
  /// at a time; calling [accept] while another accept is in progress will
  /// throw a [StateError].
  Future<Socket2> accept();

  /// Closes the server socket.
  ///
  /// Any pending [accept] operation will complete with a [SocketException].
  Future<void> close();

  /// Returns the port that this server socket is bound to.
  int get port;
}

class _ServerSocket2 implements ServerSocket2 {
  static Future<ServerSocket2> _bind(
    Object address,
    int port,
    int backlog,
    bool v6Only,
    bool shared,
  ) {
    throw UnimplementedError("Patch should implement this");
  }

  @override
  Future<Socket2> accept() {
    throw UnimplementedError();
  }

  @override
  Future<void> close() {
    throw UnimplementedError();
  }

  @override
  int get port => throw UnimplementedError();
}

/// A high-performance, ownership-based socket connection.
///
/// [Socket2] is an advanced alternative to [Socket], providing a
/// completion-based API instead of a [Stream]-based one. It is specifically
/// designed for "zero-copy" scenarios where the application manages its own
/// buffer pools and wants to avoid the overhead of [Stream] controllers and
/// intermediate data copying.
///
/// Unlike [Socket], [Socket2] uses an ownership-passing paradigm:
/// 1. You pass a [TypedData] buffer to [read] or [write].
/// 2. The socket takes ownership of that buffer while the operation is in flight.
/// 3. The returned [Future] completes with a record that returns ownership of
///    the buffer along with the result of the operation.
///
/// High-performance applications should prefer using [Socket2] with a
/// [Uint8List] from a pool to minimize garbage collection pressure.
abstract interface class Socket2 {
  /// Connects to a host and port.
  ///
  /// Returns a [Future] that completes with a [Socket2] instance once the
  /// connection is established.
  ///
  /// The [host] can be either a [String] or an [InternetAddress].
  static Future<Socket2> connect(
    Object host,
    int port, {
    Object? sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) {
    return _Socket2._connect(host, port, sourceAddress, sourcePort, timeout);
  }

  /// Initiates an asynchronous read into [buffer].
  ///
  /// The socket takes ownership of [buffer] until the returned [Future]
  /// completes. Attempting to modify the buffer while the read is in progress
  /// results in undefined behavior.
  ///
  /// The returned [Future] completes with a named record:
  /// - `bytes`: The number of bytes actually read. If 0, it indicates the
  ///   remote peer has closed the connection (EOF).
  /// - `buffer`: The same buffer instance passed to the method, with its
  ///   ownership returned to the caller.
  ///
  /// Only one [read] operation can be pending at a time. Calling [read] while
  /// another read is in progress will throw a [StateError].
  Future<({int bytes, TypedData buffer})> read(TypedData buffer);

  /// Initiates an asynchronous write from [buffer].
  ///
  /// The socket takes ownership of [buffer] until the returned [Future]
  /// completes. Attempting to modify the buffer while the write is in progress
  /// results in undefined behavior.
  ///
  /// The returned [Future] completes with a named record:
  /// - `bytes`: The number of bytes actually written.
  /// - `buffer`: The same buffer instance passed to the method, with its
  ///   ownership returned to the caller.
  ///
  /// Only one [write] operation can be pending at a time. Calling [write] while
  /// another write is in progress will throw a [StateError].
  ///
  /// Note: [Socket2] allows a [read] and a [write] to be pending simultaneously.
  Future<({int bytes, TypedData buffer})> write(TypedData buffer);

  /// Closes the socket.
  ///
  /// Any pending [read] or [write] operations will complete with a
  /// [SocketException].
  Future<void> close();
}

class _Socket2 implements Socket2 {
  static Future<Socket2> _connect(
    Object host,
    int port,
    Object? sourceAddress,
    int sourcePort,
    Duration? timeout,
  ) {
    throw UnimplementedError("Patch should implement this");
  }

  @override
  Future<({int bytes, TypedData buffer})> read(TypedData buffer) {
    throw UnimplementedError();
  }

  @override
  Future<({int bytes, TypedData buffer})> write(TypedData buffer) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() {
    throw UnimplementedError();
  }
}
