import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/neutrino/neutrino_client.dart';
import '../../core/models/utxo.dart';
import '../../core/models/transaction.dart';
import '../../core/models/app_settings.dart';
import '../../core/crypto/bip44.dart';
import '../../core/crypto/bip32.dart';
import '../../core/chain/chain_params.dart';
import '../../core/storage/address_book_storage.dart';
import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:bech32/bech32.dart';

typedef ScanProgressCallback = void Function(int scanned, int total, String status);

class NeutrinoWalletRepository {
  final NeutrinoClient client;
  final ChainParams chainParams;
  final String walletId;
  final AddressBookStorage addressStorage;
  Bip44Wallet? _hdWallet;
  List<Utxo> _utxos = [];
  int _currentAddressIndex = 0;
  Map<AddressType, int> _highestIndexByType = {};
  bool _isInitialized = false;
  int _lastScannedHeight = 0;
  final Map<AddressType, List<String>> _addressCache = {};
  static const int _maxReceiveAddresses = 42;
  static const int _maxChangeAddresses = 10;
  
  ScanProgressCallback? onScanProgress;

  NeutrinoWalletRepository({
    required this.client,
    required this.chainParams,
    required this.walletId,
    required this.addressStorage,
  });

  bool get isInitialized => _isInitialized;

  Future<void> clearLocalState() async {
    _utxos.clear();
    _lastScannedHeight = 0;
    _isInitialized = false;
    _addressCache.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('wallet_${walletId}_lastScannedHeight');
    await prefs.remove('wallet_${walletId}_utxos');
  }

  void handleReorg(int fromHeight) {
    final affectedUtxos = _utxos.where((u) => u.blockHeight != null && u.blockHeight! >= fromHeight).toList();
    if (affectedUtxos.isNotEmpty) {
      print('NeutrinoWallet: Reorg affects ${affectedUtxos.length} UTXOs from height $fromHeight');
      for (final utxo in affectedUtxos) {
        utxo.confirmed = false;
      }
    }
  }

  Future<void> checkBlockForTransactions(int height) async {
    if (_hdWallet == null || !_isInitialized) return;
    if (!client.hasPeerReady) return;
    
    final chainHeight = client.blockHeight;
    if (height >= chainHeight) {
      print('NeutrinoWallet: Block $height not yet in chain (tip=$chainHeight), waiting...');
      await Future.delayed(const Duration(milliseconds: 500));
    }
    
    final scripts = <Uint8List>[];
    final addresses = <String>[];
    
    for (var i = 0; i < _maxReceiveAddresses; i++) {
      final node = _hdWallet!.getReceiveAddress(0, i);
      final address = _deriveNativeSegWit(node.publicKey);
      addresses.add(address);
      scripts.add(_addressToScript(address));
    }
    
    for (var i = 0; i < _maxChangeAddresses; i++) {
      final changeNode = _hdWallet!.getChangeAddress(0, i);
      final changeAddress = _deriveNativeSegWit(changeNode.publicKey);
      addresses.add(changeAddress);
      scripts.add(_addressToScript(changeAddress));
    }
    
    print('NeutrinoWallet: Checking block $height for ${scripts.length} addresses');
    print('NeutrinoWallet: First receive address: ${addresses.isNotEmpty ? addresses[0] : "none"}');
    
    try {
      final matches = await client.filterMatchesScripts(height, scripts);
      if (matches) {
        print('NeutrinoWallet: Block $height has potential matches, fetching...');
        final blockData = await client.requestBlock(height);
        if (blockData != null) {
          final allSpentOutpoints = <String>{};
          
          for (var i = 0; i < scripts.length; i++) {
            final result = await _extractUtxosAndSpentsFromBlock(blockData, addresses[i], scripts[i], height);
            final utxos = result['utxos'] as List<Utxo>;
            final spentOutpoints = result['spentOutpoints'] as Set<String>;
            allSpentOutpoints.addAll(spentOutpoints);
            
            for (final utxo in utxos) {
              final existingIdx = _utxos.indexWhere((u) => u.outpoint == utxo.outpoint);
              if (existingIdx >= 0) {
                final existing = _utxos[existingIdx];
                _utxos[existingIdx] = Utxo(
                  txid: existing.txid,
                  vout: existing.vout,
                  value: existing.value,
                  scriptPubKey: existing.scriptPubKey,
                  address: existing.address,
                  blockHeight: height,
                  confirmed: true,
                  frozen: existing.frozen,
                );
                print('NeutrinoWallet: Confirmed pending UTXO ${utxo.outpoint} at height $height');
              } else {
                _utxos.add(utxo);
                print('NeutrinoWallet: Found new UTXO ${utxo.outpoint} at height $height');
              }
            }
          }
          
          final spentCount = _utxos.where((u) => allSpentOutpoints.contains(u.outpoint)).length;
          if (spentCount > 0) {
            print('NeutrinoWallet: Removing $spentCount spent UTXOs at height $height');
            _utxos.removeWhere((u) => allSpentOutpoints.contains(u.outpoint));
          }
          
          _lastScannedHeight = height;
          unawaited(_persistWalletState());
        } else {
          print('NeutrinoWallet: Block data not received for $height');
        }
      } else {
        print('NeutrinoWallet: Block $height has no matches for our addresses');
        _lastScannedHeight = height;
      }
    } catch (e) {
      print('NeutrinoWallet: Error checking block $height - $e');
    }
  }

  Future<void> initializeFromSeed(Uint8List seed) async {
    await loadLocalState(seed);
    await syncWithNetwork();
  }

  Future<void> loadLocalState(Uint8List seed) async {
    print('NeutrinoWallet: Preparing local state');
    _hdWallet = Bip44Wallet.fromSeed(seed, chainParams.coinType);
    _isInitialized = true;
    _addressCache.clear();

    final stored = await addressStorage.load(walletId);
    if (stored.isEmpty) {
      _highestIndexByType = {};
    } else {
      _highestIndexByType = {};
      for (final entry in stored.entries) {
        _highestIndexByType[entry.key] = entry.value.clamp(0, _maxReceiveAddresses - 1);
      }
    }

    _syncAddressCursor();
    
    await _loadCachedWalletState();
  }
  
  Future<void> _loadCachedWalletState() async {
    final prefs = await SharedPreferences.getInstance();
    _lastScannedHeight = prefs.getInt('wallet_${walletId}_lastScannedHeight') ?? 0;
    
    final utxoJson = prefs.getString('wallet_${walletId}_utxos');
    if (utxoJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(utxoJson);
        _utxos = decoded.map((e) => Utxo.fromJson(e as Map<String, dynamic>)).toList();
        print('NeutrinoWallet: Loaded ${_utxos.length} cached UTXOs, lastScanned=$_lastScannedHeight');
        for (final utxo in _utxos) {
          print('NeutrinoWallet: UTXO: ${utxo.txid}:${utxo.vout} = ${utxo.value} sats (confirmed=${utxo.confirmed}, height=${utxo.blockHeight})');
        }
      } catch (e) {
        print('NeutrinoWallet: Failed to load cached UTXOs - $e');
        _utxos = [];
      }
    }
  }
  
  Future<void> _persistWalletState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wallet_${walletId}_lastScannedHeight', _lastScannedHeight);
    final utxoJson = jsonEncode(_utxos.map((u) => u.toJson()).toList());
    await prefs.setString('wallet_${walletId}_utxos', utxoJson);
  }
  
  int get lastScannedHeight => _lastScannedHeight;

  Future<void> syncWithNetwork() async {
    if (_hdWallet == null) {
      throw Exception('Wallet not initialized');
    }

    if (!client.isConnected) {
      await client.connect();
    }
    await client.waitForPeerReady();
    await client.syncToTip();
  }

  Future<void> finalizeDiscovery() async {
    final discoveredHighest = max(0, _currentAddressIndex - 1);
    final currentNative = _highestIndexByType[AddressType.nativeSegwit] ?? -1;
    if (discoveredHighest > currentNative) {
      _highestIndexByType[AddressType.nativeSegwit] = discoveredHighest;
      await _persistAddressState();
    }
  }

  Future<void> discoverUtxos({bool fullRescan = false, int startHeight = 0}) async {
    print('NeutrinoWallet: discoverUtxos called - fullRescan=$fullRescan, startHeight=$startHeight, cachedHeight=$_lastScannedHeight, cachedUtxos=${_utxos.length}');
    
    if (_hdWallet == null) {
      throw Exception('Wallet not initialized');
    }

    if (!client.hasPeerReady) {
      await client.waitForPeerReady();
    }

    if (fullRescan) {
      print('NeutrinoWallet: FULL RESCAN - clearing ${_utxos.length} UTXOs and resetting lastScannedHeight from $_lastScannedHeight to 0');
      _utxos.clear();
      _lastScannedHeight = 0;
      await _persistWalletState();
    }
    
    final scripts = <Uint8List>[];
    final addresses = <String>[];
    
    print('NeutrinoWallet: Building address list - maxReceive=$_maxReceiveAddresses, maxChange=$_maxChangeAddresses');
    
    for (var i = 0; i < _maxReceiveAddresses; i++) {
      final node = _hdWallet!.getReceiveAddress(0, i);
      final address = _deriveNativeSegWit(node.publicKey);
      addresses.add(address);
      scripts.add(_addressToScript(address));
      if (i == 0) {
        print('NeutrinoWallet: First receive address: $address');
        print('NeutrinoWallet: First script (hex): ${_bytesToHex(scripts.last)}');
      }
    }
    
    for (var i = 0; i < _maxChangeAddresses; i++) {
      final changeNode = _hdWallet!.getChangeAddress(0, i);
      final changeAddress = _deriveNativeSegWit(changeNode.publicKey);
      addresses.add(changeAddress);
      scripts.add(_addressToScript(changeAddress));
    }
    
    print('NeutrinoWallet: Total addresses to scan: ${addresses.length} ($_maxReceiveAddresses receive + $_maxChangeAddresses change)');

    int effectiveStartHeight;
    if (fullRescan) {
      effectiveStartHeight = startHeight.clamp(0, client.blockHeight);
    } else if (_lastScannedHeight > 0 && startHeight <= _lastScannedHeight) {
      effectiveStartHeight = _lastScannedHeight;
      print('NeutrinoWallet: Resuming from cached height $_lastScannedHeight');
    } else {
      effectiveStartHeight = startHeight.clamp(0, client.blockHeight);
    }
    final targetHeight = client.blockHeight;
    final blocksToScan = targetHeight - effectiveStartHeight;
    print('NeutrinoWallet: Scanning from height $effectiveStartHeight to $targetHeight ($blocksToScan blocks)');
    onScanProgress?.call(0, blocksToScan, 'Scanning $effectiveStartHeight → $targetHeight');

    final matchedBlocks = <int>{};
    int blocksScanned = 0;
    int filtersMissing = 0;
    DateTime lastProgressTime = DateTime.now();
    const int batchSize = 100;
    
    print('NeutrinoWallet: Starting filter scan loop from $effectiveStartHeight to $targetHeight');
    
    for (var height = effectiveStartHeight; height < targetHeight; height++) {
      if (!client.hasPeerReady) {
        print('NeutrinoWallet: Peer disconnected at height $height, stopping scan');
        return;
      }

      if ((height - effectiveStartHeight) % batchSize == 0) {
        final batchEnd = (height + batchSize - 1).clamp(height, targetHeight - 1);
        try {
          await client.prefetchFilters(height, batchEnd);
        } catch (e) {
          print('NeutrinoWallet: Prefetch failed at $height: $e');
        }
        await Future.delayed(const Duration(milliseconds: 200));
      }

      final now = DateTime.now();
      if (now.difference(lastProgressTime).inMilliseconds >= 250) {
        lastProgressTime = now;
        final pct = (blocksScanned * 100 / blocksToScan).toStringAsFixed(1);
        onScanProgress?.call(blocksScanned, blocksToScan, 'Checking height $height / $targetHeight ($pct%)');
      }

      try {
        final matches = await client.filterMatchesScripts(height, scripts);
        if (matches) {
          print('NeutrinoWallet: Filter match at height $height');
          matchedBlocks.add(height);
        }
      } catch (e) {
        print('NeutrinoWallet: Filter check failed at $height - $e');
        filtersMissing++;
        if (filtersMissing <= 5) {
          print('NeutrinoWallet: Missing filter #$filtersMissing at height $height');
        }
        onScanProgress?.call(blocksScanned, blocksToScan, 'Height $height - retrying...');
        continue;
      }
      
      blocksScanned++;
      if (blocksScanned % 500 == 0 || blocksScanned == blocksToScan) {
        final pct = (blocksScanned * 100 / blocksToScan).toStringAsFixed(1);
        print('NeutrinoWallet: Scanned $blocksScanned / $blocksToScan blocks ($pct%), ${matchedBlocks.length} matches');
      }
    }

    print('NeutrinoWallet: Filter scan complete - ${matchedBlocks.length} matches, $filtersMissing filters missing');
    if (matchedBlocks.isEmpty) {
      onScanProgress?.call(blocksToScan, blocksToScan, 'Scan complete - no matches');
    } else {
      onScanProgress?.call(blocksToScan, blocksToScan, 'Found ${matchedBlocks.length} potential blocks');
    }

    int blocksFetched = 0;
    final sortedMatches = matchedBlocks.toList()..sort();
    for (final height in sortedMatches) {
      if (!client.hasPeerReady) {
        print('NeutrinoWallet: Peer disconnected while fetching blocks');
        break;
      }
      
      onScanProgress?.call(blocksFetched, sortedMatches.length, 'Fetching block $height (${blocksFetched + 1}/${sortedMatches.length})');
      
      try {
        print('NeutrinoWallet: Fetching block at height $height');
        final blockData = await client.requestBlock(height);
        
        if (blockData == null) {
          print('NeutrinoWallet: Block data not received for height $height');
          continue;
        }
        
        print('NeutrinoWallet: Processing block $height (${blockData.length} bytes)');

        final allSpentOutpoints = <String>{};
        
        for (var i = 0; i < scripts.length; i++) {
          final result = await _extractUtxosAndSpentsFromBlock(blockData, addresses[i], scripts[i], height);
          final utxos = result['utxos'] as List<Utxo>;
          final spentOutpoints = result['spentOutpoints'] as Set<String>;
          allSpentOutpoints.addAll(spentOutpoints);
          
          if (utxos.isNotEmpty) {
            print('NeutrinoWallet: Found ${utxos.length} UTXOs for address ${addresses[i]} at height $height');
            for (final utxo in utxos) {
              print('NeutrinoWallet:   UTXO: ${utxo.outpoint} = ${utxo.value} sats');
              if (!_utxos.any((u) => u.outpoint == utxo.outpoint)) {
                _utxos.add(utxo);
              }
            }
            if (i > (_highestIndexByType[AddressType.nativeSegwit] ?? 0)) {
              _highestIndexByType[AddressType.nativeSegwit] = i;
            }
          }
        }
        
        final spentCount = _utxos.where((u) => allSpentOutpoints.contains(u.outpoint)).length;
        if (spentCount > 0) {
          print('NeutrinoWallet: Removing $spentCount spent UTXOs at height $height');
          _utxos.removeWhere((u) => allSpentOutpoints.contains(u.outpoint));
        }
        
        blocksFetched++;
      } catch (e, stack) {
        print('NeutrinoWallet: Error processing block $height - $e');
        print('NeutrinoWallet: Stack: $stack');
      }
      
      await Future.delayed(Duration.zero);
    }

    _lastScannedHeight = targetHeight;
    await _persistAddressState();
    await _persistWalletState();
    final totalBalance = _utxos.fold<int>(0, (sum, u) => sum + u.value);
    print('NeutrinoWallet: Discovery complete - ${_utxos.length} UTXOs, total balance: $totalBalance sats');
    onScanProgress?.call(blocksToScan, blocksToScan, 'Complete');
  }
  
  String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String? _getBlockHashAtHeight(int height) {
    return client.getBlockHashHexAtHeight(height);
  }

  Future<Map<String, dynamic>> _extractUtxosAndSpentsFromBlock(
    Uint8List blockData,
    String address,
    Uint8List targetScript,
    int blockHeight,
  ) async {
    final utxos = <Utxo>[];
    final spentOutpoints = <String>{};
    
    try {
      var offset = chainParams.headerLengthBytes;
      
      final txCountData = _readVarInt(blockData, offset);
      offset = (txCountData['offset'] as num).toInt();
      final txCount = (txCountData['value'] as num).toInt();

      for (var txIndex = 0; txIndex < txCount; txIndex++) {
        final txStart = offset;
        
        offset += 4;

        bool hasWitness = false;
        int witnessMarkerOffset = offset;
        if (offset + 2 <= blockData.length &&
            blockData[offset] == 0x00 &&
            blockData[offset + 1] == 0x01) {
          hasWitness = true;
          offset += 2;
        }

        final inputCountData = _readVarInt(blockData, offset);
        offset = (inputCountData['offset'] as num).toInt();
        final inputCount = (inputCountData['value'] as num).toInt();

        for (var i = 0; i < inputCount; i++) {
          final prevTxHash = blockData.sublist(offset, offset + 32);
          offset += 32;
          final prevVout = _readUint32LE(blockData, offset);
          offset += 4;
          
          final prevTxid = _bytesToHex(Uint8List.fromList(prevTxHash.reversed.toList()));
          final outpoint = '$prevTxid:$prevVout';
          spentOutpoints.add(outpoint);
          
          final scriptLenData = _readVarInt(blockData, offset);
          offset = (scriptLenData['offset'] as num).toInt();
          offset += (scriptLenData['value'] as num).toInt();
          
          offset += 4;
        }

        final outputCountData = _readVarInt(blockData, offset);
        offset = (outputCountData['offset'] as num).toInt();
        final outputCount = (outputCountData['value'] as num).toInt();
        
        final matchingOutputs = <int, int>{};

        for (var i = 0; i < outputCount; i++) {
          final value = _readUint64LE(blockData, offset);
          offset += 8;
          
          final scriptLenData = _readVarInt(blockData, offset);
          offset = (scriptLenData['offset'] as num).toInt();
          final scriptLen = (scriptLenData['value'] as num).toInt();
          
          final scriptPubKey = blockData.sublist(offset, offset + scriptLen);
          offset += scriptLen;

          if (_compareBytes(scriptPubKey, targetScript)) {
            matchingOutputs[i] = value;
          }
        }
        
        final afterOutputsOffset = offset;

        if (hasWitness) {
          for (var i = 0; i < inputCount; i++) {
            final witnessCountData = _readVarInt(blockData, offset);
            offset = (witnessCountData['offset'] as num).toInt();
            final witnessCount = (witnessCountData['value'] as num).toInt();
            
            for (var j = 0; j < witnessCount; j++) {
              final itemLenData = _readVarInt(blockData, offset);
              offset = (itemLenData['offset'] as num).toInt();
              offset += (itemLenData['value'] as num).toInt();
            }
          }
        }

        offset += 4;
        
        if (matchingOutputs.isNotEmpty) {
          String txid;
          if (hasWitness) {
            txid = _computeSegwitTxid(blockData, txStart, witnessMarkerOffset, afterOutputsOffset, offset);
          } else {
            txid = _computeTxid(blockData, txStart, offset - txStart);
          }
          
          for (final entry in matchingOutputs.entries) {
            final vout = entry.key;
            final value = entry.value;
            
            utxos.add(Utxo(
              txid: txid,
              vout: vout,
              value: value,
              scriptPubKey: _bytesToHex(targetScript),
              address: address,
              blockHeight: blockHeight,
              confirmed: true,
            ));
            
            print('NeutrinoWallet: Found UTXO: $txid:$vout = $value sats at height $blockHeight');
          }
        }
      }
    } catch (e) {
      print('NeutrinoWallet: Error extracting UTXOs - $e');
    }

    return {'utxos': utxos, 'spentOutpoints': spentOutpoints};
  }
  
  String _computeSegwitTxid(Uint8List blockData, int txStart, int witnessMarkerOffset, int afterOutputsOffset, int txEnd) {
    final nonWitnessTx = <int>[];
    
    nonWitnessTx.addAll(blockData.sublist(txStart, witnessMarkerOffset));
    nonWitnessTx.addAll(blockData.sublist(witnessMarkerOffset + 2, afterOutputsOffset));
    nonWitnessTx.addAll(blockData.sublist(txEnd - 4, txEnd));
    
    final hash1 = sha256.convert(nonWitnessTx);
    final hash2 = sha256.convert(hash1.bytes);
    return _bytesToHex(Uint8List.fromList(hash2.bytes.reversed.toList()));
  }

  String _computeTxid(Uint8List blockData, int start, int length) {
    final txData = blockData.sublist(start, start + length);
    final hash1 = sha256.convert(txData);
    final hash2 = sha256.convert(hash1.bytes);
    return _bytesToHex(Uint8List.fromList(hash2.bytes.reversed.toList()));
  }

  int getBalance() {
    return _utxos.where((u) => u.confirmed).fold<int>(0, (sum, u) => sum + u.value);
  }

  int getUnconfirmedBalance() {
    return _utxos.where((u) => !u.confirmed).fold<int>(0, (sum, u) => sum + u.value);
  }

  List<Utxo> getUtxos() {
    return List.unmodifiable(_utxos);
  }

  List<Utxo> getSpendableUtxos() {
    return _utxos.where((u) => u.isSpendable).toList();
  }

  void freezeUtxo(String outpoint) {
    final idx = _utxos.indexWhere((u) => u.outpoint == outpoint);
    if (idx >= 0) {
      _utxos[idx].frozen = true;
      unawaited(_persistWalletState());
    }
  }

  void unfreezeUtxo(String outpoint) {
    final idx = _utxos.indexWhere((u) => u.outpoint == outpoint);
    if (idx >= 0) {
      _utxos[idx].frozen = false;
      unawaited(_persistWalletState());
    }
  }

  void setUtxoFrozen(String outpoint, bool frozen) {
    final idx = _utxos.indexWhere((u) => u.outpoint == outpoint);
    if (idx >= 0) {
      _utxos[idx].frozen = frozen;
      unawaited(_persistWalletState());
    }
  }

  Future<String> getNewReceiveAddress({AddressType addressType = AddressType.nativeSegwit}) async {
    if (_hdWallet == null) {
      throw Exception('Wallet not initialized');
    }

    final nextIndex = (_highestIndexByType[addressType] ?? -1) + 1;
    if (nextIndex >= _maxReceiveAddresses) {
      throw Exception('Maximum address limit reached ($_maxReceiveAddresses)');
    }
    final node = _hdWallet!.getReceiveAddress(0, nextIndex);
    final address = _deriveAddress(node.publicKey, addressType);
    _highestIndexByType[addressType] = nextIndex;
    _addressCache.remove(addressType);
    if (addressType == AddressType.nativeSegwit && nextIndex >= _currentAddressIndex) {
      _currentAddressIndex = nextIndex + 1;
    }
    await _persistAddressState();
    return address;
  }

  List<String> getCurrentAddresses(int count, AddressType addressType) {
    final all = getAllAddresses(addressType);
    if (all.length <= count) {
      return all;
    }
    return all.sublist(0, count);
  }

  List<String> getAllAddresses(AddressType addressType) {
    if (_hdWallet == null) {
      throw Exception('Wallet not initialized');
    }
    final highest = _highestIndexByType[addressType] ?? -1;
    if (highest < 0) {
      return [];
    }
    final cached = _addressCache[addressType];
    if (cached != null && cached.length == highest + 1) {
      return List.unmodifiable(cached);
    }
    final addresses = <String>[];
    for (var i = 0; i <= highest; i++) {
      final node = _hdWallet!.getReceiveAddress(0, i);
      addresses.add(_deriveAddress(node.publicKey, addressType));
    }
    _addressCache[addressType] = addresses;
    return List.unmodifiable(addresses);
  }

  int getAddressCount(AddressType addressType) {
    final highest = _highestIndexByType[addressType] ?? -1;
    return highest + 1;
  }

  List<String> getAddressesInRange(AddressType addressType, int start, int end) {
    if (_hdWallet == null) {
      throw Exception('Wallet not initialized');
    }
    final highest = _highestIndexByType[addressType] ?? -1;
    if (highest < 0 || start > highest) {
      return [];
    }
    final effectiveEnd = end > highest ? highest : end;
    final cached = _addressCache[addressType];
    if (cached != null && cached.length > effectiveEnd) {
      return List.unmodifiable(cached.sublist(start, effectiveEnd + 1));
    }
    final addresses = <String>[];
    for (var i = start; i <= effectiveEnd; i++) {
      final node = _hdWallet!.getReceiveAddress(0, i);
      addresses.add(_deriveAddress(node.publicKey, addressType));
    }
    return addresses;
  }

  String _deriveAddress(Uint8List publicKey, AddressType addressType) {
    switch (addressType) {
      case AddressType.nativeSegwit:
        return _deriveNativeSegWit(publicKey);
      case AddressType.taproot:
        return _deriveTaproot(publicKey);
      case AddressType.legacy:
        return _deriveLegacy(publicKey);
      case AddressType.p2shSegwit:
        return _deriveP2SHSegWit(publicKey);
    }
  }

  String _deriveNativeSegWit(Uint8List publicKey) {
    final sha256Hash = sha256.convert(publicKey);
    final pubKeyHash = pc.RIPEMD160Digest().process(
      Uint8List.fromList(sha256Hash.bytes),
    );

    final program = _convertBits(pubKeyHash, 8, 5, true);
    final data = [0, ...program];
    return bech32.encode(Bech32(chainParams.bech32Hrp, data));
  }

  String _deriveTaproot(Uint8List publicKey) {
    Uint8List xOnlyPubKey;
    if (publicKey.length == 33) {
      xOnlyPubKey = Uint8List.fromList(publicKey.sublist(1));
    } else if (publicKey.length == 65) {
      xOnlyPubKey = Uint8List.fromList(publicKey.sublist(1, 33));
    } else {
      throw Exception('Invalid public key length');
    }

    final tweakedKey = _taprootTweakPubkey(xOnlyPubKey);
    final program = _convertBits(tweakedKey, 8, 5, true);
    return _encodeBech32m(chainParams.bech32Hrp, 1, program);
  }

  Uint8List _taprootTweakPubkey(Uint8List xOnlyPubKey) {
    final curve = pc.ECCurve_secp256k1();
    final G = curve.G;
    final n = curve.n;
    final p = BigInt.parse(
      'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F',
      radix: 16,
    );
    
    final xInt = BigInt.parse(_bytesToHex(xOnlyPubKey), radix: 16);
    final ySquared = (xInt.modPow(BigInt.from(3), p) + BigInt.from(7)) % p;
    final y = ySquared.modPow((p + BigInt.one) ~/ BigInt.from(4), p);
    
    final yIsEven = y.isEven;
    final yFinal = yIsEven ? y : (p - y);
    
    final P = curve.curve.createPoint(xInt, yFinal);
    
    final tweak = _taggedHash('TapTweak', xOnlyPubKey);
    final tweakInt = BigInt.parse(_bytesToHex(tweak), radix: 16) % n;
    if (tweakInt == BigInt.zero) {
      throw Exception('Invalid tweak');
    }
    
    final tweakPoint = (G * tweakInt)!;
    final Q = (P + tweakPoint)!;
    
    final qX = Q.x!.toBigInteger()!;
    return _bigIntToBytes(qX, 32);
  }

  Uint8List _taggedHash(String tag, Uint8List data) {
    final tagHash = sha256.convert(tag.codeUnits).bytes;
    final preimage = <int>[...tagHash, ...tagHash, ...data];
    return Uint8List.fromList(sha256.convert(preimage).bytes);
  }

  Uint8List _bigIntToBytes(BigInt value, int length) {
    final result = Uint8List(length);
    var temp = value;
    for (var i = length - 1; i >= 0; i--) {
      result[i] = (temp & BigInt.from(0xff)).toInt();
      temp = temp >> 8;
    }
    return result;
  }

  String _encodeBech32m(String hrp, int witnessVersion, List<int> program) {
    final data = [witnessVersion, ...program];
    final values = _expandHrp(hrp) + data;
    final checksum = _createBech32mChecksum(values);
    final combined = data + checksum;
    
    const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
    final encoded = StringBuffer(hrp)..write('1');
    for (final v in combined) {
      encoded.write(charset[v]);
    }
    return encoded.toString();
  }

  List<int> _expandHrp(String hrp) {
    final result = <int>[];
    for (final c in hrp.codeUnits) {
      result.add(c >> 5);
    }
    result.add(0);
    for (final c in hrp.codeUnits) {
      result.add(c & 31);
    }
    return result;
  }

  List<int> _createBech32mChecksum(List<int> values) {
    const bech32mConst = 0x2bc830a3;
    final polymod = _bech32Polymod([...values, 0, 0, 0, 0, 0, 0]) ^ bech32mConst;
    final checksum = <int>[];
    for (var i = 0; i < 6; i++) {
      checksum.add((polymod >> (5 * (5 - i))) & 31);
    }
    return checksum;
  }

  int _bech32Polymod(List<int> values) {
    const gen = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
    var chk = 1;
    for (final v in values) {
      final top = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v;
      for (var i = 0; i < 5; i++) {
        if ((top >> i) & 1 == 1) {
          chk ^= gen[i];
        }
      }
    }
    return chk;
  }

  String _deriveLegacy(Uint8List publicKey) {
    final sha256Hash = sha256.convert(publicKey);
    final pubKeyHash = pc.RIPEMD160Digest().process(
      Uint8List.fromList(sha256Hash.bytes),
    );

    final versionedPayload = Uint8List(21);
    versionedPayload[0] = chainParams.pubKeyAddressPrefix;
    versionedPayload.setRange(1, 21, pubKeyHash);

    return bs58check.encode(versionedPayload);
  }

  String _deriveP2SHSegWit(Uint8List publicKey) {
    final sha256Hash = sha256.convert(publicKey);
    final pubKeyHash = pc.RIPEMD160Digest().process(
      Uint8List.fromList(sha256Hash.bytes),
    );

    final redeemScript = Uint8List(22);
    redeemScript[0] = 0x00;
    redeemScript[1] = 0x14;
    redeemScript.setRange(2, 22, pubKeyHash);

    final scriptHash = pc.RIPEMD160Digest().process(
      Uint8List.fromList(sha256.convert(redeemScript).bytes),
    );

    final versionedPayload = Uint8List(21);
    versionedPayload[0] = chainParams.scriptAddressPrefix;
    versionedPayload.setRange(1, 21, scriptHash);

    return bs58check.encode(versionedPayload);
  }

  List<int> _convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;

    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        throw Exception('Invalid value for conversion');
      }
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad && bits > 0) {
      result.add((acc << (toBits - bits)) & maxv);
    }

    return result;
  }

  void _ensureAddressType(AddressType type) {
    if (_highestIndexByType.containsKey(type)) {
      return;
    }
    _highestIndexByType[type] = -1;
  }

  Future<void> _persistAddressState() {
    return addressStorage.save(walletId, Map<AddressType, int>.from(_highestIndexByType));
  }

  void _syncAddressCursor() {
    final highest = _highestIndexByType[AddressType.nativeSegwit];
    if (highest == null) {
      return;
    }
    _currentAddressIndex = max(_currentAddressIndex, highest + 1);
  }

  Uint8List _addressToScript(String address) {
    final isBech32 = address.toLowerCase().startsWith(chainParams.bech32Hrp);
    if (isBech32) {
      final decoded = _decodeBech32OrBech32m(address);
      final witnessVersion = decoded['version'] as int;
      final program = decoded['program'] as List<int>;
      
      final script = <int>[];
      if (witnessVersion == 0) {
        script.add(0x00);
      } else {
        script.add(0x50 + witnessVersion);
      }
      script.add(program.length);
      script.addAll(program);
      
      return Uint8List.fromList(script);
    } else {
      final decoded = bs58check.decode(address);
      if (decoded.length < 21) {
        throw Exception('Invalid base58 address');
      }
      final version = decoded[0];
      final payload = decoded.sublist(1);
      if (payload.length != 20) {
        throw Exception('Invalid base58 payload length');
      }
      
      if (version == chainParams.pubKeyAddressPrefix) {
        final script = <int>[];
        script.add(0x76);
        script.add(0xa9);
        script.add(0x14);
        script.addAll(payload);
        script.add(0x88);
        script.add(0xac);
        return Uint8List.fromList(script);
      }
      
      if (version == chainParams.scriptAddressPrefix) {
        final script = <int>[];
        script.add(0xa9);
        script.add(0x14);
        script.addAll(payload);
        script.add(0x87);
        return Uint8List.fromList(script);
      }
      
      throw Exception('Unsupported address version $version for ${chainParams.name}');
    }
  }

  Map<String, dynamic> _decodeBech32OrBech32m(String address) {
    const charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
    final lower = address.toLowerCase();
    final separatorIndex = lower.lastIndexOf('1');
    if (separatorIndex < 1) {
      throw Exception('Invalid bech32 address');
    }
    
    final hrp = lower.substring(0, separatorIndex);
    final dataStr = lower.substring(separatorIndex + 1);
    
    final data = <int>[];
    for (final c in dataStr.codeUnits) {
      final idx = charset.indexOf(String.fromCharCode(c));
      if (idx < 0) {
        throw Exception('Invalid bech32 character');
      }
      data.add(idx);
    }
    
    final expanded = _expandHrp(hrp) + data;
    final polymod = _bech32Polymod(expanded);
    
    if (polymod != 1 && polymod != 0x2bc830a3) {
      throw Exception('Invalid bech32/bech32m checksum');
    }
    
    final witnessVersion = data[0];
    final payload = data.sublist(1, data.length - 6);
    final program = _convertBits(payload, 5, 8, false);
    
    return {
      'hrp': hrp,
      'version': witnessVersion,
      'program': program,
    };
  }

  int estimateTransactionSize(int inputCount, int outputCount) {
    const baseSize = 10;
    const p2wpkhInputSize = 68;
    const witnessSize = 107;
    const p2wpkhOutputSize = 31;
    
    final nonWitnessSize = baseSize + (p2wpkhInputSize * inputCount) + (p2wpkhOutputSize * outputCount);
    final witnessWeight = witnessSize * inputCount;
    
    final vsize = ((nonWitnessSize * 4 + witnessWeight) + 3) ~/ 4;
    return vsize;
  }

  int estimateFee(int inputCount, int outputCount, int feePerByte) {
    return estimateTransactionSize(inputCount, outputCount) * feePerByte;
  }

  Future<Map<String, dynamic>> calculateMaxSendAmount(int feePerByte, {List<String>? selectedOutpoints}) async {
    List<Utxo> availableUtxos;
    if (selectedOutpoints != null && selectedOutpoints.isNotEmpty) {
      availableUtxos = _utxos.where((u) => selectedOutpoints.contains(u.outpoint)).toList();
    } else {
      availableUtxos = _utxos.where((u) => u.isSpendable).toList();
    }
    
    if (availableUtxos.isEmpty) {
      return {'maxAmount': 0, 'fee': 0, 'inputCount': 0};
    }
    
    final totalInput = availableUtxos.fold<int>(0, (sum, u) => sum + u.value);
    final fee = estimateFee(availableUtxos.length, 1, feePerByte);
    final maxAmount = totalInput - fee;
    
    return {
      'maxAmount': maxAmount > 0 ? maxAmount : 0,
      'fee': fee,
      'inputCount': availableUtxos.length,
    };
  }

  Future<Transaction> buildTransaction(
    String recipientAddress,
    int amount,
    int feePerByte, {
    bool subtractFeeFromAmount = false,
    bool enableRbf = true,
    List<String>? selectedOutpoints,
  }) async {
    if (_hdWallet == null) {
      throw Exception('Wallet not initialized');
    }

    List<Utxo> availableUtxos;
    if (selectedOutpoints != null && selectedOutpoints.isNotEmpty) {
      availableUtxos = _utxos.where((u) => selectedOutpoints.contains(u.outpoint)).toList();
      if (availableUtxos.isEmpty) {
        throw Exception('Selected UTXOs not found');
      }
    } else {
      availableUtxos = _utxos.where((u) => u.isSpendable).toList();
      availableUtxos.sort((a, b) => b.value.compareTo(a.value));
    }

    if (availableUtxos.isEmpty) {
      throw Exception('No spendable UTXOs available');
    }

    var totalInput = 0;
    final selectedUtxos = <Utxo>[];

    if (subtractFeeFromAmount) {
      for (final utxo in availableUtxos) {
        selectedUtxos.add(utxo);
        totalInput += utxo.value;
      }
      
      final fee = estimateFee(selectedUtxos.length, 1, feePerByte);
      final sendAmount = totalInput - fee;
      
      if (sendAmount <= 546) {
        throw Exception('Amount after fee is below dust limit (546 sats)');
      }

      final sequence = enableRbf ? TransactionInput.rbfSequence : TransactionInput.finalSequence;
      final inputs = selectedUtxos.map((utxo) => TransactionInput(
        txid: utxo.txid,
        vout: utxo.vout,
        value: utxo.value,
        address: utxo.address,
        sequence: sequence,
      )).toList();

      final recipientScript = _addressToScript(recipientAddress);
      final outputs = <TransactionOutput>[
        TransactionOutput(value: sendAmount, scriptPubKey: recipientScript),
      ];

      return Transaction(
        version: 2,
        inputs: inputs,
        outputs: outputs,
        locktime: 0,
        hasWitness: true,
      );
    }

    if (selectedOutpoints != null && selectedOutpoints.isNotEmpty) {
      for (final utxo in availableUtxos) {
        selectedUtxos.add(utxo);
        totalInput += utxo.value;
      }
      
      final estimatedFee = estimateFee(selectedUtxos.length, 2, feePerByte);
      final targetAmount = amount + estimatedFee;

      if (totalInput < targetAmount) {
        throw Exception('Selected UTXOs insufficient: need $targetAmount sats, have $totalInput sats');
      }

      final sequence = enableRbf ? TransactionInput.rbfSequence : TransactionInput.finalSequence;
      final inputs = selectedUtxos.map((utxo) => TransactionInput(
        txid: utxo.txid,
        vout: utxo.vout,
        value: utxo.value,
        address: utxo.address,
        sequence: sequence,
      )).toList();

      final recipientScript = _addressToScript(recipientAddress);
      final outputs = <TransactionOutput>[
        TransactionOutput(value: amount, scriptPubKey: recipientScript),
      ];

      final change = totalInput - amount - estimatedFee;
      if (change > 546) {
        final changeNode = _hdWallet!.getChangeAddress(0, 0);
        final changeAddress = _deriveNativeSegWit(changeNode.publicKey);
        final changeScript = _addressToScript(changeAddress);
        outputs.add(TransactionOutput(value: change, scriptPubKey: changeScript));
      }

      return Transaction(
        version: 2,
        inputs: inputs,
        outputs: outputs,
        locktime: 0,
        hasWitness: true,
      );
    }

    var estimatedInputs = 1;
    var estimatedFee = estimateFee(estimatedInputs, 2, feePerByte);
    var targetAmount = amount + estimatedFee;

    for (final utxo in availableUtxos) {
      selectedUtxos.add(utxo);
      totalInput += utxo.value;

      estimatedFee = estimateFee(selectedUtxos.length, 2, feePerByte);
      targetAmount = amount + estimatedFee;

      if (totalInput >= targetAmount) {
        break;
      }
    }

    if (totalInput < targetAmount) {
      throw Exception('Insufficient funds: need $targetAmount sats, have $totalInput sats');
    }

    final sequence = enableRbf ? TransactionInput.rbfSequence : TransactionInput.finalSequence;
    final inputs = selectedUtxos.map((utxo) => TransactionInput(
      txid: utxo.txid,
      vout: utxo.vout,
      value: utxo.value,
      address: utxo.address,
      sequence: sequence,
    )).toList();

    final recipientScript = _addressToScript(recipientAddress);
    final outputs = <TransactionOutput>[
      TransactionOutput(value: amount, scriptPubKey: recipientScript),
    ];

    final change = totalInput - amount - estimatedFee;
    if (change > 546) {
      final changeNode = _hdWallet!.getChangeAddress(0, 0);
      final changeAddress = _deriveNativeSegWit(changeNode.publicKey);
      final changeScript = _addressToScript(changeAddress);
      outputs.add(TransactionOutput(value: change, scriptPubKey: changeScript));
    }

    return Transaction(
      version: 2,
      inputs: inputs,
      outputs: outputs,
      locktime: 0,
      hasWitness: true,
    );
  }

  Bip32Node? _findKeyForAddress(String address) {
    if (_hdWallet == null) return null;
    
    for (var i = 0; i < _maxReceiveAddresses; i++) {
      final node = _hdWallet!.getReceiveAddress(0, i);
      final derivedAddress = _deriveNativeSegWit(node.publicKey);
      if (derivedAddress == address) {
        return node;
      }
    }
    
    for (var i = 0; i < _maxChangeAddresses; i++) {
      final node = _hdWallet!.getChangeAddress(0, i);
      final derivedAddress = _deriveNativeSegWit(node.publicKey);
      if (derivedAddress == address) {
        return node;
      }
    }
    
    return null;
  }

  String? _findAddressForScript(String scriptHex) {
    if (_hdWallet == null) return null;
    
    for (var i = 0; i < _maxReceiveAddresses; i++) {
      final node = _hdWallet!.getReceiveAddress(0, i);
      final address = _deriveNativeSegWit(node.publicKey);
      final script = _bytesToHex(_addressToScript(address));
      if (script == scriptHex) {
        return address;
      }
    }
    
    for (var i = 0; i < _maxChangeAddresses; i++) {
      final node = _hdWallet!.getChangeAddress(0, i);
      final address = _deriveNativeSegWit(node.publicKey);
      final script = _bytesToHex(_addressToScript(address));
      if (script == scriptHex) {
        return address;
      }
    }
    
    return null;
  }

  Future<String> signAndBroadcastTransaction(Transaction tx) async {
    if (_hdWallet == null) {
      throw Exception('Wallet not initialized');
    }

    print('NeutrinoWallet: === SIGNING TRANSACTION ===');
    print('NeutrinoWallet: Inputs: ${tx.inputs.length}');
    for (var i = 0; i < tx.inputs.length; i++) {
      final input = tx.inputs[i];
      print('NeutrinoWallet: Input[$i]: ${input.txid}:${input.vout} value=${input.value} sats');
      
      final utxoExists = _utxos.any((u) => u.txid == input.txid && u.vout == input.vout);
      print('NeutrinoWallet: Input[$i] exists in local UTXO set: $utxoExists');
      if (utxoExists) {
        final utxo = _utxos.firstWhere((u) => u.txid == input.txid && u.vout == input.vout);
        print('NeutrinoWallet: Input[$i] UTXO: confirmed=${utxo.confirmed}, height=${utxo.blockHeight}, frozen=${utxo.frozen}');
      }
    }
    
    print('NeutrinoWallet: Outputs: ${tx.outputs.length}');
    int totalOut = 0;
    for (var i = 0; i < tx.outputs.length; i++) {
      final output = tx.outputs[i];
      print('NeutrinoWallet: Output[$i]: ${output.value} sats, script=${_bytesToHex(output.scriptPubKey)}');
      totalOut += output.value;
    }
    
    final totalIn = tx.inputs.fold<int>(0, (sum, i) => sum + i.value);
    final fee = totalIn - totalOut;
    print('NeutrinoWallet: Total in: $totalIn sats, Total out: $totalOut sats, Fee: $fee sats');
    
    if (fee < 0) {
      throw Exception('Invalid transaction: negative fee ($fee sats)');
    }
    if (fee > 1000000) {
      print('NeutrinoWallet: WARNING - Very high fee: $fee sats');
    }

    final spentOutpoints = <String>{};
    final signedInputs = <TransactionInput>[];
    
    for (var i = 0; i < tx.inputs.length; i++) {
      final input = tx.inputs[i];
      spentOutpoints.add('${input.txid}:${input.vout}');
      
      final address = input.address;
      if (address == null) {
        throw Exception('Input $i missing address');
      }
      
      final node = _findKeyForAddress(address);
      if (node == null) {
        throw Exception('Cannot find key for address: $address');
      }
      
      print('NeutrinoWallet: Signing input[$i] for address $address');
      print('NeutrinoWallet: Public key: ${_bytesToHex(node.publicKey)}');
      
      final sighash = _computeBip143Sighash(tx, i, node.publicKey, input.value);
      print('NeutrinoWallet: Sighash: ${_bytesToHex(sighash)}');
      
      final signature = SignatureHelper.signTransaction(sighash, node.privateKey);
      print('NeutrinoWallet: DER signature (${signature.length} bytes): ${_bytesToHex(signature)}');
      
      final signatureWithSighashType = Uint8List(signature.length + 1);
      signatureWithSighashType.setRange(0, signature.length, signature);
      signatureWithSighashType[signature.length] = 0x01;
      
      final verified = _verifySignature(sighash, signature, node.publicKey);
      print('NeutrinoWallet: Signature verification: $verified');
      if (!verified) {
        throw Exception('Signature verification failed for input $i');
      }

      signedInputs.add(input.copyWith(
        witness: [signatureWithSighashType, node.publicKey],
      ));
    }
    
    print('NeutrinoWallet: === SIGNING COMPLETE ===');

    final signedTx = Transaction(
      version: tx.version,
      inputs: signedInputs,
      outputs: tx.outputs,
      locktime: tx.locktime,
      hasWitness: true,
    );

    final rawTx = signedTx.serialize();
    
    final nonWitnessTx = _serializeNonWitness(signedTx);
    final hash1 = sha256.convert(nonWitnessTx);
    final hash2 = sha256.convert(hash1.bytes);
    final txid = _bytesToHex(Uint8List.fromList(hash2.bytes.reversed.toList()));
    
    await client.broadcastTransaction(rawTx);

    _utxos.removeWhere((utxo) => spentOutpoints.contains(utxo.outpoint));

    for (var i = 0; i < tx.outputs.length; i++) {
      final output = tx.outputs[i];
      final outputScript = _bytesToHex(output.scriptPubKey);
      final outputAddress = _findAddressForScript(outputScript);
      if (outputAddress != null) {
        _utxos.add(Utxo(
          txid: txid,
          vout: i,
          value: output.value,
          scriptPubKey: outputScript,
          address: outputAddress,
          blockHeight: null,
          confirmed: false,
        ));
        print('NeutrinoWallet: Added pending UTXO $txid:$i (${output.value} sats) to $outputAddress');
      }
    }

    await _persistWalletState();
    print('NeutrinoWallet: Broadcast $txid, removed ${spentOutpoints.length} spent UTXOs');
    return txid;
  }
  
  Uint8List _serializeNonWitness(Transaction tx) {
    final buffer = <int>[];
    _writeUint32(buffer, tx.version);
    _writeVarInt(buffer, tx.inputs.length);
    for (final input in tx.inputs) {
      final txidBytes = _hexToBytes(input.txid).reversed.toList();
      buffer.addAll(txidBytes);
      _writeUint32(buffer, input.vout);
      if (input.scriptSig != null) {
        _writeVarInt(buffer, input.scriptSig!.length);
        buffer.addAll(input.scriptSig!);
      } else {
        _writeVarInt(buffer, 0);
      }
      _writeUint32(buffer, input.sequence);
    }
    _writeVarInt(buffer, tx.outputs.length);
    for (final output in tx.outputs) {
      _writeUint64(buffer, output.value);
      _writeVarInt(buffer, output.scriptPubKey.length);
      buffer.addAll(output.scriptPubKey);
    }
    _writeUint32(buffer, tx.locktime);
    return Uint8List.fromList(buffer);
  }

  Uint8List _computeBip143Sighash(Transaction tx, int inputIndex, Uint8List publicKey, int inputValue) {
    final hashPrevouts = _computeHashPrevouts(tx);
    final hashSequence = _computeHashSequence(tx);
    final hashOutputs = _computeHashOutputs(tx);
    
    final input = tx.inputs[inputIndex];
    
    final scriptCode = _pubKeyToP2PKHScript(publicKey);
    
    final buffer = <int>[];
    
    _writeUint32(buffer, tx.version);
    
    buffer.addAll(hashPrevouts);
    
    buffer.addAll(hashSequence);
    
    final txidBytes = _hexToBytes(input.txid).reversed.toList();
    buffer.addAll(txidBytes);
    _writeUint32(buffer, input.vout);
    
    _writeVarInt(buffer, scriptCode.length);
    buffer.addAll(scriptCode);
    
    _writeUint64(buffer, inputValue);
    
    _writeUint32(buffer, input.sequence);
    
    buffer.addAll(hashOutputs);
    
    _writeUint32(buffer, tx.locktime);
    
    _writeUint32(buffer, 0x01);
    
    final hash1 = sha256.convert(buffer);
    final hash2 = sha256.convert(hash1.bytes);
    return Uint8List.fromList(hash2.bytes);
  }
  
  Uint8List _computeHashPrevouts(Transaction tx) {
    final buffer = <int>[];
    for (final input in tx.inputs) {
      final txidBytes = _hexToBytes(input.txid).reversed.toList();
      buffer.addAll(txidBytes);
      _writeUint32(buffer, input.vout);
    }
    final hash1 = sha256.convert(buffer);
    final hash2 = sha256.convert(hash1.bytes);
    return Uint8List.fromList(hash2.bytes);
  }
  
  Uint8List _computeHashSequence(Transaction tx) {
    final buffer = <int>[];
    for (final input in tx.inputs) {
      _writeUint32(buffer, input.sequence);
    }
    final hash1 = sha256.convert(buffer);
    final hash2 = sha256.convert(hash1.bytes);
    return Uint8List.fromList(hash2.bytes);
  }
  
  Uint8List _computeHashOutputs(Transaction tx) {
    final buffer = <int>[];
    for (final output in tx.outputs) {
      _writeUint64(buffer, output.value);
      _writeVarInt(buffer, output.scriptPubKey.length);
      buffer.addAll(output.scriptPubKey);
    }
    final hash1 = sha256.convert(buffer);
    final hash2 = sha256.convert(hash1.bytes);
    return Uint8List.fromList(hash2.bytes);
  }
  
  Uint8List _pubKeyToP2PKHScript(Uint8List publicKey) {
    final sha256Hash = sha256.convert(publicKey);
    final pubKeyHash = pc.RIPEMD160Digest().process(
      Uint8List.fromList(sha256Hash.bytes),
    );
    
    final script = <int>[];
    script.add(0x76);
    script.add(0xa9);
    script.add(0x14);
    script.addAll(pubKeyHash);
    script.add(0x88);
    script.add(0xac);
    
    return Uint8List.fromList(script);
  }


  Map<String, dynamic> _readVarInt(Uint8List data, int offset) {
    if (offset >= data.length) {
      return {'value': 0, 'offset': offset};
    }

    final first = data[offset];
    
    if (first < 0xfd) {
      return {'value': first, 'offset': offset + 1};
    } else if (first == 0xfd) {
      if (offset + 2 >= data.length) {
        return {'value': 0, 'offset': offset};
      }
      final value = data[offset + 1] | (data[offset + 2] << 8);
      return {'value': value, 'offset': offset + 3};
    } else if (first == 0xfe) {
      if (offset + 4 >= data.length) {
        return {'value': 0, 'offset': offset};
      }
      final value = _readUint32LE(data, offset + 1);
      return {'value': value, 'offset': offset + 5};
    } else {
      if (offset + 8 >= data.length) {
        return {'value': 0, 'offset': offset};
      }
      final value = _readUint64LE(data, offset + 1);
      return {'value': value, 'offset': offset + 9};
    }
  }

  static int _readUint32LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static int _readUint64LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24) |
        (data[offset + 4] << 32) |
        (data[offset + 5] << 40) |
        (data[offset + 6] << 48) |
        (data[offset + 7] << 56);
  }

  static void _writeUint32(List<int> buffer, int value) {
    buffer.add(value & 0xff);
    buffer.add((value >> 8) & 0xff);
    buffer.add((value >> 16) & 0xff);
    buffer.add((value >> 24) & 0xff);
  }

  static void _writeUint64(List<int> buffer, int value) {
    buffer.add(value & 0xff);
    buffer.add((value >> 8) & 0xff);
    buffer.add((value >> 16) & 0xff);
    buffer.add((value >> 24) & 0xff);
    buffer.add((value >> 32) & 0xff);
    buffer.add((value >> 40) & 0xff);
    buffer.add((value >> 48) & 0xff);
    buffer.add((value >> 56) & 0xff);
  }

  static void _writeVarInt(List<int> buffer, int value) {
    if (value < 0xfd) {
      buffer.add(value);
    } else if (value <= 0xffff) {
      buffer.add(0xfd);
      buffer.add(value & 0xff);
      buffer.add((value >> 8) & 0xff);
    } else if (value <= 0xffffffff) {
      buffer.add(0xfe);
      _writeUint32(buffer, value);
    } else {
      buffer.add(0xff);
      _writeUint64(buffer, value);
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  static bool _compareBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _verifySignature(Uint8List messageHash, Uint8List derSignature, Uint8List publicKey) {
    try {
      final decoded = _decodeDERSignature(derSignature);
      if (decoded == null) {
        print('NeutrinoWallet: Failed to decode DER signature');
        return false;
      }
      
      final r = decoded['r'] as BigInt;
      final s = decoded['s'] as BigInt;
      
      final domainParams = pc.ECDomainParameters('secp256k1');
      final pubKeyPoint = domainParams.curve.decodePoint(publicKey);
      if (pubKeyPoint == null) {
        print('NeutrinoWallet: Failed to decode public key point');
        return false;
      }
      
      final pubKey = pc.ECPublicKey(pubKeyPoint, domainParams);
      
      final signer = pc.ECDSASigner(null, pc.HMac(pc.SHA256Digest(), 64));
      signer.init(false, pc.PublicKeyParameter(pubKey));
      
      final signature = pc.ECSignature(r, s);
      return signer.verifySignature(messageHash, signature);
    } catch (e) {
      print('NeutrinoWallet: Signature verification error: $e');
      return false;
    }
  }
  
  Map<String, BigInt>? _decodeDERSignature(Uint8List der) {
    try {
      if (der.length < 8 || der[0] != 0x30) return null;
      
      var offset = 2;
      if (der[offset] != 0x02) return null;
      offset++;
      
      final rLen = der[offset];
      offset++;
      final rBytes = der.sublist(offset, offset + rLen);
      offset += rLen;
      
      if (der[offset] != 0x02) return null;
      offset++;
      
      final sLen = der[offset];
      offset++;
      final sBytes = der.sublist(offset, offset + sLen);
      
      BigInt bytesToBigInt(Uint8List bytes) {
        var result = BigInt.zero;
        for (var i = 0; i < bytes.length; i++) {
          result = (result << 8) | BigInt.from(bytes[i]);
        }
        return result;
      }
      
      return {
        'r': bytesToBigInt(Uint8List.fromList(rBytes)),
        's': bytesToBigInt(Uint8List.fromList(sBytes)),
      };
    } catch (e) {
      print('NeutrinoWallet: DER decode error: $e');
      return null;
    }
  }
}

