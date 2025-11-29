import 'dart:typed_data';
import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';

const bool _p2pLoggingEnabled = true;

void _p2pLog(String message) {
  if (!_p2pLoggingEnabled) {
    return;
  }
  print(message);
}

class P2PMessage {
  final String command;
  final Uint8List payload;

  P2PMessage({
    required this.command,
    required this.payload,
  });

  static const int magicBytes = 0xd17cbee4;
  static const int headerLength = 24;

  Uint8List serialize() {
    final buffer = <int>[];
    
    _writeUint32LE(buffer, magicBytes);
    
    final commandBytes = Uint8List(12);
    final cmdBytes = command.codeUnits;
    for (var i = 0; i < cmdBytes.length && i < 12; i++) {
      commandBytes[i] = cmdBytes[i];
    }
    buffer.addAll(commandBytes);
    
    _writeUint32LE(buffer, payload.length);
    
    final checksum = _calculateChecksum(payload);
    buffer.addAll(checksum);
    
    buffer.addAll(payload);
    
    return Uint8List.fromList(buffer);
  }

  static P2PMessage? parse(Uint8List data) {
    if (data.length < headerLength) return null;

    final magic = _readUint32LE(data, 0);
    if (magic != magicBytes) {
      _p2pLog('P2P: Warning - Expected magic 0x${magicBytes.toRadixString(16)}, got 0x${magic.toRadixString(16)}');
      return null;
    }

    final commandBytes = data.sublist(4, 16);
    var commandLength = 0;
    for (var i = 0; i < 12; i++) {
      if (commandBytes[i] == 0) break;
      commandLength++;
    }
    final command = String.fromCharCodes(commandBytes.sublist(0, commandLength));

    final payloadLength = _readUint32LE(data, 16);
    final checksumExpected = data.sublist(20, 24);

    if (data.length < headerLength + payloadLength) return null;

    final payload = data.sublist(headerLength, headerLength + payloadLength);
    final checksumActual = _calculateChecksum(payload);

    if (!_compareBytes(checksumExpected, checksumActual)) {
      _p2pLog('P2P: Checksum mismatch for $command');
      return null;
    }

    return P2PMessage(command: command, payload: payload);
  }

  static Uint8List _calculateChecksum(Uint8List data) {
    final hash1 = sha256.convert(data);
    final hash2 = sha256.convert(hash1.bytes);
    return Uint8List.fromList(hash2.bytes.sublist(0, 4));
  }

  static void _writeUint32LE(List<int> buffer, int value) {
    buffer.add(value & 0xff);
    buffer.add((value >> 8) & 0xff);
    buffer.add((value >> 16) & 0xff);
    buffer.add((value >> 24) & 0xff);
  }

  static int _readUint32LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static bool _compareBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class P2PConnection {
  final String host;
  final int port;
  Socket? _socket;
  final _messageController = StreamController<P2PMessage>.broadcast();
  final _buffer = <int>[];

  P2PConnection({
    required this.host,
    required this.port,
  });

  Stream<P2PMessage> get messages => _messageController.stream;

  Future<void> connect() async {
    _p2pLog('P2P: Connecting to $host:$port');
    
    try {
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 10));
      _p2pLog('P2P: Connected successfully');
      
      _socket!.listen(
        _onData,
        onError: _onError,
        onDone: _onDone,
      );

      await _sendVersion();
    } catch (e) {
      _p2pLog('P2P: Connection failed - $e');
      rethrow;
    }
  }

  void _onData(Uint8List data) {
    _p2pLog('P2P: Received ${data.length} bytes, buffer was ${_buffer.length} bytes');
    _buffer.addAll(data);
    _p2pLog('P2P: Buffer now ${_buffer.length} bytes');
    _processBuffer();
  }

  void _processBuffer() {
    int iterations = 0;
    while (true) {
      iterations++;
      if (iterations > 100) {
        _p2pLog('P2P: WARNING - _processBuffer exceeded 100 iterations, breaking');
        break;
      }
      
      if (_buffer.length < P2PMessage.headerLength) {
        if (_buffer.isNotEmpty) {
          _p2pLog('P2P: Buffer has ${_buffer.length} bytes, waiting for more (need ${P2PMessage.headerLength} for header)');
        }
        return;
      }

      final headerBytes = Uint8List.fromList(_buffer.sublist(0, P2PMessage.headerLength));
      final magic = P2PMessage._readUint32LE(headerBytes, 0);

      if (magic != P2PMessage.magicBytes) {
        _p2pLog('P2P: Desynced - expected 0x${P2PMessage.magicBytes.toRadixString(16)}, got 0x${magic.toRadixString(16)}, shifting');
        _buffer.removeAt(0);
        continue;
      }

      final payloadLength = P2PMessage._readUint32LE(headerBytes, 16);
      final totalLength = P2PMessage.headerLength + payloadLength;

      if (_buffer.length < totalLength) {
        _p2pLog('P2P: Buffer has ${_buffer.length} bytes, waiting for $totalLength (payload=$payloadLength)');
        return;
      }

      final messageBytes = Uint8List.fromList(_buffer.sublist(0, totalLength));

      try {
        final message = P2PMessage.parse(messageBytes);
        if (message == null) {
          _p2pLog('P2P: Failed to parse message (checksum mismatch?), shifting');
          _buffer.removeAt(0);
          continue;
        }

        _buffer.removeRange(0, totalLength);
        _p2pLog('P2P: Parsed ${message.command} (${message.payload.length} bytes), buffer now ${_buffer.length} bytes');
        _messageController.add(message);
      } catch (e) {
        _p2pLog('P2P: Error parsing message - $e');
        _buffer.removeAt(0);
      }
    }
  }

  void _onError(error) {
    _p2pLog('P2P: Socket error - $error');
    _p2pLog('P2P: Buffer had ${_buffer.length} bytes when error occurred');
    _messageController.addError(error);
  }

  void _onDone() {
    _p2pLog('P2P: Connection closed by peer');
    _p2pLog('P2P: Buffer had ${_buffer.length} bytes when connection closed');
    if (_buffer.isNotEmpty && _buffer.length >= 4) {
      final magic = P2PMessage._readUint32LE(Uint8List.fromList(_buffer.sublist(0, 4)), 0);
      _p2pLog('P2P: First 4 bytes in buffer: 0x${magic.toRadixString(16).padLeft(8, '0')}');
    }
    _messageController.close();
  }

  Future<void> _sendVersion() async {
    final payload = <int>[];
    
    _writeInt32LE(payload, 70015);
    _writeUint64LE(payload, 1);
    _writeInt64LE(payload, DateTime.now().millisecondsSinceEpoch ~/ 1000);
    
    for (var i = 0; i < 26; i++) payload.add(0);
    for (var i = 0; i < 26; i++) payload.add(0);
    
    _writeUint64LE(payload, 0);
    
    payload.add(0);
    
    _writeInt32LE(payload, 0);
    
    payload.add(0);

    final message = P2PMessage(
      command: 'version',
      payload: Uint8List.fromList(payload),
    );

    _socket!.add(message.serialize());
    _p2pLog('P2P: Sent version message');
  }

  Future<void> sendMessage(P2PMessage message) async {
    if (_socket == null) {
      _p2pLog('P2P: Cannot send ${message.command} - not connected');
      throw Exception('Not connected');
    }
    final serialized = message.serialize();
    _p2pLog('P2P: Sending ${message.command} (${serialized.length} bytes total, payload=${message.payload.length} bytes)');
    if (message.command == 'tx' || message.command == 'inv') {
      _p2pLog('P2P: Full message hex for ${message.command}: ${_bytesToHex(serialized)}');
    }
    _socket!.add(serialized);
    _p2pLog('P2P: Sent ${message.command} to socket');
  }
  
  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static void _writeInt32LE(List<int> buffer, int value) {
    buffer.add(value & 0xff);
    buffer.add((value >> 8) & 0xff);
    buffer.add((value >> 16) & 0xff);
    buffer.add((value >> 24) & 0xff);
  }

  static void _writeInt64LE(List<int> buffer, int value) {
    buffer.add(value & 0xff);
    buffer.add((value >> 8) & 0xff);
    buffer.add((value >> 16) & 0xff);
    buffer.add((value >> 24) & 0xff);
    buffer.add((value >> 32) & 0xff);
    buffer.add((value >> 40) & 0xff);
    buffer.add((value >> 48) & 0xff);
    buffer.add((value >> 56) & 0xff);
  }

  static void _writeUint64LE(List<int> buffer, int value) {
    _writeInt64LE(buffer, value);
  }

  void disconnect() {
    _socket?.close();
    _socket = null;
  }
}


