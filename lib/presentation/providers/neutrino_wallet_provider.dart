import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../data/repositories/neutrino_wallet_repository.dart';
import '../../core/neutrino/neutrino_client.dart';
import '../../core/chain/chain_params.dart';
import '../../core/models/app_settings.dart';
import '../../core/models/utxo.dart';
import '../../core/storage/address_book_storage.dart';
import '../../core/p2p/peer.dart';

class NeutrinoWalletProvider extends ChangeNotifier {
  final String walletId;
  late final NeutrinoWalletRepository _repository;
  late final NeutrinoClient _client;
  final AddressBookStorage _addressStorage = AddressBookStorage();
  
  bool _isInitialized = false;
  bool _isSyncing = false;
  bool _isConnected = false;
  bool _isDiscoveringUtxos = false;
  bool _disposed = false;
  String? _error;
  String? _nodeHost;
  int? _nodePort;
  int _restoreHeight = 0;
  String _scanStatus = '';
  int _filterScanProgress = 0;
  int _filterScanTotal = 0;

  NeutrinoWalletProvider({
    required this.walletId,
    required String nodeHost,
    required int nodePort,
    bool enablePeerDiscovery = false,
    int maxPeerConnections = 1,
    int restoreHeight = 0,
    ChainParams? chainParams,
    List<String>? bannedPeers,
    List<String>? favoritePeers,
  })  : _nodeHost = nodeHost,
        _nodePort = nodePort,
        _restoreHeight = restoreHeight {
    final params = chainParams ?? ShaicoinMainnetParams();
    _client = NeutrinoClient(
      nodeHost: nodeHost,
      nodeP2PPort: nodePort,
      chainParams: params,
      enablePeerDiscovery: enablePeerDiscovery,
      maxPeerConnections: maxPeerConnections,
    );
    _client.onStateChanged = _onClientStateChanged;
    _client.onReorg = _handleReorg;
    _client.onNewBlock = _handleNewBlock;
    _client.onPeerListChanged = _onPeerListChanged;
    if (bannedPeers != null) _client.setBannedPeers(bannedPeers);
    if (favoritePeers != null) _client.setFavoritePeers(favoritePeers);
    _repository = NeutrinoWalletRepository(
      client: _client,
      chainParams: params,
      walletId: walletId,
      addressStorage: _addressStorage,
    );
    _repository.onScanProgress = _onScanProgress;
  }

  void _onPeerListChanged() {
    if (_disposed) return;
    notifyListeners();
  }
  
  void _onScanProgress(int scanned, int total, String status) {
    if (_disposed) return;
    _filterScanProgress = scanned;
    _filterScanTotal = total;
    _scanStatus = status;
    notifyListeners();
  }

  void _safeNotifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _onClientStateChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  void _handleReorg(int oldHeight, int newHeight, int commonAncestor) {
    if (_disposed) return;
    debugPrint('NeutrinoProvider: Reorg detected - old=$oldHeight, new=$newHeight, ancestor=$commonAncestor');
    _repository.handleReorg(commonAncestor);
    notifyListeners();
  }

  void _handleNewBlock(int height) {
    if (_disposed || _isSyncing) return;
    debugPrint('NeutrinoProvider: New block at height $height');
    _repository.checkBlockForTransactions(height).then((_) {
      if (_disposed) return;
      debugPrint('NeutrinoProvider: Checked block $height for transactions');
      notifyListeners();
    });
  }

  bool get isInitialized => _isInitialized;
  bool get isSyncing => _isSyncing || _client.isSyncing || _isDiscoveringUtxos;
  bool get isScanning => _isDiscoveringUtxos;
  bool get isConnected => _isConnected || _client.isConnected;
  String? get error => _error ?? _client.syncError;
  String? get nodeHost => _nodeHost;
  int? get nodePort => _nodePort;
  int get balance => _repository.getBalance();
  int get unconfirmedBalance => _repository.getUnconfirmedBalance();
  int get blockHeight => _client.blockHeight;
  int get targetHeight => _client.targetHeight;
  int get cachedHeaderCount => _client.cachedHeaderCount;
  double get syncProgress => _client.syncProgress;
  int get scanProgress => _filterScanProgress;
  int get scanTotal => _filterScanTotal;
  double get scanProgressPercent => _filterScanTotal > 0 ? _filterScanProgress / _filterScanTotal : 0.0;
  List<Utxo> get utxos => _repository.getUtxos();
  List<Utxo> get spendableUtxos => _repository.getSpendableUtxos();
  int get minFeeRate => _client.minFeeRateSatPerByte;

  void freezeUtxo(String outpoint) {
    _repository.freezeUtxo(outpoint);
    notifyListeners();
  }

  void unfreezeUtxo(String outpoint) {
    _repository.unfreezeUtxo(outpoint);
    notifyListeners();
  }

  void setUtxoFrozen(String outpoint, bool frozen) {
    _repository.setUtxoFrozen(outpoint, frozen);
    notifyListeners();
  }

  List<PeerInfo> get peerInfoList => _client.peerInfoList;
  Set<String> get bannedPeers => _client.bannedPeers;
  Set<String> get favoritePeers => _client.favoritePeers;

  void banPeer(String peerId) {
    _client.banPeer(peerId);
    notifyListeners();
  }

  void unbanPeer(String peerId) {
    _client.unbanPeer(peerId);
    notifyListeners();
  }

  void addFavoritePeer(String peerId) {
    _client.addFavoritePeer(peerId);
    notifyListeners();
  }

  void removeFavoritePeer(String peerId) {
    _client.removeFavoritePeer(peerId);
    notifyListeners();
  }

  void disconnectPeer(String peerId) {
    _client.disconnectPeer(peerId);
    notifyListeners();
  }

  Future<void> connectToPeer(String host, int port) async {
    await _client.connectToPeer(host, port);
    notifyListeners();
  }

  bool isPeerBanned(String peerId) => _client.bannedPeers.contains(peerId);
  bool isPeerFavorite(String peerId) => _client.favoritePeers.contains(peerId);

  String get syncStatus {
    if (_isSyncing || _client.isSyncing) return 'Syncing headers...';
    if (_isDiscoveringUtxos) {
      if (_scanStatus.isNotEmpty) return _scanStatus;
      if (_filterScanTotal > 0) {
        final pct = ((_filterScanProgress / _filterScanTotal) * 100).toInt();
        return 'Scanning: $pct%';
      }
      return 'Scanning wallet...';
    }
    if (!_isInitialized) return 'Initializing...';
    if (!isConnected) return 'Connecting...';
    if (_client.blockHeight == 0) return 'Waiting for blocks...';
    return 'Synced';
  }

  String get balanceFormatted {
    final sha = balance / 100000000;
    return sha.toStringAsFixed(8);
  }

  Future<void> initializeWallet(Uint8List seed) async {
    _error = null;
    _isSyncing = true;
    
    try {
      await _client.loadCachedState();
      await _repository.loadLocalState(seed);
      _isInitialized = true;
      
      if (_repository.getAddressCount(AddressType.nativeSegwit) == 0) {
        await _repository.getNewReceiveAddress(addressType: AddressType.nativeSegwit);
      }
      
      notifyListeners();
      
      _connectAndSync();
    } catch (e) {
      _error = e.toString();
      _isSyncing = false;
      notifyListeners();
    }
  }

  void _connectAndSync() async {
    debugPrint('NeutrinoProvider: _connectAndSync starting');
    try {
      if (!_client.isConnected) {
        debugPrint('NeutrinoProvider: Connecting to node...');
        await _client.connect();
      }
      _isConnected = true;
      debugPrint('NeutrinoProvider: Connected, starting sync');
      notifyListeners();
      
      await _client.syncToTip();
      debugPrint('NeutrinoProvider: syncToTip completed successfully');
      _isSyncing = false;
      notifyListeners();
      
      _discoverUtxosInBackground();
    } catch (e, stack) {
      debugPrint('NeutrinoProvider: _connectAndSync failed - $e');
      debugPrint('NeutrinoProvider: Stack: $stack');
      debugPrint('NeutrinoProvider: Client state - isSyncing=${_client.isSyncing}, phase=${_client.syncPhase}, connected=${_client.isConnected}');
      _error = e.toString();
      _isSyncing = false;
      _isConnected = false;
      notifyListeners();
    }
  }

  void _discoverUtxosInBackground() {
    _isDiscoveringUtxos = true;
    notifyListeners();
    
    Future(() async {
      try {
        final startHeight = _determineScanStartHeight();
        debugPrint('NeutrinoProvider: Starting UTXO discovery from height $startHeight');
        await _repository.discoverUtxos(startHeight: startHeight);
        await _repository.finalizeDiscovery();
      } catch (e) {
        debugPrint('NeutrinoProvider: UTXO discovery failed - $e');
      } finally {
        _isDiscoveringUtxos = false;
        notifyListeners();
      }
    });
  }

  Future<void> refreshBalance() async {
    if (!_isInitialized) return;
    if (_isDiscoveringUtxos) return;
    
    _isDiscoveringUtxos = true;
    _error = null;
    notifyListeners();

    try {
      await _client.syncToTip();
      final startHeight = _determineScanStartHeight();
      await _repository.discoverUtxos(startHeight: startHeight);
      _isConnected = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isDiscoveringUtxos = false;
      notifyListeners();
    }
  }

  Future<void> rescan() async {
    if (!_isInitialized) return;
    if (_isDiscoveringUtxos) return;
    
    _isDiscoveringUtxos = true;
    _error = null;
    notifyListeners();

    try {
      await _client.syncToTip();
      int startHeight;
      if (_restoreHeight > 0 && _restoreHeight < _client.blockHeight) {
        startHeight = _restoreHeight;
      } else {
        startHeight = 0;
      }
      debugPrint('NeutrinoProvider: Full rescan from height $startHeight (restoreHeight=$_restoreHeight, tip=${_client.blockHeight})');
      await _repository.discoverUtxos(fullRescan: true, startHeight: startHeight);
      _isConnected = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isDiscoveringUtxos = false;
      notifyListeners();
    }
  }

  int _determineScanStartHeight() {
    final tip = _client.blockHeight;
    if (tip <= 0) {
      return 0;
    }
    
    if (_restoreHeight > 0 && _restoreHeight < tip) {
      return _restoreHeight;
    }
    
    final candidate = tip - 1000;
    return candidate > 0 ? candidate : 0;
  }

  Future<String> getNewReceiveAddress({AddressType addressType = AddressType.nativeSegwit}) async {
    if (!_isInitialized) {
      throw Exception('Wallet not initialized');
    }
    final address = await _repository.getNewReceiveAddress(addressType: addressType);
    debugPrint('NeutrinoProvider: Generated new address: $address');
    notifyListeners();
    return address;
  }

  List<String> getCurrentAddresses(int count, AddressType addressType) {
    if (!_isInitialized) {
      return [];
    }
    return _repository.getCurrentAddresses(count, addressType);
  }

  List<String> getAllAddresses(AddressType addressType) {
    if (!_isInitialized) {
      return [];
    }
    return _repository.getAllAddresses(addressType);
  }

  int getAddressCount(AddressType addressType) {
    if (!_isInitialized) {
      return 0;
    }
    return _repository.getAddressCount(addressType);
  }

  List<String> getAddressesInRange(AddressType addressType, int start, int end) {
    if (!_isInitialized) {
      return [];
    }
    return _repository.getAddressesInRange(addressType, start, end);
  }

  Future<Map<String, dynamic>> calculateMaxSendAmount(int feePerByte, {List<String>? selectedOutpoints}) async {
    if (!_isInitialized) {
      throw Exception('Wallet not initialized');
    }
    return _repository.calculateMaxSendAmount(feePerByte, selectedOutpoints: selectedOutpoints);
  }

  int estimateFee(int inputCount, int outputCount, int feePerByte) {
    return _repository.estimateFee(inputCount, outputCount, feePerByte);
  }

  Future<String> sendTransaction({
    required String recipientAddress,
    required int amount,
    int feePerByte = 1,
    bool subtractFeeFromAmount = false,
    bool enableRbf = true,
    List<String>? selectedOutpoints,
  }) async {
    if (!_isInitialized) {
      throw Exception('Wallet not initialized');
    }

    try {
      debugPrint('NeutrinoProvider: Building transaction to $recipientAddress for $amount sats (sweep: $subtractFeeFromAmount, rbf: $enableRbf, utxos: ${selectedOutpoints?.length ?? "auto"})');
      
      final tx = await _repository.buildTransaction(
        recipientAddress,
        amount,
        feePerByte,
        subtractFeeFromAmount: subtractFeeFromAmount,
        enableRbf: enableRbf,
        selectedOutpoints: selectedOutpoints,
      );

      debugPrint('NeutrinoProvider: Signing and broadcasting transaction');
      
      final txid = await _repository.signAndBroadcastTransaction(tx);
      
      debugPrint('NeutrinoProvider: Transaction broadcast - $txid');
      
      _safeNotifyListeners();
      
      return txid;
    } catch (e) {
      debugPrint('NeutrinoProvider: Send failed - $e');
      _error = e.toString();
      _safeNotifyListeners();
      rethrow;
    }
  }

  Future<void> resetWallet() async {
    _isInitialized = false;
    _isSyncing = false;
    _isConnected = false;
    _error = null;
    _safeNotifyListeners();
    
    await _client.resetWallet();
    await _repository.clearLocalState();
    
    debugPrint('NeutrinoProvider: Wallet reset complete');
    _safeNotifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _client.onStateChanged = null;
    _client.onReorg = null;
    _client.onNewBlock = null;
    _client.onPeerListChanged = null;
    _repository.onScanProgress = null;
    _client.disconnect();
    super.dispose();
  }
}


