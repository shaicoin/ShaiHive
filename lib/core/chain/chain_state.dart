import 'dart:typed_data';
import '../chain/block_header.dart';
import '../chain/chain_params.dart';
import '../storage/header_storage.dart';
import '../utils/binary_utils.dart';

typedef ChainStateListener = void Function();

class ChainState {
  final ChainParams chainParams;
  final Map<int, BlockHeader> _cache = {};
  final Map<String, int> _hashToHeight = {};
  final List<Uint8List> _pendingHeaders = [];
  
  static const int _cacheSize = 100;
  
  HeaderStorage? _storage;
  int _persistedCount = 0;
  int _totalHeight = 0;
  bool _isFlushing = false;
  bool _isReady = false;
  
  late final Uint8List genesisHashLE;
  
  ChainStateListener? onStateChanged;

  ChainState({required this.chainParams}) {
    final genesisBE = BinaryUtils.hexToBytes(chainParams.genesisHashHex);
    genesisHashLE = Uint8List.fromList(genesisBE.reversed.toList());
  }

  int get height => _totalHeight;
  int get persistedCount => _persistedCount;
  bool get isLoaded => _isReady;

  BlockHeader? _getHeaderByIndex(int index) {
    if (index < 0 || index >= _totalHeight) return null;
    
    if (_cache.containsKey(index)) {
      return _cache[index];
    }
    
    final pendingIndex = index - _persistedCount;
    if (pendingIndex >= 0 && pendingIndex < _pendingHeaders.length) {
      final header = BlockHeader.parse(_pendingHeaders[pendingIndex], chainParams.headerLengthBytes);
      _addToCache(index, header);
      return header;
    }
    
    return null;
  }

  Future<BlockHeader?> _getHeaderByIndexAsync(int index) async {
    if (index < 0 || index >= _totalHeight) return null;
    
    if (_cache.containsKey(index)) {
      return _cache[index];
    }
    
    final pendingIndex = index - _persistedCount;
    if (pendingIndex >= 0 && pendingIndex < _pendingHeaders.length) {
      final header = BlockHeader.parse(_pendingHeaders[pendingIndex], chainParams.headerLengthBytes);
      _addToCache(index, header);
      return header;
    }
    
    if (_storage == null || index >= _persistedCount) return null;
    
    final bytes = await _storage!.readHeader(index);
    if (bytes == null) return null;
    
    final header = BlockHeader.parse(bytes, chainParams.headerLengthBytes);
    _addToCache(index, header);
    
    final hashHex = BinaryUtils.bytesToHex(header.getHash());
    _hashToHeight[hashHex] = index;
    
    return header;
  }

  BlockHeader? getHeader(int blockHeight) {
    if (blockHeight <= 0) return null;
    return _getHeaderByIndex(blockHeight - 1);
  }

  Future<BlockHeader?> getHeaderAsync(int blockHeight) async {
    if (blockHeight <= 0) return null;
    return _getHeaderByIndexAsync(blockHeight - 1);
  }

  Uint8List? getBlockHash(int blockHeight) {
    if (blockHeight == 0) return genesisHashLE;
    if (blockHeight < 0 || blockHeight > _totalHeight) return null;
    final header = _getHeaderByIndex(blockHeight - 1);
    return header?.getHash();
  }

  Future<Uint8List?> getBlockHashAsync(int blockHeight) async {
    if (blockHeight == 0) return genesisHashLE;
    if (blockHeight < 0 || blockHeight > _totalHeight) return null;
    final header = await _getHeaderByIndexAsync(blockHeight - 1);
    return header?.getHash();
  }

  String? getBlockHashHex(int blockHeight) {
    if (blockHeight == 0) {
      return BinaryUtils.bytesToHex(Uint8List.fromList(genesisHashLE.reversed.toList()));
    }
    if (blockHeight < 0 || blockHeight > _totalHeight) return null;
    final header = _getHeaderByIndex(blockHeight - 1);
    return header?.getHashHex();
  }

  int? findHeightByHash(Uint8List hash) {
    final hashHex = BinaryUtils.bytesToHex(hash);
    if (hashHex == BinaryUtils.bytesToHex(genesisHashLE)) {
      return 0;
    }
    final index = _hashToHeight[hashHex];
    if (index == null) return null;
    return index + 1;
  }

  Future<void> init() async {
    if (_isReady) return;
    
    _storage = await HeaderStorage.create(chainParams.headerLengthBytes);
    _persistedCount = await _storage!.getHeaderCount();
    _totalHeight = _persistedCount;
    
    if (_persistedCount > 0) {
      await _loadRecentHeaders();
    }
    
    _isReady = true;
    print('ChainState: Ready with $height headers');
    _emitStateChanged();
  }

  Future<void> _loadRecentHeaders() async {
    final loadCount = _persistedCount < _cacheSize ? _persistedCount : _cacheSize;
    final startIndex = _persistedCount - loadCount;
    
    final headers = await _storage!.readHeaders(startIndex, loadCount);
    for (var i = 0; i < headers.length; i++) {
      final index = startIndex + i;
      final header = BlockHeader.parse(headers[i], chainParams.headerLengthBytes);
      _cache[index] = header;
      final hashHex = BinaryUtils.bytesToHex(header.getHash());
      _hashToHeight[hashHex] = index;
    }
    print('ChainState: Cached $loadCount recent headers');
  }

  void _addToCache(int index, BlockHeader header) {
    if (_cache.length >= _cacheSize) {
      final oldest = _cache.keys.reduce((a, b) => a < b ? a : b);
      _cache.remove(oldest);
    }
    _cache[index] = header;
  }

  bool addHeader(BlockHeader header, Uint8List rawBytes) {
    final headerHash = header.getHash();
    final hashHex = BinaryUtils.bytesToHex(headerHash);

    if (_hashToHeight.containsKey(hashHex)) {
      return false;
    }

    if (_totalHeight == 0) {
      if (!BinaryUtils.compareBytes(header.previousBlockHash, genesisHashLE)) {
        return false;
      }
    } else {
      final prevHeader = _getHeaderByIndex(_totalHeight - 1);
      if (prevHeader == null) return false;
      final prevHash = prevHeader.getHash();
      if (!BinaryUtils.compareBytes(header.previousBlockHash, prevHash)) {
        return false;
      }
    }

    _hashToHeight[hashHex] = _totalHeight;
    _addToCache(_totalHeight, header);
    _pendingHeaders.add(Uint8List.fromList(rawBytes));
    _totalHeight++;
    return true;
  }

  Future<void> flushToStorage({int batchSize = 2000}) async {
    if (_storage == null || _pendingHeaders.isEmpty || _isFlushing) return;
    if (_pendingHeaders.length < batchSize) return;

    _isFlushing = true;
    final batch = List<Uint8List>.from(_pendingHeaders);
    _pendingHeaders.clear();

    try {
      await _storage!.appendBatch(batch);
      _persistedCount += batch.length;
      print('ChainState: Flushed ${batch.length} headers');
    } catch (e) {
      print('ChainState: Flush failed - $e');
      _pendingHeaders.insertAll(0, batch);
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> forceFlush() async {
    if (_storage == null || _pendingHeaders.isEmpty || _isFlushing) return;

    _isFlushing = true;
    final batch = List<Uint8List>.from(_pendingHeaders);
    _pendingHeaders.clear();

    try {
      await _storage!.appendBatch(batch);
      _persistedCount += batch.length;
      print('ChainState: Flushed ${batch.length} headers');
    } catch (e) {
      print('ChainState: Flush failed - $e');
      _pendingHeaders.insertAll(0, batch);
    } finally {
      _isFlushing = false;
    }
  }

  Future<void> truncate(int keepCount) async {
    if (keepCount < 0 || keepCount >= _totalHeight) return;

    final oldHeight = _totalHeight;
    
    _cache.removeWhere((key, _) => key >= keepCount);
    _hashToHeight.removeWhere((_, value) => value >= keepCount);

    if (keepCount < _persistedCount) {
      await _storage!.truncate(keepCount);
      _persistedCount = keepCount;
      _pendingHeaders.clear();
    } else {
      final keep = keepCount - _persistedCount;
      while (_pendingHeaders.length > keep) {
        _pendingHeaders.removeLast();
      }
    }
    
    _totalHeight = keepCount;

    print('ChainState: Truncated from $oldHeight to $keepCount');
    _emitStateChanged();
  }

  Future<void> reset() async {
    _cache.clear();
    _hashToHeight.clear();
    _pendingHeaders.clear();
    _persistedCount = 0;
    _totalHeight = 0;
    
    if (_storage != null) {
      await _storage!.reset();
    }
    
    _emitStateChanged();
  }

  Future<List<LocatorEntry>> buildBlockLocator() async {
    final entries = <LocatorEntry>[];
    int h = _totalHeight;
    int step = 1;

    if (h == 0) {
      entries.add(LocatorEntry(height: 0, hash: genesisHashLE));
      return entries;
    }

    while (h > 0) {
      final hash = await getBlockHashAsync(h);
      if (hash != null) {
        entries.add(LocatorEntry(height: h, hash: hash));
      }

      if (h <= step) break;

      if (entries.length >= 10) {
        step *= 2;
      }

      h -= step;
      if (h <= 0) break;
    }

    if (entries.isEmpty || entries.last.height != 0) {
      entries.add(LocatorEntry(height: 0, hash: genesisHashLE));
    }

    return entries;
  }

  void _emitStateChanged() {
    onStateChanged?.call();
  }
}

class LocatorEntry {
  final int height;
  final Uint8List hash;

  LocatorEntry({required this.height, required this.hash});
}
