import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'p2p_connection.dart';
import 'peer.dart';
import '../utils/binary_utils.dart';

const bool _peerManagerLoggingEnabled = false;

void _peerManagerLog(String message) {
  if (!_peerManagerLoggingEnabled) {
    return;
  }
  print(message);
}

typedef PeerMessageHandler = void Function(Peer peer, P2PMessage message);
typedef PeerEventHandler = void Function(Peer peer);

class PeerManager {
  final String seedHost;
  final int seedPort;
  final bool enableDiscovery;
  final int maxConnections;
  final Duration keepAliveInterval;
  final Duration reconnectDelay;

  final Map<String, Peer> _peers = {};
  final Queue<PeerAddress> _pendingPeers = Queue<PeerAddress>();
  final Set<String> _pendingPeerIds = <String>{};
  final Set<String> _connectingPeers = <String>{};
  final Set<String> _bannedPeers = <String>{};
  final Set<String> _favoritePeers = <String>{};
  
  Timer? _keepAliveTimer;
  Timer? _reconnectTimer;
  bool _isShuttingDown = false;
  Duration _currentReconnectDelay;
  int _headerPeerCursor = -1;
  int _filterPeerCursor = -1;
  int _pingNonceCounter = 0;

  PeerMessageHandler? onMessage;
  PeerEventHandler? onPeerConnected;
  PeerEventHandler? onPeerDisconnected;
  void Function()? onConnectionStateChanged;
  void Function()? onPeerListChanged;

  PeerManager({
    required this.seedHost,
    required this.seedPort,
    this.enableDiscovery = false,
    this.maxConnections = 1,
    this.keepAliveInterval = const Duration(seconds: 30),
    this.reconnectDelay = const Duration(seconds: 30),
  }) : _currentReconnectDelay = reconnectDelay;

  bool get isConnected => _peers.isNotEmpty;
  int get peerCount => _peers.length;
  List<Peer> get activePeers => _peers.values.where((p) => p.handshakeComplete).toList();
  
  List<PeerInfo> get peerInfoList {
    return _peers.values.map((p) => PeerInfo.fromPeer(p)).toList();
  }
  
  Set<String> get bannedPeers => Set.unmodifiable(_bannedPeers);
  Set<String> get favoritePeers => Set.unmodifiable(_favoritePeers);

  void setBannedPeers(List<String> peers) {
    _bannedPeers.clear();
    _bannedPeers.addAll(peers);
  }

  void setFavoritePeers(List<String> peers) {
    _favoritePeers.clear();
    _favoritePeers.addAll(peers);
  }

  void banPeer(String peerId) {
    _bannedPeers.add(peerId);
    final peer = _peers[peerId];
    if (peer != null) {
      _removePeer(peer);
    }
    _pendingPeers.removeWhere((p) => p.id == peerId);
    _pendingPeerIds.remove(peerId);
    onPeerListChanged?.call();
  }

  void unbanPeer(String peerId) {
    _bannedPeers.remove(peerId);
    onPeerListChanged?.call();
  }

  void addFavorite(String peerId) {
    _favoritePeers.add(peerId);
    onPeerListChanged?.call();
  }

  void removeFavorite(String peerId) {
    _favoritePeers.remove(peerId);
    onPeerListChanged?.call();
  }

  bool isPeerBanned(String peerId) => _bannedPeers.contains(peerId);
  bool isPeerFavorite(String peerId) => _favoritePeers.contains(peerId);

  List<PeerInfo> getSortedPeerList() {
    final peers = peerInfoList;
    peers.sort((a, b) {
      final aFav = _favoritePeers.contains(a.id) ? 0 : 1;
      final bFav = _favoritePeers.contains(b.id) ? 0 : 1;
      if (aFav != bFav) return aFav.compareTo(bFav);
      
      final aSeed = a.isSeed ? 0 : 1;
      final bSeed = b.isSeed ? 0 : 1;
      if (aSeed != bSeed) return aSeed.compareTo(bSeed);
      
      final aPing = a.pingTimeMs ?? 999999;
      final bPing = b.pingTimeMs ?? 999999;
      return aPing.compareTo(bPing);
    });
    return peers;
  }

  Future<void> connectToPeer(String host, int port) async {
    final id = '$host:$port';
    if (_bannedPeers.contains(id)) return;
    if (_peers.containsKey(id)) return;
    
    await _connectToPeer(host: host, port: port, isSeed: false);
  }

  void removePeerById(String peerId) {
    final peer = _peers[peerId];
    if (peer != null) {
      _removePeer(peer);
    }
  }

  Future<void> connect() async {
    _isShuttingDown = false;
    await _connectToPeer(host: seedHost, port: seedPort, isSeed: true, throwOnFailure: true);
    _startKeepAliveTimer();
  }

  Future<Peer?> _connectToPeer({
    required String host,
    required int port,
    bool isSeed = false,
    bool throwOnFailure = false,
  }) async {
    final id = '$host:$port';
    if (_bannedPeers.contains(id) && !isSeed) {
      _peerManagerLog('PeerManager: Peer $id is banned, skipping');
      return null;
    }
    if (_peers.containsKey(id)) {
      return _peers[id];
    }

    _peerManagerLog('PeerManager: Connecting to $id');
    final connection = P2PConnection(host: host, port: port);
    
    try {
      await connection.connect();
    } catch (e) {
      _peerManagerLog('PeerManager: Failed to connect to $id - $e');
      if (throwOnFailure) rethrow;
      return null;
    }

    final peer = Peer(id: id, connection: connection, isSeed: isSeed);
    
    peer.subscription = connection.messages.listen(
      (message) => _handleMessage(peer, message),
      onError: (error) => _handlePeerError(peer, error),
      onDone: () => _handlePeerClosed(peer),
    );

    _peers[id] = peer;
    _peerManagerLog('PeerManager: Connected to $id');
    _emitConnectionStateChanged();
    onPeerListChanged?.call();
    return peer;
  }

  void _handleMessage(Peer peer, P2PMessage message) {
    peer.markMessageReceived();
    onMessage?.call(peer, message);
  }

  void _handlePeerError(Peer peer, Object error) {
    _peerManagerLog('PeerManager: Peer ${peer.id} error - $error');
    _peerManagerLog('PeerManager: Peer handshake was ${peer.handshakeComplete ? "complete" : "incomplete"}');
    _removePeer(peer);
    _scheduleReconnect();
  }

  void _handlePeerClosed(Peer peer) {
    _peerManagerLog('PeerManager: Peer ${peer.id} connection closed');
    _peerManagerLog('PeerManager: Peer handshake was ${peer.handshakeComplete ? "complete" : "incomplete"}');
    _peerManagerLog('PeerManager: Last message from peer: ${peer.lastMessage}');
    _peerManagerLog('PeerManager: Time since last message: ${DateTime.now().difference(peer.lastMessage).inSeconds}s');
    _removePeer(peer);
    _scheduleReconnect();
  }

  void _removePeer(Peer peer) {
    peer.dispose();
    _peers.remove(peer.id);
    onPeerDisconnected?.call(peer);
    _emitConnectionStateChanged();
    onPeerListChanged?.call();
  }

  void _startKeepAliveTimer() {
    _keepAliveTimer ??= Timer.periodic(keepAliveInterval, (_) {
      _sendKeepAlive();
      if (enableDiscovery) {
        _maybeConnectMorePeers();
      }
    });
  }

  void _sendKeepAlive() {
    _pingNonceCounter++;
    final nonce = _pingNonceCounter;
    final payload = <int>[];
    BinaryUtils.writeUint64LE(payload, nonce);
    final ping = Uint8List.fromList(payload);
    
    for (final peer in _peers.values) {
      if (!peer.handshakeComplete) continue;
      peer.markPingSent(nonce);
      final message = P2PMessage(command: 'ping', payload: ping);
      peer.connection.sendMessage(message);
    }
  }

  void handlePong(Peer peer, Uint8List payload) {
    if (payload.length >= 8) {
      final nonce = BinaryUtils.readUint64LE(payload, 0);
      peer.handlePong(nonce);
      onPeerListChanged?.call();
    }
  }

  void forceReconnectNow() {
    if (_isShuttingDown) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectNow();
  }

  void _scheduleReconnect() {
    if (_isShuttingDown || _reconnectTimer != null) return;
    
    _reconnectTimer = Timer(_currentReconnectDelay, _reconnectNow);
  }

  Future<void> _reconnectNow() async {
    _reconnectTimer = null;
    if (_isShuttingDown) return;
    
    if (_peers.length >= maxConnections) {
      _resetReconnectDelay();
      return;
    }
    
    if (enableDiscovery) {
      _maybeConnectMorePeers();
    } else {
      await _connectToPeer(host: seedHost, port: seedPort, isSeed: true);
    }
    
    if (_peers.isEmpty) {
      _increaseReconnectDelay();
      _scheduleReconnect();
    } else {
      _resetReconnectDelay();
    }
  }

  void _resetReconnectDelay() {
    _currentReconnectDelay = reconnectDelay;
  }

  void _increaseReconnectDelay() {
    const maxDelay = Duration(seconds: 30);
    final nextMillis = (_currentReconnectDelay.inMilliseconds * 2)
        .clamp(reconnectDelay.inMilliseconds, maxDelay.inMilliseconds);
    _currentReconnectDelay = Duration(milliseconds: nextMillis);
  }

  void _maybeConnectMorePeers() {
    if (!enableDiscovery) return;
    
    while ((_peers.length + _connectingPeers.length) < maxConnections && _pendingPeers.isNotEmpty) {
      final peer = _pendingPeers.removeFirst();
      _pendingPeerIds.remove(peer.id);
      
      if (_peers.containsKey(peer.id) || _connectingPeers.contains(peer.id) || peer.port <= 0) {
        continue;
      }
      
      _connectingPeers.add(peer.id);
      _connectToPeer(host: peer.host, port: peer.port).whenComplete(() {
        _connectingPeers.remove(peer.id);
      });
    }
  }

  void enqueuePeerAddress(PeerAddress address) {
    if (_peers.containsKey(address.id)) return;
    if (_connectingPeers.contains(address.id)) return;
    if (_pendingPeerIds.contains(address.id)) return;
    if (_bannedPeers.contains(address.id)) return;
    if (address.host == seedHost && address.port == seedPort) return;
    if (address.port <= 0 || address.port > 65535) return;
    
    _pendingPeers.add(address);
    _pendingPeerIds.add(address.id);
  }

  Peer? selectPeerForHeaders({Peer? preferred}) {
    final peers = activePeers;
    if (peers.isEmpty) return null;
    if (preferred != null && preferred.handshakeComplete) return preferred;
    
    _headerPeerCursor = (_headerPeerCursor + 1) % peers.length;
    return peers[_headerPeerCursor];
  }

  Peer? selectPeerForFilters({Peer? preferred}) {
    final allActive = activePeers;
    final peers = allActive.where((p) => p.supportsCompactFilters).toList();
    if (peers.isEmpty) {
      _peerManagerLog('PeerManager: selectPeerForFilters - no filter peers (active=${allActive.length}, filter-capable=0)');
      for (final p in allActive) {
        _peerManagerLog('PeerManager:   ${p.id} - supportsFilters=${p.supportsCompactFilters}, services=0x${p.serviceFlags.toRadixString(16)}');
      }
      return null;
    }
    if (preferred != null && preferred.handshakeComplete && preferred.supportsCompactFilters) {
      return preferred;
    }
    
    _filterPeerCursor = (_filterPeerCursor + 1) % peers.length;
    return peers[_filterPeerCursor];
  }

  Peer? selectPeerForData({Peer? preferred, bool requireFilters = false}) {
    final peers = activePeers.where((p) => !requireFilters || p.supportsCompactFilters).toList();
    if (peers.isEmpty) return null;
    if (preferred != null && preferred.handshakeComplete && (!requireFilters || preferred.supportsCompactFilters)) {
      return preferred;
    }
    return peers.first;
  }

  void sendToAll(P2PMessage message) {
    for (final peer in activePeers) {
      peer.connection.sendMessage(message);
    }
  }

  void disconnect() {
    _isShuttingDown = true;
    
    for (final peer in _peers.values) {
      peer.dispose();
    }
    _peers.clear();
    _pendingPeers.clear();
    _pendingPeerIds.clear();
    
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    
    _emitConnectionStateChanged();
  }

  void _emitConnectionStateChanged() {
    onConnectionStateChanged?.call();
  }

  String? decodeIp(Uint8List bytes) {
    try {
      final address = InternetAddress.fromRawAddress(bytes);
      return address.address;
    } catch (_) {
      return null;
    }
  }

  String? decodeAddrV2(int networkId, Uint8List addrBytes) {
    try {
      switch (networkId) {
        case 1:
          if (addrBytes.length != 4) return null;
          return InternetAddress.fromRawAddress(addrBytes).address;
        case 2:
          if (addrBytes.length != 16) return null;
          return InternetAddress.fromRawAddress(addrBytes).address;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}

