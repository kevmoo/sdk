part of "common_patch.dart";

@patch
class _Socket2 {
  @patch
  static Future<Socket2> _connect(dynamic host, int port,
      dynamic sourceAddress, int sourcePort, Duration? timeout) async {
    final rawSocket = await RawSocket.connect(
        host, port,
        sourceAddress: sourceAddress,
        sourcePort: sourcePort,
        timeout: timeout) as _RawSocket;
    
    return _Socket2Impl(rawSocket._socket);
  }
}

class _Socket2Impl implements Socket2 {
  final _NativeSocket _socket;
  
  Completer<(int, ByteBuffer)>? _readCompleter;
  Completer<(int, ByteBuffer)>? _writeCompleter;

  ByteBuffer? _pendingReadBuffer;
  ByteBuffer? _pendingWriteBuffer;

  _Socket2Impl(this._socket) {
    // Hijack the event handlers from _RawSocket.
    _socket.setHandlers(
      read: _tryRead,
      write: _tryWrite,
      error: (e, st) => _completeAllWithError(e),
      closed: () => _completeAllWithError(SocketException("Socket closed")),
    );
    // Ensure we are listening for both read and write events.
    _socket.setListening(read: true, write: true);
  }

  void _completeAllWithError(Object error) {
    if (_readCompleter != null && !_readCompleter!.isCompleted) {
      var c = _readCompleter!;
      _readCompleter = null;
      _pendingReadBuffer = null;
      c.completeError(error);
    }
    if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
      var c = _writeCompleter!;
      _writeCompleter = null;
      _pendingWriteBuffer = null;
      c.completeError(error);
    }
  }

  void _tryRead() {
    if (_readCompleter != null && _pendingReadBuffer != null) {
      int result = _nativeReadInto(_socket, Uint8List.view(_pendingReadBuffer!), 0, _pendingReadBuffer!.lengthInBytes);
      if (result > 0 || (result == 0 && _socket.isClosed)) {
        var completer = _readCompleter!;
        var buffer = _pendingReadBuffer!;
        _readCompleter = null;
        _pendingReadBuffer = null;
        completer.complete((result, buffer));
      } else if (result == -1 || result == 0) {
        // Would block, wait for next event.
      }
    }
  }

  void _tryWrite() {
    if (_writeCompleter != null && _pendingWriteBuffer != null) {
      int result = _nativeWriteFrom(_socket, Uint8List.view(_pendingWriteBuffer!), 0, _pendingWriteBuffer!.lengthInBytes);
      if (result > 0 || (result == 0 && _socket.isClosed)) {
        var completer = _writeCompleter!;
        var buffer = _pendingWriteBuffer!;
        _writeCompleter = null;
        _pendingWriteBuffer = null;
        completer.complete((result, buffer));
      } else if (result == -1 || result == 0) {
        // Would block, wait for next event.
      }
    }
  }

  @override
  Future<(int bytes, ByteBuffer buffer)> read(ByteBuffer buffer) {
    if (_readCompleter != null) {
      throw StateError("A read operation is already pending.");
    }
    _readCompleter = Completer<(int, ByteBuffer)>();
    var future = _readCompleter!.future;
    _pendingReadBuffer = buffer;
    _tryRead();
    return future;
  }

  @override
  Future<(int bytes, ByteBuffer buffer)> write(ByteBuffer buffer) {
    if (_writeCompleter != null) {
      throw StateError("A write operation is already pending.");
    }
    _writeCompleter = Completer<(int, ByteBuffer)>();
    var future = _writeCompleter!.future;
    _pendingWriteBuffer = buffer;
    _tryWrite();
    return future;
  }

  @override
  Future<void> close() async {
    _socket.close();
  }

  @pragma("vm:external-name", "Socket2_ReadInto")
  external static int _nativeReadInto(_NativeSocket socket, TypedData buffer, int offset, int length);

  @pragma("vm:external-name", "Socket2_WriteFrom")
  external static int _nativeWriteFrom(_NativeSocket socket, TypedData buffer, int offset, int length);
}
