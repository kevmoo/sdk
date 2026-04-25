part of dart.io;

/// A high-performance, ownership-based server socket.
abstract interface class ServerSocket2 {
  /// Binds to a given address and port.
  static Future<ServerSocket2> bind(Object address, int port,
      {int backlog = 0, bool v6Only = false, bool shared = false}) {
    return _ServerSocket2._bind(address, port, backlog, v6Only, shared);
  }

  /// Accepts the next incoming connection.
  Future<Socket2> accept();

  /// Closes the server socket.
  Future<void> close();

  /// Returns the port that this server socket is bound to.
  int get port;
}

class _ServerSocket2 implements ServerSocket2 {
  static Future<ServerSocket2> _bind(
      Object address, int port, int backlog, bool v6Only, bool shared) {
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
}

/// A high-performance, ownership-based socket connection.
/// 
/// Unlike [Socket], [Socket2] does not use [Stream]. Instead, it uses an
/// ownership-passing paradigm: you pass a [ByteBuffer] to the socket to
/// read or write, and the socket takes ownership of it while the operation
/// is in flight, returning it when the Future completes.
abstract interface class Socket2 {
  /// Connects to a host and port, returning a Future that completes with the
  /// [Socket2] once connected.
  static Future<Socket2> connect(Object host, int port,
      {Object? sourceAddress, int sourcePort = 0, Duration? timeout}) {
    return _Socket2._connect(host, port, sourceAddress, sourcePort, timeout);
  }

  /// Initiates an asynchronous read into [buffer].
  /// 
  /// The socket takes ownership of the buffer until the Future completes.
  /// The returned Record contains the number of bytes read and
  /// returns ownership of the buffer.
  Future<({int bytes, TypedData buffer})> read(TypedData buffer);

  /// Initiates an asynchronous write from [buffer].
  /// 
  /// The socket takes ownership of the buffer until the Future completes.
  /// The returned Record contains the number of bytes written and
  /// returns ownership of the buffer.
  Future<({int bytes, TypedData buffer})> write(TypedData buffer);

  /// Closes the socket.
  Future<void> close();
}

class _Socket2 implements Socket2 {
  static Future<Socket2> _connect(Object host, int port,
      Object? sourceAddress, int sourcePort, Duration? timeout) {
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
