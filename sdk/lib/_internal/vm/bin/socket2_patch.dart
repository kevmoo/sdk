part of "common_patch.dart";

@patch
class _Socket2 {
  @patch
  static Future<Socket2> _connect(Object host, int port,
      Object? sourceAddress, int sourcePort, Duration? timeout) async {
    final rawSocket = await RawSocket.connect(
        host, port,
        sourceAddress: sourceAddress,
        sourcePort: sourcePort,
        timeout: timeout) as _RawSocket;
    
    return _Socket2Impl(rawSocket._socket);
  }
}

@patch
class _ServerSocket2 {
  @patch
  static Future<ServerSocket2> _bind(
      Object address, int port, int backlog, bool v6Only, bool shared) async {
    final rawServerSocket = await RawServerSocket.bind(
      address,
      port,
      backlog: backlog,
      v6Only: v6Only,
      shared: shared,
    ) as _RawServerSocket;
    
    return _ServerSocket2Impl(rawServerSocket._socket);
  }
}

class _ServerSocket2Impl implements ServerSocket2 {
  final _NativeSocket _socket;
  Completer<Socket2>? _acceptCompleter;

  _ServerSocket2Impl(this._socket) {
    _socket.setHandlers(
      read: _tryAccept,
      error: (e, st) => _completeWithError(e),
      closed: () => _completeWithError(SocketException("Server socket closed")),
    );
    _socket.setListening(read: true, write: false);
  }

  void _completeWithError(Object error) {
    if (_acceptCompleter != null && !_acceptCompleter!.isCompleted) {
      var c = _acceptCompleter!;
      _acceptCompleter = null;
      c.completeError(error);
    }
  }

  void _tryAccept() {
    if (_acceptCompleter != null && _socket.connections > 0) {
      var nativeSocket = _socket.accept();
      if (nativeSocket != null) {
        var c = _acceptCompleter!;
        _acceptCompleter = null;
        c.complete(_Socket2Impl(nativeSocket));
      }
    }
  }

  @override
  Future<Socket2> accept() {
    if (_acceptCompleter != null) {
      throw StateError("An accept operation is already pending.");
    }
    _acceptCompleter = Completer<Socket2>();
    _tryAccept();
    return _acceptCompleter!.future;
  }

  @override
  Future<void> close() async {
    _socket.close();
  }
}

class _Socket2Impl implements Socket2 {
  final _NativeSocket _socket;
  
  Completer<({int bytes, TypedData buffer})>? _readCompleter;
  Completer<({int bytes, TypedData buffer})>? _writeCompleter;

  TypedData? _pendingReadBuffer;
  TypedData? _pendingWriteBuffer;

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
      int result = _nativeReadInto(_socket, _pendingReadBuffer!, 0, _pendingReadBuffer!.lengthInBytes);
      if (result > 0 || (result == 0 && _socket.isClosed)) {
        var completer = _readCompleter!;
        var buffer = _pendingReadBuffer!;
        _readCompleter = null;
        _pendingReadBuffer = null;
        completer.complete((bytes: result, buffer: buffer));
      } else if (result == -1 || result == 0) {
        // Would block, wait for next event.
      }
    }
  }

  void _tryWrite() {
    if (_writeCompleter != null && _pendingWriteBuffer != null) {
      int result = _nativeWriteFrom(_socket, _pendingWriteBuffer!, 0, _pendingWriteBuffer!.lengthInBytes);
      if (result > 0 || (result == 0 && _socket.isClosed)) {
        var completer = _writeCompleter!;
        var buffer = _pendingWriteBuffer!;
        _writeCompleter = null;
        _pendingWriteBuffer = null;
        completer.complete((bytes: result, buffer: buffer));
      } else if (result == -1 || result == 0) {
        // Would block, wait for next event.
      }
    }
  }

  @override
  Future<({int bytes, TypedData buffer})> read(TypedData buffer) {
    if (_readCompleter != null) {
      throw StateError("A read operation is already pending.");
    }
    _readCompleter = Completer<({int bytes, TypedData buffer})>();
    var future = _readCompleter!.future;
    _pendingReadBuffer = buffer;
    _tryRead();
    return future;
  }

  @override
  Future<({int bytes, TypedData buffer})> write(TypedData buffer) {
    if (_writeCompleter != null) {
      throw StateError("A write operation is already pending.");
    }
    _writeCompleter = Completer<({int bytes, TypedData buffer})>();
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
