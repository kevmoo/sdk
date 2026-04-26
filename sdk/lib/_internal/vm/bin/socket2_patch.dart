part of "common_patch.dart";

@patch
class _Socket2 {
  @patch
  static Future<Socket2> _connect(
    Object host,
    int port,
    Object? sourceAddress,
    int sourcePort,
    Duration? timeout,
  ) async {
    final nativeSocket = await _NativeSocket.connect(
      host,
      port,
      sourceAddress,
      sourcePort,
      timeout,
    );

    return _Socket2Impl(nativeSocket);
  }
}

@patch
class _ServerSocket2 {
  @patch
  static Future<ServerSocket2> _bind(
    Object address,
    int port,
    int backlog,
    bool v6Only,
    bool shared,
  ) async {
    final nativeSocket = await _NativeSocket.bind(
      address,
      port,
      backlog,
      v6Only,
      shared,
    );

    return _ServerSocket2Impl(nativeSocket);
  }
}

class _ServerSocket2Impl implements ServerSocket2 {
  final _NativeSocket _socket;
  Completer<Socket2>? _acceptCompleter;

  _ServerSocket2Impl(this._socket) {
    _socket.isSocket2 = true;
    _socket.setHandlers(
      read: _tryAccept,
      error: (e, st) => _completeWithError(e),
      closed: () => _completeWithError(SocketException("Server socket closed")),
    );
    _socket.setListening(read: true, write: false, issueEvents: true);
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

  @override
  int get port => _socket.port;
}

class _Socket2Impl implements Socket2 {
  final _NativeSocket _socket;

  Completer<({int bytes, Uint8List buffer})>? _readCompleter;
  Completer<({int bytes, Uint8List buffer})>? _writeCompleter;
  Completer<({int bytes, List<Uint8List> buffers})>? _writeListCompleter;

  Uint8List? _pendingReadBuffer;
  Uint8List? _pendingWriteBuffer;
  List<Uint8List>? _pendingWriteListBuffers;

  _Socket2Impl(this._socket) {
    _socket.isSocket2 = true;
    // Hijack the event handlers from _RawSocket.
    _socket.setHandlers(
      read: _tryRead,
      write: _tryWrite,
      error: (e, st) => _completeAllWithError(e),
      closed: _onClosed,
    );
    // Ensure we are listening for both read and write events.
    _socket.setListening(read: true, write: true, issueEvents: true);
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
    if (_writeListCompleter != null && !_writeListCompleter!.isCompleted) {
      var c = _writeListCompleter!;
      _writeListCompleter = null;
      _pendingWriteListBuffers = null;
      c.completeError(error);
    }
  }

  void _onClosed() {
    if (_readCompleter != null && !_readCompleter!.isCompleted) {
      var c = _readCompleter!;
      var buffer = _pendingReadBuffer!;
      _readCompleter = null;
      _pendingReadBuffer = null;
      c.complete((bytes: 0, buffer: buffer));
    }
    if (_writeCompleter != null && !_writeCompleter!.isCompleted) {
      var c = _writeCompleter!;
      _writeCompleter = null;
      _pendingWriteBuffer = null;
      c.completeError(const SocketException("Connection closed while writing"));
    }
    if (_writeListCompleter != null && !_writeListCompleter!.isCompleted) {
      var c = _writeListCompleter!;
      _writeListCompleter = null;
      _pendingWriteListBuffers = null;
      c.completeError(const SocketException("Connection closed while writing"));
    }
  }

  void _tryRead() {
    if (_readCompleter != null && _pendingReadBuffer != null) {
      try {
        int result = _nativeReadInto(
          _socket,
          _pendingReadBuffer!,
          0,
          _pendingReadBuffer!.lengthInBytes,
        );
        if (result > 0 || (result == 0 && _socket.isClosed)) {
          var completer = _readCompleter!;
          var buffer = _pendingReadBuffer!;
          _readCompleter = null;
          _pendingReadBuffer = null;
          completer.complete((bytes: result, buffer: buffer));
        } else if (result == -1 || result == 0) {
          // Would block, wait for next event.
          // Re-register interest to ensure we get the next readiness event.
          _socket.setListening(read: true, write: true, issueEvents: false);
        }
      } catch (e) {
        _completeAllWithError(e);
      }
    }
  }

  void _tryWrite() {
    if (_writeCompleter != null && _pendingWriteBuffer != null) {
      try {
        int result = _nativeWriteFrom(
          _socket,
          _pendingWriteBuffer!,
          0,
          _pendingWriteBuffer!.lengthInBytes,
        );
        if (result > 0 || (result == 0 && _socket.isClosed)) {
          var completer = _writeCompleter!;
          var buffer = _pendingWriteBuffer!;
          _writeCompleter = null;
          _pendingWriteBuffer = null;
          completer.complete((bytes: result, buffer: buffer));
        } else if (result == -1 || result == 0) {
          // Would block, wait for next event.
          // Re-register interest to ensure we get the next readiness event.
          _socket.setListening(read: true, write: true, issueEvents: false);
        }
      } catch (e) {
        _completeAllWithError(e);
      }
    } else if (_writeListCompleter != null && _pendingWriteListBuffers != null) {
      try {
        int result = _nativeWriteList(
          _socket,
          _pendingWriteListBuffers!,
        );
        if (result > 0 || (result == 0 && _socket.isClosed)) {
          var completer = _writeListCompleter!;
          var buffers = _pendingWriteListBuffers!;
          _writeListCompleter = null;
          _pendingWriteListBuffers = null;
          completer.complete((bytes: result, buffers: buffers));
        } else if (result == -1 || result == 0) {
          // Would block, wait for next event.
          // Re-register interest to ensure we get the next readiness event.
          _socket.setListening(read: true, write: true, issueEvents: false);
        }
      } catch (e) {
        _completeAllWithError(e);
      }
    }
  }

  @override
  Future<({int bytes, Uint8List buffer})> read(Uint8List buffer) {
    if (buffer.lengthInBytes == 0) {
      return Future.value((bytes: 0, buffer: buffer));
    }
    if (_readCompleter != null) {
      throw StateError("A read operation is already pending.");
    }
    _readCompleter = Completer<({int bytes, Uint8List buffer})>();
    var future = _readCompleter!.future;
    _pendingReadBuffer = buffer;
    _tryRead();
    return future;
  }

  @override
  Future<({int bytes, Uint8List buffer})> write(Uint8List buffer) {
    if (buffer.lengthInBytes == 0) {
      return Future.value((bytes: 0, buffer: buffer));
    }
    if (_writeCompleter != null || _writeListCompleter != null) {
      throw StateError("A write operation is already pending.");
    }
    _writeCompleter = Completer<({int bytes, Uint8List buffer})>();
    var future = _writeCompleter!.future;
    _pendingWriteBuffer = buffer;
    // Always ensure we are listening when a write is initiated.
    _socket.setListening(read: true, write: true, issueEvents: false);
    _tryWrite();
    return future;
  }

  @override
  Future<({int bytes, List<Uint8List> buffers})> writeList(List<Uint8List> buffers) {
    if (buffers.isEmpty) {
      return Future.value((bytes: 0, buffers: buffers));
    }
    if (_writeCompleter != null || _writeListCompleter != null) {
      throw StateError("A write operation is already pending.");
    }
    _writeListCompleter = Completer<({int bytes, List<Uint8List> buffers})>();
    var future = _writeListCompleter!.future;
    _pendingWriteListBuffers = buffers;
    // Always ensure we are listening when a write is initiated.
    _socket.setListening(read: true, write: true, issueEvents: false);
    _tryWrite();
    return future;
  }

  @override
  Future<void> close() async {
    _socket.close();
    _completeAllWithError(SocketException("Socket closed"));
  }

  @pragma("vm:external-name", "Socket2_ReadInto")
  external static int _nativeReadInto(
    _NativeSocket socket,
    Uint8List buffer,
    int offset,
    int length,
  );

  @pragma("vm:external-name", "Socket2_WriteFrom")
  external static int _nativeWriteFrom(
    _NativeSocket socket,
    Uint8List buffer,
    int offset,
    int length,
  );

  @pragma("vm:external-name", "Socket2_WriteList")
  external static int _nativeWriteList(
    _NativeSocket socket,
    List<Uint8List> buffers,
  );
}
