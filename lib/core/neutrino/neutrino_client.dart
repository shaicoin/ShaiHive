import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../chain/block_header.dart';
import '../chain/chain_params.dart';
import '../chain/chain_state.dart';
import '../p2p/p2p_connection.dart';
import '../p2p/peer.dart';
import '../p2p/peer_manager.dart';
import '../sync/header_sync.dart';
import '../sync/filter_sync.dart';
import '../utils/binary_utils.dart';

const bool _neutrinoLoggingEnabled = true;

void _neutrinoLog(String message) {
  if (!_neutrinoLoggingEnabled) {
    return;
  }
  print(message);
}

typedef NeutrinoClientListener = void Function();
typedef ReorgCallback = void Function(int oldHeight, int newHeight, int commonAncestor);
typedef MempoolTxCallback = void Function(Uint8List rawTx);

enum SyncPhase { idle, headers, filters, complete }

class NeutrinoClient {
  final String nodeHost;
  final int nodeP2PPort;
  final ChainParams chainParams;
  final bool enablePeerDiscovery;
  final int maxPeerConnections;
  final Duration keepAliveInterval;
  final Duration reconnectDelay;

  late final ChainState _chainState;
  late final PeerManager _peerManager;
  late final HeaderSync _headerSync;
  late final FilterSync _filterSync;
  
  final Map<String, Uint8List> _blocks = {};
  final Map<String, Completer<Uint8List?>> _pendingBlockRequests = {};
  final Map<String, Uint8List> _broadcastTxs = {};
  final Map<String, Completer<Uint8List?>> _pendingTxRequests = {};
  final Set<String> _mempoolTxHashes = {};
  bool _mempoolScanActive = false;
  List<Uint8List>? _mempoolWatchScripts;
  
  int _minFeeRateSatPerByte = 1;
  
  bool _isConnected = false;
  bool _isSyncing = false;
  String? _syncError;
  SyncPhase _syncPhase = SyncPhase.idle;

  NeutrinoClientListener? onStateChanged;
  ReorgCallback? onReorg;
  void Function(int height)? onNewBlock;
  MempoolTxCallback? onMempoolTx;

  NeutrinoClient({
    required this.nodeHost,
    required this.nodeP2PPort,
    required this.chainParams,
    this.enablePeerDiscovery = false,
    int maxPeerConnections = 1,
    this.keepAliveInterval = const Duration(seconds: 30),
    this.reconnectDelay = const Duration(seconds: 30),
  }) : maxPeerConnections = maxPeerConnections.clamp(1, 16).toInt() {
    _chainState = ChainState(chainParams: chainParams);
    
    _peerManager = PeerManager(
      seedHost: nodeHost,
      seedPort: nodeP2PPort,
      enableDiscovery: enablePeerDiscovery,
      maxConnections: this.maxPeerConnections,
      keepAliveInterval: keepAliveInterval,
      reconnectDelay: reconnectDelay,
    );
    
    _headerSync = HeaderSync(
      chainParams: chainParams,
      chainState: _chainState,
      peerManager: _peerManager,
    );
    
    _filterSync = FilterSync(
      chainState: _chainState,
      peerManager: _peerManager,
    );
    
    _setupCallbacks();
  }

  void _setupCallbacks() {
    _peerManager.onMessage = _handleMessage;
    _peerManager.onConnectionStateChanged = _onConnectionStateChanged;
    _peerManager.onPeerListChanged = () => onPeerListChanged?.call();
    _chainState.onStateChanged = _emitStateChanged;
    _headerSync.onSyncProgress = _emitStateChanged;
    _headerSync.onNewBlock = (height) => onNewBlock?.call(height);
  }

  bool get isConnected => _isConnected;
  bool get isSyncing => _isSyncing;
  bool get isAtTip => _headerSync.isAtTip;
  bool get hasPeerReady => _peerManager.activePeers.isNotEmpty;
  int get blockHeight => _chainState.height;
  int get cachedHeaderCount => _chainState.height;
  String? get syncError => _syncError ?? _headerSync.syncError ?? _filterSync.syncError;
  int get targetHeight => _headerSync.syncTargetHeight;
  SyncPhase get syncPhase => _syncPhase;
  
  double get syncProgress {
    if (_headerSync.syncTargetHeight == 0) return 0;
    final progress = _chainState.height / _headerSync.syncTargetHeight;
    return progress.clamp(0.0, 1.0);
  }

  int get minFeeRateSatPerByte => _minFeeRateSatPerByte;

  List<PeerInfo> get peerInfoList => _peerManager.getSortedPeerList();
  Set<String> get bannedPeers => _peerManager.bannedPeers;
  Set<String> get favoritePeers => _peerManager.favoritePeers;

  void Function()? onPeerListChanged;

  void setBannedPeers(List<String> peers) => _peerManager.setBannedPeers(peers);
  void setFavoritePeers(List<String> peers) => _peerManager.setFavoritePeers(peers);
  void banPeer(String peerId) => _peerManager.banPeer(peerId);
  void unbanPeer(String peerId) => _peerManager.unbanPeer(peerId);
  void addFavoritePeer(String peerId) => _peerManager.addFavorite(peerId);
  void removeFavoritePeer(String peerId) => _peerManager.removeFavorite(peerId);
  void disconnectPeer(String peerId) => _peerManager.removePeerById(peerId);
  Future<void> connectToPeer(String host, int port) => _peerManager.connectToPeer(host, port);

  BlockHeader? getHeaderAtHeight(int height) => _chainState.getHeader(height);
  Uint8List? getBlockHashAtHeight(int height) => _chainState.getBlockHash(height);
  String? getBlockHashHexAtHeight(int height) => _chainState.getBlockHashHex(height);

  Future<void> loadCachedState() async {
    await _chainState.init();
    _headerSync.setTargetHeight(_chainState.height);
    if (_chainState.height > 0) {
      _syncPhase = SyncPhase.complete;
    }
  }

  Future<void> connect() async {
    _neutrinoLog('Neutrino: Connecting to $nodeHost:$nodeP2PPort');
    
    try {
      await _chainState.init();
      await _peerManager.connect();
    } catch (e) {
      _neutrinoLog('Neutrino: Connection failed - $e');
      _syncError = e.toString();
      _isConnected = false;
      rethrow;
    }
  }

  void _onConnectionStateChanged() {
    final connected = _peerManager.isConnected;
    _neutrinoLog('Neutrino: Connection state changed - connected=$connected, wasConnected=$_isConnected');
    _neutrinoLog('Neutrino: Current state - phase=$_syncPhase, isSyncing=$_isSyncing, isAtTip=${_headerSync.isAtTip}');
    _neutrinoLog('Neutrino: Heights - local=${_chainState.height}, target=${_headerSync.syncTargetHeight}');
    
    if (_isConnected != connected) {
      _isConnected = connected;
      if (!connected) {
        _neutrinoLog('Neutrino: DISCONNECTED - sync phase was $_syncPhase');
        if (_syncPhase == SyncPhase.headers || _syncPhase == SyncPhase.filters) {
          _neutrinoLog('Neutrino: Mid-sync disconnect, forcing immediate reconnect');
          _peerManager.forceReconnectNow();
        }
      } else if (connected && _headerSync.isAtTip && _syncPhase != SyncPhase.complete) {
        _neutrinoLog('Neutrino: Reconnected and at tip, marking sync complete');
        _syncPhase = SyncPhase.complete;
        _isSyncing = false;
      }
      _emitStateChanged();
    }
  }

  void _handleMessage(Peer peer, P2PMessage message) {
    try {
      if (message.command == 'pong' || message.command == 'ping') {
        _neutrinoLog('Neutrino: Received ${message.command} from ${peer.id} (${message.payload.length} bytes)');
      } else {
        _neutrinoLog('Neutrino: >>> Received ${message.command} from ${peer.id} (${message.payload.length} bytes)');
      }
      
      switch (message.command) {
        case 'version':
          _handleVersion(peer, message.payload);
          _sendVerAck(peer);
          break;
        case 'verack':
          if (!peer.handshakeComplete) {
            peer.verackReceived = true;
            peer.handshakeComplete = true;
            _neutrinoLog('Neutrino: Handshake complete with ${peer.id}');
            _onPeerHandshakeComplete(peer);
          }
          break;
        case 'headers':
          _headerSync.handleHeaders(peer, message.payload);
          break;
        case 'cfheaders':
          _filterSync.handleFilterHeaders(peer, message.payload);
          break;
        case 'cfcheckpt':
          _filterSync.handleFilterCheckpoint(peer, message.payload);
          break;
        case 'cfilter':
          _neutrinoLog('Neutrino: Received cfilter (${message.payload.length} bytes)');
          _filterSync.handleFilter(message.payload);
          break;
        case 'block':
          _handleBlock(message.payload);
          break;
        case 'tx':
          _handleTx(message.payload);
          break;
        case 'ping':
          _handlePing(peer, message.payload);
          break;
        case 'inv':
          _handleInv(peer, message.payload);
          break;
        case 'addr':
          _handleAddr(peer, message.payload);
          break;
        case 'addrv2':
          _handleAddrV2(peer, message.payload);
          break;
        case 'getheaders':
          _handleGetHeadersRequest(peer);
          break;
        case 'notfound':
          _handleNotFound(message.payload);
          break;
        case 'reject':
          _handleReject(message.payload);
          break;
        case 'sendheaders':
        case 'sendcmpct':
          break;
        case 'feefilter':
          _handleFeeFilter(message.payload);
          break;
        case 'pong':
          _peerManager.handlePong(peer, message.payload);
          break;
        case 'cmpctblock':
          _handleCompactBlock(peer, message.payload);
          break;
        case 'getdata':
          _handleGetData(peer, message.payload);
          break;
        default:
          _neutrinoLog('Neutrino: Unhandled message: ${message.command}');
      }
    } catch (e) {
      _neutrinoLog('Neutrino: Error handling ${message.command} - $e');
      _syncError = 'Error handling ${message.command}: $e';
    }
  }

  void _handleVersion(Peer peer, Uint8List payload) {
    if (payload.length >= 12) {
      final services = BinaryUtils.readUint64LE(payload, 4);
      peer.updateServices(services);
      _neutrinoLog('Neutrino: Peer ${peer.id} services=0x${services.toRadixString(16)}, supportsFilters=${peer.supportsCompactFilters}');
    }
    final remoteHeight = _extractStartHeight(payload);
    if (remoteHeight != null && remoteHeight > 0) {
      final wasAtTip = _headerSync.isAtTip;
      _headerSync.setTargetHeight(remoteHeight);
    _neutrinoLog('Neutrino: Peer start height reported as $remoteHeight, local=${_chainState.height}, wasAtTip=$wasAtTip');
      if (wasAtTip && !_headerSync.isAtTip && _syncPhase == SyncPhase.complete) {
        _neutrinoLog('Neutrino: Was at tip but peer has more blocks, resetting to idle');
        _syncPhase = SyncPhase.idle;
      }
      _emitStateChanged();
    }
  }

  void _sendVerAck(Peer peer) {
    if (peer.versionAcked) return;
    peer.versionAcked = true;
    _neutrinoLog('Neutrino: Sending verack to ${peer.id}');
    final message = P2PMessage(command: 'verack', payload: Uint8List(0));
    peer.connection.sendMessage(message);
  }

  void _onPeerHandshakeComplete(Peer peer) {
    _sendSendHeaders(peer);
    _sendSendCmpct(peer);
    if (enablePeerDiscovery) {
      _sendAddrV2(peer);
      _requestAddr(peer, force: true);
    }
    _resumeSyncForPeer(peer);
  }

  void _resumeSyncForPeer(Peer peer) {
    final headersSynced = _headerSync.isAtTip;
    
    if (headersSynced) {
      if (_syncPhase != SyncPhase.complete) {
        _syncPhase = SyncPhase.complete;
        _isSyncing = false;
        _emitStateChanged();
      }
      return;
    }
    
    switch (_syncPhase) {
      case SyncPhase.idle:
      case SyncPhase.headers:
        unawaited(_headerSync.requestHeaders(preferredPeer: peer, force: true));
        break;
      case SyncPhase.filters:
      case SyncPhase.complete:
        break;
    }
  }

  void _sendSendHeaders(Peer peer) {
    if (peer.sendHeadersRequested) return;
    peer.sendHeadersRequested = true;
    final message = P2PMessage(command: 'sendheaders', payload: Uint8List(0));
    peer.connection.sendMessage(message);
  }

  void _sendSendCmpct(Peer peer) {
    if (peer.sendCmpctRequested) return;
    peer.sendCmpctRequested = true;
    final payload = <int>[];
    payload.add(1);
    BinaryUtils.writeUint64LE(payload, 2);
    final message = P2PMessage(command: 'sendcmpct', payload: Uint8List.fromList(payload));
    peer.connection.sendMessage(message);
  }

  void _sendAddrV2(Peer peer) {
    if (peer.addrV2Requested) return;
    peer.addrV2Requested = true;
    final message = P2PMessage(command: 'sendaddrv2', payload: Uint8List(0));
    peer.connection.sendMessage(message);
  }

  void _requestAddr(Peer peer, {bool force = false}) {
    if (!enablePeerDiscovery) return;
    final now = DateTime.now();
    if (!force && peer.lastAddrRequest != null && now.difference(peer.lastAddrRequest!) < const Duration(minutes: 5)) {
      return;
    }
    peer.lastAddrRequest = now;
    final message = P2PMessage(command: 'getaddr', payload: Uint8List(0));
    peer.connection.sendMessage(message);
  }

  void _handleGetHeadersRequest(Peer peer) {
    final response = P2PMessage(command: 'headers', payload: Uint8List.fromList([0]));
    peer.connection.sendMessage(response);
  }

  void _handlePing(Peer peer, Uint8List payload) {
    final message = P2PMessage(command: 'pong', payload: payload);
    peer.connection.sendMessage(message);
  }

  void _handleFeeFilter(Uint8List payload) {
    if (payload.length < 8) return;
    final feeRateSatPerKvB = BinaryUtils.readUint64LE(payload, 0);
    final feeRateSatPerByte = (feeRateSatPerKvB / 1000).ceil();
    if (feeRateSatPerByte > 0) {
      _minFeeRateSatPerByte = feeRateSatPerByte;
      _neutrinoLog('Neutrino: Received feefilter - min fee rate: $_minFeeRateSatPerByte sat/byte (${feeRateSatPerKvB} sat/kvB)');
      _emitStateChanged();
    }
  }

  void _handleAddr(Peer peer, Uint8List payload) {
    if (!enablePeerDiscovery) return;
    
    var offset = 0;
    final countResult = BinaryUtils.readVarInt(payload, offset);
    offset += countResult.bytesRead;
    final count = countResult.value;
    
    for (var i = 0; i < count; i++) {
      if (offset + 30 > payload.length) break;
      final timestamp = BinaryUtils.readUint32LE(payload, offset);
      offset += 4;
      final services = BinaryUtils.readUint64LE(payload, offset);
      offset += 8;
      final ipBytes = payload.sublist(offset, offset + 16);
      offset += 16;
      final port = (payload[offset] << 8) | payload[offset + 1];
      offset += 2;
      
      final host = _peerManager.decodeIp(ipBytes);
      if (host == null) continue;
      
      _peerManager.enqueuePeerAddress(PeerAddress(
        host: host,
        port: port,
        timestamp: timestamp,
        services: services,
      ));
    }
  }

  void _handleAddrV2(Peer peer, Uint8List payload) {
    if (!enablePeerDiscovery) return;
    
    var offset = 0;
    final countResult = BinaryUtils.readVarInt(payload, offset);
    offset += countResult.bytesRead;
    final count = countResult.value;
    
    for (var i = 0; i < count; i++) {
      if (offset + 4 > payload.length) break;
      final timestamp = BinaryUtils.readUint32LE(payload, offset);
      offset += 4;
      final servicesResult = BinaryUtils.readVarInt(payload, offset);
      offset += servicesResult.bytesRead;
      final services = servicesResult.value;
      if (offset >= payload.length) break;
      final networkId = payload[offset];
      offset++;
      final addrLenResult = BinaryUtils.readVarInt(payload, offset);
      offset += addrLenResult.bytesRead;
      final addrLen = addrLenResult.value;
      if (offset + addrLen > payload.length) break;
      final addrBytes = payload.sublist(offset, offset + addrLen);
      offset += addrLen;
      if (offset + 2 > payload.length) break;
      final port = (payload[offset] << 8) | payload[offset + 1];
      offset += 2;
      
      final host = _peerManager.decodeAddrV2(networkId, addrBytes);
      if (host == null) continue;
      
      _peerManager.enqueuePeerAddress(PeerAddress(
        host: host,
        port: port,
        timestamp: timestamp,
        services: services,
      ));
    }
  }

  void _handleNotFound(Uint8List payload) {
    try {
      var offset = 0;
      final countResult = BinaryUtils.readVarInt(payload, offset);
      offset += countResult.bytesRead;
      final count = countResult.value;
      for (var i = 0; i < count; i++) {
        if (offset + 36 > payload.length) break;
        final invType = BinaryUtils.readUint32LE(payload, offset);
        offset += 4;
        final hash = payload.sublist(offset, offset + 32);
        offset += 32;
        final typeStr = invType == 2 ? 'block' : (invType == 1 ? 'tx' : 'unknown');
        final hashHex = BinaryUtils.bytesToHex(Uint8List.fromList(hash.reversed.toList()));
        _neutrinoLog('Neutrino: Peer does not have $typeStr $hashHex');
        
        if (invType == 2) {
          final pendingRequest = _pendingBlockRequests.remove(hashHex);
          if (pendingRequest != null && !pendingRequest.isCompleted) {
            pendingRequest.complete(null);
            _neutrinoLog('Neutrino: Completed pending block request with null (notfound)');
          }
        }
      }
    } catch (e) {
      _neutrinoLog('Neutrino: Error parsing notfound - $e');
    }
  }

  void _handleReject(Uint8List payload) {
    try {
      _neutrinoLog('Neutrino: === REJECT MESSAGE RECEIVED ===');
      _neutrinoLog('Neutrino: Reject payload (${payload.length} bytes): ${BinaryUtils.bytesToHex(payload)}');
      
      var offset = 0;
      final msgResult = BinaryUtils.readVarInt(payload, offset);
      offset += msgResult.bytesRead;
      final msgLen = msgResult.value;
      final msgBytes = payload.sublist(offset, offset + msgLen);
      offset += msgLen;
      final msg = String.fromCharCodes(msgBytes);
      final code = offset < payload.length ? payload[offset] : 0;
      offset++;
      final reasonResult = BinaryUtils.readVarInt(payload, offset);
      offset += reasonResult.bytesRead;
      final reasonLen = reasonResult.value;
      final reason = offset + reasonLen <= payload.length
          ? String.fromCharCodes(payload.sublist(offset, offset + reasonLen))
          : '';
      
      String codeDescription;
      switch (code) {
        case 0x01: codeDescription = 'REJECT_MALFORMED'; break;
        case 0x10: codeDescription = 'REJECT_INVALID'; break;
        case 0x11: codeDescription = 'REJECT_OBSOLETE'; break;
        case 0x12: codeDescription = 'REJECT_DUPLICATE'; break;
        case 0x40: codeDescription = 'REJECT_NONSTANDARD'; break;
        case 0x41: codeDescription = 'REJECT_DUST'; break;
        case 0x42: codeDescription = 'REJECT_INSUFFICIENTFEE'; break;
        case 0x43: codeDescription = 'REJECT_CHECKPOINT'; break;
        default: codeDescription = 'UNKNOWN'; break;
      }
      
      _neutrinoLog('Neutrino: REJECTED - message=$msg, code=$code ($codeDescription), reason=$reason');
      
      if (msg == 'tx' && offset + 32 <= payload.length) {
        final txHash = payload.sublist(offset, offset + 32);
        final txHashHex = BinaryUtils.bytesToHex(txHash);
        final txHashDisplayHex = BinaryUtils.bytesToHex(Uint8List.fromList(txHash.reversed.toList()));
        _neutrinoLog('Neutrino: Rejected tx hash (internal): $txHashHex');
        _neutrinoLog('Neutrino: Rejected tx hash (display): $txHashDisplayHex');
      }
      
      _neutrinoLog('Neutrino: === END REJECT MESSAGE ===');
    } catch (e, stack) {
      _neutrinoLog('Neutrino: Error parsing reject - $e');
      _neutrinoLog('Neutrino: Stack: $stack');
    }
  }

  void _handleBlock(Uint8List payload) {
    try {
      _neutrinoLog('Neutrino: Received block (${payload.length} bytes)');
      
      if (payload.length < chainParams.headerLengthBytes + 1) {
        _neutrinoLog('Neutrino: Block too small');
        return;
      }
      
      final headerData = payload.sublist(0, chainParams.headerLengthBytes);
      final header = BlockHeader.parse(headerData, chainParams.headerLengthBytes);
      final blockHash = header.getHashHex();
      
      _blocks[blockHash] = payload;
      _neutrinoLog('Neutrino: Stored block $blockHash');
      
      final pendingRequest = _pendingBlockRequests.remove(blockHash);
      if (pendingRequest != null && !pendingRequest.isCompleted) {
        pendingRequest.complete(payload);
        _neutrinoLog('Neutrino: Completed pending block request for $blockHash');
      }
    } catch (e) {
      _neutrinoLog('Neutrino: Error in _handleBlock - $e');
    }
  }

  void _handleTx(Uint8List payload) {
    try {
      if (payload.length < 10) {
        _neutrinoLog('Neutrino: Tx too small');
        return;
      }
      
      final txHash = _computeTxHash(payload);
      _neutrinoLog('Neutrino: Received tx $txHash (${payload.length} bytes)');
      
      final pendingRequest = _pendingTxRequests.remove(txHash);
      if (pendingRequest != null && !pendingRequest.isCompleted) {
        pendingRequest.complete(payload);
        _neutrinoLog('Neutrino: Completed pending tx request for $txHash');
      }
      
      if (_mempoolScanActive && _mempoolWatchScripts != null) {
        if (_txMatchesScripts(payload, _mempoolWatchScripts!)) {
          _neutrinoLog('Neutrino: Mempool tx $txHash matches watched scripts');
          onMempoolTx?.call(payload);
        }
      }
    } catch (e) {
      _neutrinoLog('Neutrino: Error in _handleTx - $e');
    }
  }

  void _handleInv(Peer peer, Uint8List payload) {
    var offset = 0;
    final countResult = BinaryUtils.readVarInt(payload, offset);
    offset += countResult.bytesRead;
    final count = countResult.value;
    
    _neutrinoLog('Neutrino: INV received with $count items');
    
    bool blockAnnouncement = false;
    final txHashes = <Uint8List>[];
    
    for (var i = 0; i < count; i++) {
      if (offset + 36 > payload.length) break;
      final invType = BinaryUtils.readUint32LE(payload, offset);
      offset += 4;
      final hash = payload.sublist(offset, offset + 32);
      offset += 32;
      
      final hashHexInternal = BinaryUtils.bytesToHex(hash);
      final hashHexDisplay = BinaryUtils.bytesToHex(Uint8List.fromList(hash.reversed.toList()));
      
      if (invType == 2) {
        blockAnnouncement = true;
        _neutrinoLog('Neutrino: INV item $i: BLOCK $hashHexDisplay');
      } else if (invType == 1) {
        _neutrinoLog('Neutrino: INV item $i: TX $hashHexDisplay (internal: $hashHexInternal)');
        
        if (_mempoolVerifyCompleter != null) {
          _lastMempoolTxids.add(hashHexInternal);
          _lastMempoolTxids.add(hashHexDisplay);
          if (hashHexInternal == _mempoolVerifyTxid || hashHexDisplay == _mempoolVerifyTxid) {
            _neutrinoLog('Neutrino: FOUND our tx in mempool inv!');
            if (!_mempoolVerifyCompleter!.isCompleted) {
              _mempoolVerifyCompleter!.complete(true);
            }
          }
        }
        
        if (_mempoolScanActive) {
          if (!_mempoolTxHashes.contains(hashHexDisplay)) {
            _mempoolTxHashes.add(hashHexDisplay);
            txHashes.add(Uint8List.fromList(hash));
          }
        }
      }
    }
    
    if (blockAnnouncement) {
      _headerSync.handleInv(peer, payload);
    }
    
    if (txHashes.isNotEmpty && _mempoolScanActive) {
      _requestTxBatch(peer, txHashes);
    }
  }

  void _requestTxBatch(Peer peer, List<Uint8List> txHashes) {
    if (txHashes.isEmpty) return;
    
    final payload = <int>[];
    BinaryUtils.writeVarInt(payload, txHashes.length);
    for (final hash in txHashes) {
      BinaryUtils.writeUint32LE(payload, 1);
      payload.addAll(hash);
    }
    
    final message = P2PMessage(command: 'getdata', payload: Uint8List.fromList(payload));
    peer.connection.sendMessage(message);
    _neutrinoLog('Neutrino: Requested ${txHashes.length} mempool transactions');
  }

  String _computeTxHash(Uint8List rawTx) {
    Uint8List txForHash;
    if (rawTx.length > 5 && rawTx[4] == 0x00 && rawTx[5] == 0x01) {
      txForHash = _stripWitnessData(rawTx);
    } else {
      txForHash = rawTx;
    }
    final hash1 = sha256.convert(txForHash);
    final hash2 = sha256.convert(hash1.bytes);
    return BinaryUtils.bytesToHex(Uint8List.fromList(hash2.bytes.reversed.toList()));
  }

  bool _txMatchesScripts(Uint8List rawTx, List<Uint8List> scripts) {
    try {
      var offset = 4;
      
      if (offset + 2 <= rawTx.length && rawTx[offset] == 0x00 && rawTx[offset + 1] == 0x01) {
        offset += 2;
      }
      
      final inputCountResult = BinaryUtils.readVarInt(rawTx, offset);
      offset += inputCountResult.bytesRead;
      final inputCount = inputCountResult.value;
      
      for (var i = 0; i < inputCount; i++) {
        offset += 36;
        final scriptLenResult = BinaryUtils.readVarInt(rawTx, offset);
        offset += scriptLenResult.bytesRead;
        offset += scriptLenResult.value;
        offset += 4;
      }
      
      final outputCountResult = BinaryUtils.readVarInt(rawTx, offset);
      offset += outputCountResult.bytesRead;
      final outputCount = outputCountResult.value;
      
      for (var i = 0; i < outputCount; i++) {
        offset += 8;
        final scriptLenResult = BinaryUtils.readVarInt(rawTx, offset);
        offset += scriptLenResult.bytesRead;
        final scriptLen = scriptLenResult.value;
        
        if (offset + scriptLen <= rawTx.length) {
          final scriptPubKey = rawTx.sublist(offset, offset + scriptLen);
          for (final watchScript in scripts) {
            if (_bytesEqual(scriptPubKey, watchScript)) {
              return true;
            }
          }
        }
        offset += scriptLen;
      }
      
      return false;
    } catch (e) {
      _neutrinoLog('Neutrino: Error parsing tx for script matching - $e');
      return false;
    }
  }

  bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _handleCompactBlock(Peer peer, Uint8List payload) {
    try {
      if (payload.length < chainParams.headerLengthBytes) {
        _neutrinoLog('Neutrino: Compact block too small');
        return;
      }
      
      final headerData = payload.sublist(0, chainParams.headerLengthBytes);
      final header = BlockHeader.parse(headerData, chainParams.headerLengthBytes);
      
      final oldHeight = _chainState.height;
      if (_chainState.addHeader(header, headerData)) {
        final newHeight = _chainState.height;
        final blockIndex = newHeight - 1;
        _neutrinoLog('Neutrino: Compact block added header at index $blockIndex, chain height now $newHeight');
        _headerSync.setTargetHeight(newHeight);
        _chainState.forceFlush();
        
        if (newHeight > oldHeight) {
          onNewBlock?.call(blockIndex);
        }
      }
    } catch (e) {
      _neutrinoLog('Neutrino: Error in _handleCompactBlock - $e');
    }
  }

  Future<void> waitForPeerReady({Duration timeout = const Duration(seconds: 10)}) async {
    if (hasPeerReady) {
      _neutrinoLog('Neutrino: Peer already ready');
      return;
    }
    
    _neutrinoLog('Neutrino: Waiting for peer to become ready (timeout=${timeout.inSeconds}s)');
    final start = DateTime.now();
    while (!hasPeerReady) {
      if (DateTime.now().difference(start) > timeout) {
        _neutrinoLog('Neutrino: Timeout waiting for peer handshake');
        throw Exception('Timeout waiting for peer handshake');
      }
      await Future.delayed(const Duration(milliseconds: 100));
    }
    _neutrinoLog('Neutrino: Peer became ready after ${DateTime.now().difference(start).inMilliseconds}ms');
  }

  Future<void> syncToTip() async {
    _neutrinoLog('Neutrino: syncToTip called, connected=$_isConnected, phase=$_syncPhase, isSyncing=$_isSyncing');
    
    if (_isSyncing) {
      _neutrinoLog('Neutrino: Already syncing, skipping');
      return;
    }
    
    if (!_isConnected) {
      _neutrinoLog('Neutrino: Not connected, connecting first');
      await connect();
    }
    
    await waitForPeerReady();
    _neutrinoLog('Neutrino: Peer ready, local height=${_chainState.height}, target=${_headerSync.syncTargetHeight}, isAtTip=${_headerSync.isAtTip}');
    
    if (_headerSync.isAtTip) {
      _neutrinoLog('Neutrino: Already synced to tip ${_chainState.height}');
      _syncPhase = SyncPhase.complete;
      _isSyncing = false;
      _emitStateChanged();
      return;
    }
    
    _isSyncing = true;
    _syncError = null;
    _emitStateChanged();
    
    try {
      _syncPhase = SyncPhase.headers;
      _neutrinoLog('Neutrino: Starting header sync phase');
      _emitStateChanged();
      
      await _headerSync.syncToTip();
      _neutrinoLog('Neutrino: Header sync completed, height=${_chainState.height}');
      
      _syncPhase = SyncPhase.complete;
      _neutrinoLog('Neutrino: Sync complete - ${_chainState.height} blocks');
      _isSyncing = false;
      _emitStateChanged();
    } catch (e, stack) {
      _neutrinoLog('Neutrino: Sync failed - $e');
      _neutrinoLog('Neutrino: Stack trace: $stack');
      _syncError = e.toString();
      _isSyncing = false;
      _emitStateChanged();
      rethrow;
    }
  }

  Future<Uint8List?> requestBlock(int height, {Duration timeout = const Duration(seconds: 10)}) async {
    if (height >= _chainState.height) {
      throw Exception('Height $height beyond chain tip');
    }
    
    var blockHashBytes = _chainState.getBlockHash(height);
    if (blockHashBytes == null) {
      blockHashBytes = await _chainState.getBlockHashAsync(height);
    }
    if (blockHashBytes == null) {
      throw Exception('No block hash for height $height');
    }
    
    var header = _chainState.getHeader(height);
    if (header == null) {
      header = await _chainState.getHeaderAsync(height);
    }
    final blockHashHex = header?.getHashHex() ?? _chainState.getBlockHashHex(height);
    if (blockHashHex == null) {
      throw Exception('Cannot get block hash hex for height $height');
    }
    
    if (_blocks.containsKey(blockHashHex)) {
      return _blocks[blockHashHex];
    }
    
    if (_pendingBlockRequests.containsKey(blockHashHex)) {
      return _pendingBlockRequests[blockHashHex]!.future;
    }
    
    final completer = Completer<Uint8List?>();
    _pendingBlockRequests[blockHashHex] = completer;
    
    final peer = _peerManager.selectPeerForData();
    if (peer == null) {
      _pendingBlockRequests.remove(blockHashHex);
      throw Exception('No peers available for block request');
    }
    
    final payload = <int>[];
    payload.add(1);
    BinaryUtils.writeUint32LE(payload, 2);
    payload.addAll(blockHashBytes);
    
    final message = P2PMessage(command: 'getdata', payload: Uint8List.fromList(payload));
    await peer.connection.sendMessage(message);
    _neutrinoLog('Neutrino: Requested block at height $height (hash=$blockHashHex)');
    
    try {
      final result = await completer.future.timeout(timeout);
      return result;
    } on TimeoutException {
      _pendingBlockRequests.remove(blockHashHex);
      _neutrinoLog('Neutrino: Block request timed out for height $height');
      return null;
    }
  }

  Future<void> requestFilter(int height) async {
    await _filterSync.requestFilter(height);
  }

  Future<void> prefetchFilters(int startHeight, int endHeight) async {
    await _filterSync.prefetchFilters(startHeight, endHeight);
  }

  Future<bool> filterMatchesScripts(int height, List<Uint8List> scripts) async {
    return await _filterSync.filterMatchesScripts(height, scripts);
  }

  Uint8List? getBlock(String blockHash) => _blocks[blockHash];

  Future<void> scanMempool(List<Uint8List> scripts) async {
    if (scripts.isEmpty) return;
    
    _mempoolWatchScripts = scripts;
    _mempoolScanActive = true;
    _mempoolTxHashes.clear();
    
    _neutrinoLog('Neutrino: Starting mempool scan for ${scripts.length} scripts');
    
    final peers = _peerManager.activePeers;
    if (peers.isEmpty) {
      _neutrinoLog('Neutrino: No peers for mempool scan');
      _mempoolScanActive = false;
      return;
    }
    
    for (final peer in peers) {
      final message = P2PMessage(command: 'mempool', payload: Uint8List(0));
      await peer.connection.sendMessage(message);
    }
    
    await Future.delayed(const Duration(seconds: 3));
    
    _neutrinoLog('Neutrino: Mempool scan complete, found ${_mempoolTxHashes.length} tx hashes');
    _mempoolScanActive = false;
    _mempoolWatchScripts = null;
  }

  void stopMempoolScan() {
    _mempoolScanActive = false;
    _mempoolWatchScripts = null;
    _mempoolTxHashes.clear();
  }

  void _handleGetData(Peer peer, Uint8List payload) {
    try {
      var offset = 0;
      final countResult = BinaryUtils.readVarInt(payload, offset);
      offset += countResult.bytesRead;
      final count = countResult.value;
      
      _neutrinoLog('Neutrino: getdata request for $count items from ${peer.id}');
      _neutrinoLog('Neutrino: Current broadcast cache has ${_broadcastTxs.length} txs: ${_broadcastTxs.keys.toList()}');
      
      for (var i = 0; i < count; i++) {
        if (offset + 36 > payload.length) break;
        final invType = BinaryUtils.readUint32LE(payload, offset);
        offset += 4;
        final hash = payload.sublist(offset, offset + 32);
        offset += 32;
        
        final hashHex = BinaryUtils.bytesToHex(hash);
        final hashDisplayHex = BinaryUtils.bytesToHex(Uint8List.fromList(hash.reversed.toList()));
        
        _neutrinoLog('Neutrino: getdata item $i: type=$invType, hashInternal=$hashHex, hashDisplay=$hashDisplayHex');
        
        if (invType == 1 || invType == 0x40000001) {
          final tx = _broadcastTxs[hashHex];
          if (tx != null) {
            _neutrinoLog('Neutrino: FOUND tx in cache, sending ${tx.length} bytes');
            _neutrinoLog('Neutrino: TX hex being sent: ${BinaryUtils.bytesToHex(tx)}');
            final txMessage = P2PMessage(command: 'tx', payload: tx);
            peer.connection.sendMessage(txMessage);
            _neutrinoLog('Neutrino: TX message sent to ${peer.id}');
          } else {
            _neutrinoLog('Neutrino: getdata requested unknown tx $hashHex (display: $hashDisplayHex)');
            _neutrinoLog('Neutrino: Available txs in cache: ${_broadcastTxs.keys.join(", ")}');
          }
        } else {
          _neutrinoLog('Neutrino: getdata for type $invType (0x${invType.toRadixString(16)}) not handled');
        }
      }
    } catch (e, stack) {
      _neutrinoLog('Neutrino: Error handling getdata - $e');
      _neutrinoLog('Neutrino: Stack: $stack');
    }
  }

  final Set<String> _lastMempoolTxids = {};
  Completer<bool>? _mempoolVerifyCompleter;
  String? _mempoolVerifyTxid;

  Future<void> broadcastTransaction(Uint8List rawTx) async {
    final nonWitnessTx = _stripWitnessData(rawTx);
    final txHashBytes = Uint8List.fromList(sha256.convert(sha256.convert(nonWitnessTx).bytes).bytes);
    final txHashHex = BinaryUtils.bytesToHex(txHashBytes);
    final txHashDisplayHex = BinaryUtils.bytesToHex(Uint8List.fromList(txHashBytes.reversed.toList()));
    
    _broadcastTxs[txHashHex] = rawTx;
    _neutrinoLog('Neutrino: === BROADCAST TRANSACTION START ===');
    _neutrinoLog('Neutrino: Caching tx with internal hash key: $txHashHex');
    _neutrinoLog('Neutrino: Display txid (reversed): $txHashDisplayHex');
    _neutrinoLog('Neutrino: Raw tx size: ${rawTx.length} bytes, stripped (for txid): ${nonWitnessTx.length} bytes');
    _neutrinoLog('Neutrino: Raw tx hex: ${BinaryUtils.bytesToHex(rawTx)}');
    _neutrinoLog('Neutrino: Stripped tx hex: ${BinaryUtils.bytesToHex(nonWitnessTx)}');
    
    _decodeTxForLogging(rawTx);
    
    final peers = _peerManager.activePeers;
    if (peers.isEmpty) {
      _neutrinoLog('Neutrino: ERROR - No peers connected for broadcast!');
      throw Exception('No peers connected for broadcast');
    }
    
    _neutrinoLog('Neutrino: Broadcasting INV to ${peers.length} peer(s)');
    
    final invPayload = <int>[];
    invPayload.add(1);
    BinaryUtils.writeUint32LE(invPayload, 1);
    invPayload.addAll(txHashBytes);
    
    _neutrinoLog('Neutrino: INV payload: count=1, type=1 (MSG_TX), hash=$txHashHex');
    _neutrinoLog('Neutrino: INV payload hex: ${BinaryUtils.bytesToHex(Uint8List.fromList(invPayload))}');
    
    for (final peer in peers) {
      _neutrinoLog('Neutrino: Sending INV to peer ${peer.id}');
      final invMessage = P2PMessage(command: 'inv', payload: Uint8List.fromList(invPayload));
      await peer.connection.sendMessage(invMessage);
      _neutrinoLog('Neutrino: INV sent to ${peer.id}');
    }
    
    _neutrinoLog('Neutrino: Broadcast INV complete, waiting 3s for getdata requests...');
    
    await Future.delayed(const Duration(seconds: 3));
    
    _neutrinoLog('Neutrino: 3s wait complete. Checking if we got getdata...');
    _neutrinoLog('Neutrino: TX still in broadcast cache: ${_broadcastTxs.containsKey(txHashHex)}');
    
    _neutrinoLog('Neutrino: Verifying tx in peer mempool...');
    final inMempool = await _verifyTxInMempool(txHashHex, txHashDisplayHex);
    _neutrinoLog('Neutrino: TX in peer mempool: $inMempool');
    
    _neutrinoLog('Neutrino: === BROADCAST TRANSACTION END ===');
    
    Future.delayed(const Duration(minutes: 5), () {
      if (_broadcastTxs.remove(txHashHex) != null) {
        _neutrinoLog('Neutrino: Removed tx $txHashHex from broadcast cache after 5 min timeout');
      }
    });
  }
  
  void _decodeTxForLogging(Uint8List rawTx) {
    try {
      var offset = 0;
      final version = BinaryUtils.readUint32LE(rawTx, offset);
      offset += 4;
      _neutrinoLog('Neutrino: TX decode - version: $version');
      
      bool hasWitness = false;
      if (rawTx[offset] == 0x00 && rawTx[offset + 1] == 0x01) {
        hasWitness = true;
        offset += 2;
        _neutrinoLog('Neutrino: TX decode - has witness data');
      }
      
      final inputCount = BinaryUtils.readVarInt(rawTx, offset);
      offset += inputCount.bytesRead;
      _neutrinoLog('Neutrino: TX decode - input count: ${inputCount.value}');
      
      for (var i = 0; i < inputCount.value; i++) {
        final prevTxid = BinaryUtils.bytesToHex(Uint8List.fromList(rawTx.sublist(offset, offset + 32).reversed.toList()));
        offset += 32;
        final prevVout = BinaryUtils.readUint32LE(rawTx, offset);
        offset += 4;
        _neutrinoLog('Neutrino: TX decode - input[$i]: $prevTxid:$prevVout');
        
        final scriptSigLen = BinaryUtils.readVarInt(rawTx, offset);
        offset += scriptSigLen.bytesRead;
        offset += scriptSigLen.value;
        
        final sequence = BinaryUtils.readUint32LE(rawTx, offset);
        offset += 4;
        _neutrinoLog('Neutrino: TX decode - input[$i] sequence: 0x${sequence.toRadixString(16)} (RBF: ${sequence < 0xfffffffe})');
      }
      
      final outputCount = BinaryUtils.readVarInt(rawTx, offset);
      offset += outputCount.bytesRead;
      _neutrinoLog('Neutrino: TX decode - output count: ${outputCount.value}');
      
      int totalOut = 0;
      for (var i = 0; i < outputCount.value; i++) {
        final value = BinaryUtils.readUint64LE(rawTx, offset);
        offset += 8;
        totalOut += value;
        
        final scriptLen = BinaryUtils.readVarInt(rawTx, offset);
        offset += scriptLen.bytesRead;
        final script = rawTx.sublist(offset, offset + scriptLen.value);
        offset += scriptLen.value;
        
        _neutrinoLog('Neutrino: TX decode - output[$i]: $value sats, script=${BinaryUtils.bytesToHex(script)}');
      }
      
      _neutrinoLog('Neutrino: TX decode - total output: $totalOut sats');
      
    } catch (e) {
      _neutrinoLog('Neutrino: TX decode error: $e');
    }
  }
  
  Future<bool> _verifyTxInMempool(String txHashInternal, String txHashDisplay) async {
    final peers = _peerManager.activePeers;
    if (peers.isEmpty) return false;
    
    _lastMempoolTxids.clear();
    _mempoolVerifyTxid = txHashInternal;
    _mempoolVerifyCompleter = Completer<bool>();
    
    final peer = peers.first;
    _neutrinoLog('Neutrino: Sending mempool request to ${peer.id}');
    final mempoolMsg = P2PMessage(command: 'mempool', payload: Uint8List(0));
    await peer.connection.sendMessage(mempoolMsg);
    
    try {
      final result = await _mempoolVerifyCompleter!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _neutrinoLog('Neutrino: Mempool verification timeout - checking collected txids');
          final found = _lastMempoolTxids.contains(txHashInternal) || 
                        _lastMempoolTxids.contains(txHashDisplay);
          _neutrinoLog('Neutrino: Found ${_lastMempoolTxids.length} txids in mempool, our tx present: $found');
          if (_lastMempoolTxids.isNotEmpty) {
            _neutrinoLog('Neutrino: Sample mempool txids: ${_lastMempoolTxids.take(5).join(", ")}');
          }
          return found;
        },
      );
      return result;
    } finally {
      _mempoolVerifyCompleter = null;
      _mempoolVerifyTxid = null;
    }
  }

  Uint8List _stripWitnessData(Uint8List rawTx) {
    if (rawTx.length < 6) return rawTx;
    
    final hasWitness = rawTx[4] == 0x00 && rawTx[5] == 0x01;
    if (!hasWitness) return rawTx;
    
    final result = <int>[];
    
    result.addAll(rawTx.sublist(0, 4));
    
    var offset = 6;
    
    final inputCountResult = BinaryUtils.readVarInt(rawTx, offset);
    offset += inputCountResult.bytesRead;
    final inputCount = inputCountResult.value;
    
    BinaryUtils.writeVarInt(result, inputCount);
    
    for (var i = 0; i < inputCount; i++) {
      result.addAll(rawTx.sublist(offset, offset + 36));
      offset += 36;
      
      final scriptLenResult = BinaryUtils.readVarInt(rawTx, offset);
      offset += scriptLenResult.bytesRead;
      final scriptLen = scriptLenResult.value;
      
      BinaryUtils.writeVarInt(result, scriptLen);
      result.addAll(rawTx.sublist(offset, offset + scriptLen));
      offset += scriptLen;
      
      result.addAll(rawTx.sublist(offset, offset + 4));
      offset += 4;
    }
    
    final outputCountResult = BinaryUtils.readVarInt(rawTx, offset);
    offset += outputCountResult.bytesRead;
    final outputCount = outputCountResult.value;
    
    BinaryUtils.writeVarInt(result, outputCount);
    
    for (var i = 0; i < outputCount; i++) {
      result.addAll(rawTx.sublist(offset, offset + 8));
      offset += 8;
      
      final scriptLenResult = BinaryUtils.readVarInt(rawTx, offset);
      offset += scriptLenResult.bytesRead;
      final scriptLen = scriptLenResult.value;
      
      BinaryUtils.writeVarInt(result, scriptLen);
      result.addAll(rawTx.sublist(offset, offset + scriptLen));
      offset += scriptLen;
    }
    
    for (var i = 0; i < inputCount; i++) {
      final witnessCountResult = BinaryUtils.readVarInt(rawTx, offset);
      offset += witnessCountResult.bytesRead;
      final witnessCount = witnessCountResult.value;
      
      for (var j = 0; j < witnessCount; j++) {
        final itemLenResult = BinaryUtils.readVarInt(rawTx, offset);
        offset += itemLenResult.bytesRead;
        offset += itemLenResult.value;
      }
    }
    
    result.addAll(rawTx.sublist(offset, offset + 4));
    
    return Uint8List.fromList(result);
  }

  void disconnect() {
    _peerManager.disconnect();
    _chainState.forceFlush();
  }

  Future<void> resetWallet() async {
    disconnect();
    await _chainState.reset();
    _filterSync.clearState();
    _blocks.clear();
    _broadcastTxs.clear();
    _syncError = null;
    _syncPhase = SyncPhase.idle;
    _neutrinoLog('Neutrino: Wallet reset complete');
  }

  int? _extractStartHeight(Uint8List payload) {
    try {
      var offset = 0;
      if (payload.length < 80) return null;
      offset += 4;
      offset += 8;
      offset += 8;
      offset += 26;
      offset += 26;
      offset += 8;
      final userAgentResult = BinaryUtils.readVarInt(payload, offset);
      offset += userAgentResult.bytesRead;
      final uaLength = userAgentResult.value;
      offset += uaLength;
      if (offset + 4 > payload.length) return null;
      final height = ByteData.sublistView(payload, offset, offset + 4).getInt32(0, Endian.little);
      return height;
    } catch (_) {
      return null;
    }
  }

  void _emitStateChanged() {
    onStateChanged?.call();
  }
}
