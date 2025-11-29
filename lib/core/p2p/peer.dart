import 'dart:async';
import 'p2p_connection.dart';

const int serviceCompactFiltersFlag = 1 << 6;

class Peer {
  final String id;
  final P2PConnection connection;
  final bool isSeed;
  
  StreamSubscription<P2PMessage>? subscription;
  bool versionAcked = false;
  bool verackReceived = false;
  bool handshakeComplete = false;
  DateTime lastMessage = DateTime.now();
  int serviceFlags = 0;
  bool supportsCompactFilters = false;
  bool addrV2Requested = false;
  bool sendHeadersRequested = false;
  bool sendCmpctRequested = false;
  DateTime? lastAddrRequest;
  
  int? _pingTimeMs;
  DateTime? _lastPingSent;
  int? _lastPingNonce;

  Peer({
    required this.id,
    required this.connection,
    required this.isSeed,
  });

  int? get pingTimeMs => _pingTimeMs;

  void updateServices(int services) {
    serviceFlags = services;
    supportsCompactFilters = (services & serviceCompactFiltersFlag) != 0;
  }

  void markMessageReceived() {
    lastMessage = DateTime.now();
  }

  void markPingSent(int nonce) {
    _lastPingSent = DateTime.now();
    _lastPingNonce = nonce;
  }

  void handlePong(int nonce) {
    if (_lastPingSent != null && _lastPingNonce == nonce) {
      _pingTimeMs = DateTime.now().difference(_lastPingSent!).inMilliseconds;
      _lastPingSent = null;
      _lastPingNonce = null;
    }
  }

  void dispose() {
    subscription?.cancel();
    connection.disconnect();
  }
}

class PeerAddress {
  final String host;
  final int port;
  final int timestamp;
  final int services;

  PeerAddress({
    required this.host,
    required this.port,
    required this.timestamp,
    required this.services,
  });

  String get id => '$host:$port';
}

class PeerInfo {
  final String id;
  final String host;
  final int port;
  final bool isSeed;
  final bool isConnected;
  final bool supportsCompactFilters;
  final int? pingTimeMs;
  final DateTime lastMessage;

  PeerInfo({
    required this.id,
    required this.host,
    required this.port,
    required this.isSeed,
    required this.isConnected,
    required this.supportsCompactFilters,
    this.pingTimeMs,
    required this.lastMessage,
  });

  static PeerInfo fromPeer(Peer peer) {
    final parts = peer.id.split(':');
    return PeerInfo(
      id: peer.id,
      host: parts.isNotEmpty ? parts[0] : peer.id,
      port: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      isSeed: peer.isSeed,
      isConnected: peer.handshakeComplete,
      supportsCompactFilters: peer.supportsCompactFilters,
      pingTimeMs: peer.pingTimeMs,
      lastMessage: peer.lastMessage,
    );
  }
}

