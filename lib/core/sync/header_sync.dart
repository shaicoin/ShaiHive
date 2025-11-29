import 'dart:async';
import 'dart:typed_data';
import '../chain/block_header.dart';
import '../chain/chain_params.dart';
import '../chain/chain_state.dart';
import '../p2p/peer.dart';
import '../p2p/peer_manager.dart';
import '../p2p/p2p_connection.dart';
import '../utils/binary_utils.dart';

typedef HeaderSyncListener = void Function();

class HeaderSync {
  final ChainParams chainParams;
  final ChainState chainState;
  final PeerManager peerManager;
  
  static const Duration _headerRequestThrottle = Duration(seconds: 30);
  
  int _syncTargetHeight = 0;
  bool _isSyncing = false;
  bool _requestPending = false;
  int _lastRequestedHeight = -1;
  DateTime? _lastHeaderRequestTime;
  Completer<void>? _syncCompleter;
  String? _syncError;
  
  HeaderSyncListener? onSyncProgress;
  void Function(int height)? onNewBlock;

  HeaderSync({
    required this.chainParams,
    required this.chainState,
    required this.peerManager,
  });

  int get syncTargetHeight => _syncTargetHeight;
  bool get isSyncing => _isSyncing;
  String? get syncError => _syncError;
  
  double get syncProgress {
    if (_syncTargetHeight == 0) return 0;
    final progress = chainState.height / _syncTargetHeight;
    return progress.clamp(0.0, 1.0);
  }

  void setTargetHeight(int height) {
    if (height > _syncTargetHeight) {
      print('HeaderSync: Target height updated $height (was $_syncTargetHeight), local=${chainState.height}');
      _syncTargetHeight = height;
    }
  }

  bool get isAtTip {
    final atTip = _syncTargetHeight > 0 && chainState.height >= _syncTargetHeight;
    return atTip;
  }
  
  void logSyncState() {
    print('HeaderSync: State - target=$_syncTargetHeight, height=${chainState.height}, isAtTip=$isAtTip, isSyncing=$_isSyncing, pending=$_requestPending');
  }

  Future<void> syncToTip({Duration timeout = const Duration(minutes: 5)}) async {
    if (isAtTip) {
      print('HeaderSync: Already at tip ${chainState.height}');
      return;
    }
    
    _isSyncing = true;
    _syncError = null;
    _syncCompleter = Completer<void>();
    
    await requestHeaders(force: true);
    
    try {
      await _syncCompleter!.future.timeout(timeout);
    } on TimeoutException {
      print('HeaderSync: Timeout, retrying');
      _lastHeaderRequestTime = null;
      await requestHeaders(force: true);
      await _syncCompleter!.future;
    }
    
    await chainState.forceFlush();
    _isSyncing = false;
  }

  Future<void> requestHeaders({Peer? preferredPeer, bool force = false}) async {
    if (!force && !_isSyncing && _syncCompleter == null && chainState.height >= _syncTargetHeight && _syncTargetHeight > 0) {
      return;
    }
    
    if (_requestPending && _lastRequestedHeight == chainState.height) {
      return;
    }
    
    final now = DateTime.now();
    if (!force && _lastHeaderRequestTime != null) {
      final elapsed = now.difference(_lastHeaderRequestTime!);
      if (elapsed < _headerRequestThrottle && _lastRequestedHeight == chainState.height) {
        print('HeaderSync: Throttled (${elapsed.inSeconds}s since last request)');
        return;
      }
    }
    
    final peer = peerManager.selectPeerForHeaders(preferred: preferredPeer);
    if (peer == null) {
      print('HeaderSync: No peer available');
      return;
    }
    
    _requestPending = true;
    _lastRequestedHeight = chainState.height;
    _lastHeaderRequestTime = now;
    
    print('HeaderSync: Requesting from height ${chainState.height}');
    
    final payload = <int>[];
    BinaryUtils.writeUint32LE(payload, 70015);
    
    final locator = await chainState.buildBlockLocator();
    BinaryUtils.writeVarInt(payload, locator.length);
    for (final entry in locator) {
      payload.addAll(entry.hash);
    }
    for (var i = 0; i < 32; i++) payload.add(0);
    
    final message = P2PMessage(command: 'getheaders', payload: Uint8List.fromList(payload));
    peer.connection.sendMessage(message);
  }

  Future<void> handleHeaders(Peer peer, Uint8List payload) async {
    _requestPending = false;
    
    if (payload.isEmpty) {
      print('HeaderSync: No more headers');
      _completeSyncIfNeeded();
      return;
    }
    
    var offset = 0;
    final countResult = BinaryUtils.readVarInt(payload, offset);
    offset += countResult.bytesRead;
    final numHeaders = countResult.value;
    
    final heightBefore = chainState.height;
    int headersAdded = 0;
    
    for (var i = 0; i < numHeaders; i++) {
      if (offset + chainParams.headerLengthBytes > payload.length) break;
      
      final headerData = payload.sublist(offset, offset + chainParams.headerLengthBytes);
      offset += chainParams.headerLengthBytes;
      
      final txCountResult = BinaryUtils.readVarInt(payload, offset);
      offset += txCountResult.bytesRead;
      
      try {
        final header = BlockHeader.parse(headerData, chainParams.headerLengthBytes);
        if (chainState.addHeader(header, headerData)) {
          headersAdded++;
        }
      } catch (e) {
        print('HeaderSync: Parse error - $e');
      }
    }
    
    if (headersAdded > 0) {
      if (_syncTargetHeight < chainState.height) {
        _syncTargetHeight = chainState.height;
      }
      onSyncProgress?.call();
    }
    
    print('HeaderSync: Added $headersAdded headers, height now ${chainState.height}');
    
    await chainState.flushToStorage();
    
    if (headersAdded > 0 && chainState.height < _syncTargetHeight) {
      _lastHeaderRequestTime = null;
      unawaited(requestHeaders(preferredPeer: peer, force: true));
    } else if (headersAdded == 0 && chainState.height == heightBefore) {
      if (chainState.height >= _syncTargetHeight && _syncTargetHeight > 0) {
        print('HeaderSync: Already at tip ${chainState.height}');
        await chainState.forceFlush();
        _completeSyncIfNeeded();
      } else if (_syncTargetHeight == 0) {
        print('HeaderSync: Waiting for peer height info');
      } else {
        print('HeaderSync: No progress at ${chainState.height}, target $_syncTargetHeight');
        _syncError = 'Chain sync stalled';
        await chainState.forceFlush();
        _completeSyncIfNeeded();
      }
    } else {
      print('HeaderSync: Complete at height ${chainState.height}');
      await chainState.forceFlush();
      if (chainState.height > _syncTargetHeight) {
        _syncTargetHeight = chainState.height;
      }
      _completeSyncIfNeeded();
    }
  }

  void handleInv(Peer peer, Uint8List payload) {
    var offset = 0;
    final countResult = BinaryUtils.readVarInt(payload, offset);
    offset += countResult.bytesRead;
    final count = countResult.value;
    
    bool blockAnnouncement = false;
    for (var i = 0; i < count; i++) {
      if (offset + 36 > payload.length) break;
      final invType = BinaryUtils.readUint32LE(payload, offset);
      offset += 4;
      offset += 32;
      if (invType == 2) {
        blockAnnouncement = true;
      }
    }
    
    if (blockAnnouncement) {
      final oldHeight = chainState.height;
      Future.delayed(const Duration(milliseconds: 200), () async {
        await requestHeaders(preferredPeer: peer, force: true);
        await Future.delayed(const Duration(seconds: 2));
        final newHeight = chainState.height;
        if (newHeight > oldHeight && onNewBlock != null) {
          final blockDiff = newHeight - oldHeight;
          if (blockDiff <= 10) {
            for (var i = oldHeight; i < newHeight; i++) {
              onNewBlock!(i);
            }
          }
        }
      });
    }
  }

  void _completeSyncIfNeeded() {
    final completer = _syncCompleter;
    if (completer != null && !completer.isCompleted) {
      print('HeaderSync: Completing sync, height=${chainState.height}, target=$_syncTargetHeight');
      completer.complete();
    }
  }
}

