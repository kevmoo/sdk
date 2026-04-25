part of dart.io;

/// A high-performance, ownership-based socket connection.
/// 
/// Unlike [Socket], [Socket2] does not use [Stream]. Instead, it uses an
/// ownership-passing paradigm: you pass a [ByteBuffer] to the socket to
/// read or write, and the socket takes ownership of it while the operation
/// is in flight, returning it when the Future completes.
abstract interface class Socket2 {
  /// Connects to a host and port, returning a Future that completes with the
  /// [Socket2] once connected.
  static Future<Socket2> connect(dynamic host, int port,
      {dynamic sourceAddress, int sourcePort = 0, Duration? timeout}) {
    return _Socket2._connect(host, port, sourceAddress, sourcePort, timeout);
  }

  /// Initiates an asynchronous read into [buffer].
  /// 
  /// The socket takes ownership of the buffer until the Future completes.
  /// The returned Record contains the number of bytes read and
  /// returns ownership of the buffer.
  Future<(int bytes, ByteBuffer buffer)> read(ByteBuffer buffer);

  /// Initiates an asynchronous write from [buffer].
  /// 
  /// The socket takes ownership of the buffer until the Future completes.
  /// The returned Record contains the number of bytes written and
  /// returns ownership of the buffer.
  Future<(int bytes, ByteBuffer buffer)> write(ByteBuffer buffer);

  /// Closes the socket.
  Future<void> close();
}

class _Socket2 implements Socket2 {
  static Future<Socket2> _connect(dynamic host, int port,
      dynamic sourceAddress, int sourcePort, Duration? timeout) {
    throw UnimplementedError("Patch should implement this");
  }

  @override
  Future<(int bytes, ByteBuffer buffer)> read(ByteBuffer buffer) {
    throw UnimplementedError();
  }

  @override
  Future<(int bytes, ByteBuffer buffer)> write(ByteBuffer buffer) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() {
    throw UnimplementedError();
  }
}
