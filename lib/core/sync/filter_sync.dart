import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';
import '../chain/chain_state.dart';
import '../neutrino/compact_filter.dart';
import '../p2p/peer.dart';
import '../p2p/peer_manager.dart';
import '../p2p/p2p_connection.dart';
import '../utils/binary_utils.dart';

class FilterSync {
  final ChainState chainState;
  final PeerManager peerManager;
  
  static const int _maxFilterBatch = 2000;
  static const int _checkpointSpacing = 1000;
  
  final Map<int, FilterHeader> _filterHeaders = {};
  final Map<int, Uint8List> _filterHeaderCheckpoints = {};
  final Map<int, CompactFilter> _filters = {};
  final LinkedHashMap<int, Uint8List> _pendingFilterRequests = LinkedHashMap<int, Uint8List>();
  final Map<String, int> _pendingFilterHeightsByHash = {};
  
  int _lastCheckpointRequestHeight = -1;
  bool _checkpointRequestPending = false;
  bool _isSyncing = false;
  int _lastSyncedHeight = 0;
  Completer<void>? _syncCompleter;
  String? _syncError;

  FilterSync({
    required this.chainState,
    required this.peerManager,
  });

  int get filterHeaderCount => _filterHeaders.length;
  String? get syncError => _syncError;
  bool get isAtTip => _filterHeaders.length >= chainState.height && chainState.height > 0;
  bool get isSyncing => _isSyncing;

  Future<void> syncFilterHeaders({Duration timeout = const Duration(minutes: 2)}) async {
    if (_isSyncing) {
      print('FilterSync: Already syncing filter headers, skipping');
      return;
    }
    
    if (_filterHeaders.length >= chainState.height && chainState.height > 0) {
      print('FilterSync: Filter headers already at tip (${_filterHeaders.length} >= ${chainState.height}), skipping sync');
      return;
    }
    
    if (_lastSyncedHeight > 0 && _filterHeaders.length >= _lastSyncedHeight && 
        chainState.height <= _lastSyncedHeight + 10) {
      print('FilterSync: Recently synced to $_lastSyncedHeight, only ${chainState.height - _lastSyncedHeight} new blocks, skipping full sync');
      return;
    }
    
    _isSyncing = true;
    print('FilterSync: Starting syncFilterHeaders, have ${_filterHeaderCheckpoints.length} checkpoints, ${_filterHeaders.length} headers, chain=${chainState.height}');
    _syncCompleter = Completer<void>();
    
    if (_filterHeaderCheckpoints.isEmpty) {
      print('FilterSync: No checkpoints yet, requesting');
      await requestFilterCheckpoints();
    } else {
      print('FilterSync: Already have checkpoints, skipping checkpoint request');
    }
    await requestFilterHeaders();
    
    try {
      await _syncCompleter!.future.timeout(timeout);
      _lastSyncedHeight = _filterHeaders.length;
    } on TimeoutException {
      print('FilterSync: Timeout waiting for filter headers, retrying');
      await requestFilterHeaders();
      await _syncCompleter!.future;
      _lastSyncedHeight = _filterHeaders.length;
    } finally {
      _isSyncing = false;
    }
    print('FilterSync: syncFilterHeaders completed');
  }

  Future<void> requestFilterCheckpoints({Peer? preferredPeer}) async {
    if (chainState.height == 0) {
      print('FilterSync: Cannot request checkpoints - chain height is 0');
      return;
    }
    
    if (_checkpointRequestPending) {
      print('FilterSync: Checkpoint request already pending, skipping');
      return;
    }
    
    final stopHeight = chainState.height - 1;
    if (stopHeight <= _lastCheckpointRequestHeight && _filterHeaderCheckpoints.isNotEmpty) {
      print('FilterSync: Skipping checkpoint request - already have ${_filterHeaderCheckpoints.length} checkpoints up to height $_lastCheckpointRequestHeight');
      return;
    }
    
    final peer = peerManager.selectPeerForFilters(preferred: preferredPeer);
    if (peer == null) {
      print('FilterSync: No filter peer available for checkpoints');
      return;
    }
    
    print('FilterSync: Requesting checkpoints from peer ${peer.id}, stopHeight=$stopHeight, lastRequested=$_lastCheckpointRequestHeight');
    
    final payload = <int>[];
    payload.add(0);
    var stopHash = chainState.getBlockHash(stopHeight);
    if (stopHash == null) {
      stopHash = await chainState.getBlockHashAsync(stopHeight);
    }
    if (stopHash == null) {
      print('FilterSync: Cannot get hash for stopHeight $stopHeight');
      return;
    }
    payload.addAll(stopHash);
    
    final message = P2PMessage(command: 'getcfcheckpt', payload: Uint8List.fromList(payload));
    peer.connection.sendMessage(message);
    _lastCheckpointRequestHeight = stopHeight;
    _checkpointRequestPending = true;
    print('FilterSync: Sent getcfcheckpt for height $stopHeight');
  }

  Future<void> requestFilterHeaders({Peer? preferredPeer}) async {
    if (chainState.height == 0) {
      print('FilterSync: Cannot request filter headers - chain height is 0');
      return;
    }
    
    final peer = peerManager.selectPeerForFilters(preferred: preferredPeer);
    if (peer == null) {
      print('FilterSync: No filter peer available for headers');
      _syncError ??= 'No compact filter peers available';
      return;
    }
    
    final startHeight = _filterHeaders.length;
    if (startHeight >= chainState.height) {
      print('FilterSync: Filter headers up to date ($startHeight >= ${chainState.height})');
      _completeSyncIfNeeded();
      return;
    }
    
    final remaining = chainState.height - startHeight;
    final batchSize = remaining > _maxFilterBatch ? _maxFilterBatch : remaining;
    final stopHeight = startHeight + batchSize - 1;
    
    print('FilterSync: Requesting headers $startHeight-$stopHeight from ${peer.id} (have ${_filterHeaders.length}/${chainState.height})');
    
    final payload = <int>[];
    payload.add(0);
    BinaryUtils.writeUint32LE(payload, startHeight);
    var stopHash = chainState.getBlockHash(stopHeight);
    if (stopHash == null) {
      stopHash = await chainState.getBlockHashAsync(stopHeight);
    }
    if (stopHash == null) {
      print('FilterSync: Unable to determine block hash for stopHeight $stopHeight, deferring request');
      return;
    }
    payload.addAll(stopHash);
    
    final message = P2PMessage(command: 'getcfheaders', payload: Uint8List.fromList(payload));
    await peer.connection.sendMessage(message);
    print('FilterSync: Sent getcfheaders');
  }

  void handleFilterCheckpoint(Peer peer, Uint8List payload) {
    try {
      print('FilterSync: handleFilterCheckpoint from ${peer.id}, payload=${payload.length} bytes');
      
      if (payload.length < 33) {
        print('FilterSync: cfcheckpt payload too small (${payload.length} < 33)');
        return;
      }
      
      var offset = 0;
      final filterType = payload[offset];
      offset++;
      
      if (filterType != 0) {
        print('FilterSync: Unsupported filter type $filterType');
        return;
      }
      
      if (offset + 32 > payload.length) {
        print('FilterSync: cfcheckpt missing stop hash');
        return;
      }
      
      final stopHash = payload.sublist(offset, offset + 32);
      offset += 32;
      
      final countResult = BinaryUtils.readVarInt(payload, offset);
      offset += countResult.bytesRead;
      final numEntries = countResult.value;
      
      print('FilterSync: Parsing $numEntries checkpoint entries');
      
      final stopHeight = chainState.findHeightByHash(stopHash) ?? (chainState.height - 1);
      final checkpoints = <int, Uint8List>{};
      
      for (var i = 0; i < numEntries; i++) {
        if (offset + 32 > payload.length) {
          print('FilterSync: Truncated at checkpoint $i');
          break;
        }
        final headerHash = payload.sublist(offset, offset + 32);
        offset += 32;
        final height = _checkpointHeightForIndex(i, stopHeight);
        if (height >= 0) {
          checkpoints[height] = headerHash;
        }
      }
      
      _checkpointRequestPending = false;
      
      if (checkpoints.isNotEmpty) {
        final hadCheckpoints = _filterHeaderCheckpoints.isNotEmpty;
        _filterHeaderCheckpoints
          ..clear()
          ..addAll(checkpoints);
        print('FilterSync: Stored ${checkpoints.length} checkpoints (stopHeight=$stopHeight, hadPrevious=$hadCheckpoints)');
      } else {
        print('FilterSync: No valid checkpoints parsed');
      }
    } catch (e, stack) {
      print('FilterSync: Error in handleFilterCheckpoint - $e');
      print('FilterSync: Stack: $stack');
      _checkpointRequestPending = false;
      _syncError = e.toString();
    }
  }

  void handleFilterHeaders(Peer peer, Uint8List payload) {
    try {
      print('FilterSync: Processing filter headers');
      
      var offset = 0;
      offset++;
      offset += 32;
      
      final previousFilterHeader = payload.sublist(offset, offset + 32);
      offset += 32;
      
      final countResult = BinaryUtils.readVarInt(payload, offset);
      offset += countResult.bytesRead;
      final numHashes = countResult.value;
      
      print('FilterSync: Received $numHashes filter hashes');
      
      var height = _filterHeaders.length;
      final startHeight = height;
      
      Uint8List prevHash;
      if (startHeight == 0) {
        prevHash = Uint8List(32);
      } else {
        final lastHeader = _filterHeaders[startHeight - 1];
        if (lastHeader != null) {
          prevHash = lastHeader.hash;
        } else {
          prevHash = previousFilterHeader;
        }
      }
      
      for (var i = 0; i < numHashes; i++) {
        if (offset + 32 > payload.length) break;
        
        final filterHash = payload.sublist(offset, offset + 32);
        offset += 32;
        
        final filterHeader = FilterHeader(
          filterHash: filterHash,
          prevFilterHash: prevHash,
          height: height,
        );
        
        _filterHeaders[height] = filterHeader;
        prevHash = filterHeader.hash;
        height++;
      }
      
      final validated = _validateFilterHeadersAgainstCheckpoints(startHeight, height - 1);
      if (!validated) {
        print('FilterSync: Warning - checkpoint validation failed, continuing anyway');
      }
      
      print('FilterSync: Filter headers now cover ${_filterHeaders.length} blocks');
      
      if (_filterHeaders.length < chainState.height) {
        Future.delayed(const Duration(milliseconds: 200), () {
          unawaited(requestFilterHeaders(preferredPeer: peer));
        });
      } else {
        _completeSyncIfNeeded();
      }
    } catch (e) {
      print('FilterSync: Error in handleFilterHeaders - $e');
      _syncError = e.toString();
    }
  }

  void handleFilter(Uint8List payload) {
    try {
      var offset = 0;
      final filterType = payload[offset];
      offset++;
      
      final blockHash = payload.sublist(offset, offset + 32);
      offset += 32;
      
      final lengthData = BinaryUtils.readVarInt(payload, offset);
      offset += lengthData.bytesRead;
      final filterLength = lengthData.value;
      
      final blockHashHex = _formatBlockHash(blockHash);
      final blockHashRaw = BinaryUtils.bytesToHex(blockHash);
      print('FilterSync: Received cfilter - hash=$blockHashHex, rawHash=$blockHashRaw, len=$filterLength');
      print('FilterSync: Pending hashes: ${_pendingFilterHeightsByHash.keys.take(3).toList()}');
      
      final resolvedHeight = _resolvePendingFilterHeight(blockHash);
      if (resolvedHeight == null) {
        print('FilterSync: Warning - received filter $blockHashHex with no pending request');
        return;
      }

      print('FilterSync: Resolved filter to height $resolvedHeight');

      if (filterLength == 0) {
        _filters[resolvedHeight] = CompactFilter(filterBytes: Uint8List(0));
        print('FilterSync: Stored empty filter for height $resolvedHeight');
        return;
      }
      
      if (offset + filterLength > payload.length) {
        print('FilterSync: Declared filter length exceeds payload (${offset + filterLength} > ${payload.length}), type=$filterType');
        return;
      }
      
      final filterBytes = payload.sublist(offset, offset + filterLength);
      final filter = CompactFilter(filterBytes: filterBytes);
      _filters[resolvedHeight] = filter;
      print('FilterSync: Stored filter for height $resolvedHeight, now have ${_filters.length} cached');
    } catch (e, stack) {
      print('FilterSync: Error in handleFilter - $e');
      print('FilterSync: Stack: $stack');
    }
  }

  static const int _filterBatchSize = 100;

  Future<void> requestFilter(int height) async {
    if (height < 0 || height >= chainState.height) {
      throw Exception('Height $height beyond chain tip (tip=${chainState.height - 1})');
    }
    
    if (_filters.containsKey(height)) return;
    if (_pendingFilterRequests.containsKey(height)) return;
    
    await _requestFilterBatch(height, height);
  }

  Future<void> requestFilterBatch(int startHeight, int endHeight) async {
    if (startHeight < 0 || endHeight >= chainState.height) {
      throw Exception('Range $startHeight-$endHeight invalid (tip=${chainState.height - 1})');
    }
    await _requestFilterBatch(startHeight, endHeight);
  }

  Future<void> _requestFilterBatch(int startHeight, int endHeight) async {
    final peer = peerManager.selectPeerForData(requireFilters: true);
    if (peer == null) {
      throw Exception('No peers available for filter request');
    }

    for (var h = startHeight; h <= endHeight; h++) {
      if (_filters.containsKey(h) || _pendingFilterRequests.containsKey(h)) continue;
      
      var blockHash = chainState.getBlockHash(h);
      if (blockHash == null) {
        blockHash = await chainState.getBlockHashAsync(h);
      }
      if (blockHash == null) {
        print('FilterSync: Cannot request filter for $h - missing block hash');
        continue;
      }
      
      _pendingFilterRequests[h] = blockHash;
      _pendingFilterHeightsByHash[_hashKey(blockHash)] = h;
    }

    var stopHash = chainState.getBlockHash(endHeight);
    if (stopHash == null) {
      stopHash = await chainState.getBlockHashAsync(endHeight);
    }
    if (stopHash == null) {
      print('FilterSync: Cannot get stop hash for batch end $endHeight');
      return;
    }
    
    final payload = <int>[];
    payload.add(0);
    BinaryUtils.writeUint32LE(payload, startHeight);
    payload.addAll(stopHash);
    
    print('FilterSync: Requesting filters $startHeight-$endHeight (${endHeight - startHeight + 1} blocks)');
    
    final message = P2PMessage(command: 'getcfilters', payload: Uint8List.fromList(payload));
    await peer.connection.sendMessage(message);
  }

  Future<void> prefetchFilters(int startHeight, int endHeight) async {
    final batchEnd = endHeight.clamp(startHeight, chainState.height - 1);
    final actualBatchSize = (batchEnd - startHeight + 1).clamp(1, _filterBatchSize);
    final adjustedEnd = startHeight + actualBatchSize - 1;
    
    var needsRequest = false;
    for (var h = startHeight; h <= adjustedEnd; h++) {
      if (!_filters.containsKey(h) && !_pendingFilterRequests.containsKey(h)) {
        needsRequest = true;
        break;
      }
    }
    
    if (needsRequest) {
      try {
        await requestFilterBatch(startHeight, adjustedEnd);
      } catch (e) {
        print('FilterSync: Batch prefetch failed: $e');
      }
    }
  }

  Future<bool> filterMatchesScripts(int height, List<Uint8List> scripts) async {
    if (!_filters.containsKey(height)) {
      if (!_pendingFilterRequests.containsKey(height)) {
        try {
          if (_pendingFilterRequests.length >= _filterBatchSize * 2) {
            for (var i = 0; i < 30 && _pendingFilterRequests.length >= _filterBatchSize; i++) {
              await Future.delayed(const Duration(milliseconds: 100));
            }
          }
          await requestFilter(height);
        } catch (e) {
          print('FilterSync: Failed to request filter for $height - $e');
          return false;
        }
      }
      
      for (var i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_filters.containsKey(height)) break;
      }
    }
    
    final filter = _filters[height];
    if (filter == null) {
      print('FilterSync: No filter for $height after 5s wait, pending=${_pendingFilterRequests.length}, cached=${_filters.length}');
      return false;
    }
    
    if (!filter.hasData) {
      return false;
    }
    
    var header = chainState.getHeader(height);
    if (header == null) {
      header = await chainState.getHeaderAsync(height);
    }
    if (header == null) {
      print('FilterSync: No header for height $height even after async load');
      return false;
    }
    
    final key = header.getHash().sublist(0, 16);
    return filter.matches(scripts, key);
  }

  CompactFilter? getFilter(int height) => _filters[height];
  FilterHeader? getFilterHeader(int height) => _filterHeaders[height];

  void clearState() {
    _filterHeaders.clear();
    _filterHeaderCheckpoints.clear();
    _filters.clear();
    _pendingFilterRequests.clear();
    _pendingFilterHeightsByHash.clear();
    _lastCheckpointRequestHeight = -1;
    _checkpointRequestPending = false;
    _isSyncing = false;
    _lastSyncedHeight = 0;
    _syncCompleter = null;
    _syncError = null;
  }

  void truncateAbove(int height) {
    _filterHeaders.removeWhere((key, _) => key >= height);
    _filterHeaderCheckpoints.removeWhere((key, _) => key >= height);
    _filters.removeWhere((key, _) => key >= height);
    _pendingFilterRequests.removeWhere((key, _) => key >= height);
    _pendingFilterHeightsByHash.removeWhere((_, value) => value >= height);
    if (_lastCheckpointRequestHeight >= height) {
      _lastCheckpointRequestHeight = height > 0 ? height - 1 : -1;
    }
    if (_lastSyncedHeight >= height) {
      _lastSyncedHeight = height > 0 ? height - 1 : 0;
    }
  }

  bool _validateFilterHeadersAgainstCheckpoints(int startHeight, int endHeight) {
    if (_filterHeaderCheckpoints.isEmpty) return true;
    
    for (final entry in _filterHeaderCheckpoints.entries) {
      final cpHeight = entry.key;
      final cpHash = entry.value;
      if (cpHeight < startHeight || cpHeight > endHeight) continue;
      
      final filterHeader = _filterHeaders[cpHeight];
      if (filterHeader == null) continue;
      
      if (!BinaryUtils.compareBytes(filterHeader.hash, cpHash)) {
        final expectedHex = _formatBlockHash(cpHash);
        final actualHex = _formatBlockHash(filterHeader.hash);
        final expectedRaw = BinaryUtils.bytesToHex(cpHash);
        final actualRaw = BinaryUtils.bytesToHex(filterHeader.hash);
        print('FilterSync: Filter header at $cpHeight does not match checkpoint');
        print('FilterSync: Expected (reversed): $expectedHex');
        print('FilterSync: Actual (reversed):   $actualHex');
        print('FilterSync: Expected (raw): $expectedRaw');
        print('FilterSync: Actual (raw):   $actualRaw');
        print('FilterSync: startHeight=$startHeight, endHeight=$endHeight, filterHeaders.length=${_filterHeaders.length}');
        return false;
      }
    }
    return true;
  }

  int _checkpointHeightForIndex(int index, int stopHeight) {
    final candidate = ((index + 1) * _checkpointSpacing) - 1;
    if (stopHeight < 0) return -1;
    if (candidate > stopHeight) return stopHeight;
    return candidate;
  }

  void _completeSyncIfNeeded() {
    final completer = _syncCompleter;
    print('FilterSync: _completeSyncIfNeeded called, completer=${completer != null ? (completer.isCompleted ? "completed" : "pending") : "null"}');
    if (completer != null && !completer.isCompleted) {
      print('FilterSync: Completing sync, filterHeaders=${_filterHeaders.length}, chainHeight=${chainState.height}');
      completer.complete();
    }
  }

  String _formatBlockHash(Uint8List hash) {
    final reversed = Uint8List.fromList(hash.reversed.toList());
    return BinaryUtils.bytesToHex(reversed);
  }

  int? _resolvePendingFilterHeight(Uint8List blockHash) {
    final hashKey = _hashKey(blockHash);
    final directHeight = _pendingFilterHeightsByHash.remove(hashKey);
    
    if (directHeight != null) {
      _pendingFilterRequests.remove(directHeight);
      return directHeight;
    }
    
    final fallbackEntry = _consumeNextPendingFilterRequest();
    if (fallbackEntry != null) {
      if (!BinaryUtils.compareBytes(fallbackEntry.value, blockHash)) {
        final expectedHex = _formatBlockHash(fallbackEntry.value);
        final receivedHex = _formatBlockHash(blockHash);
        print('FilterSync: Warning - expected hash $expectedHex for height ${fallbackEntry.key} but received $receivedHex');
      }
      return fallbackEntry.key;
    }
    
    return null;
  }
  
  MapEntry<int, Uint8List>? _consumeNextPendingFilterRequest() {
    if (_pendingFilterRequests.isEmpty) {
      return null;
    }
    final firstKey = _pendingFilterRequests.keys.first;
    final expectedHash = _pendingFilterRequests.remove(firstKey)!;
    _pendingFilterHeightsByHash.remove(_hashKey(expectedHash));
    return MapEntry(firstKey, expectedHash);
  }
  
  String _hashKey(Uint8List hash) {
    return BinaryUtils.bytesToHex(hash);
  }
}

