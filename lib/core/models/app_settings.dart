import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum AddressType {
  nativeSegwit,
  taproot,
  legacy,
  p2shSegwit,
}

class AppSettings {
  String nodeHost;
  int nodePort;
  AddressType preferredAddressType;
  bool peerDiscoveryEnabled;
  int maxPeerConnections;
  int restoreHeight;
  List<String> bannedPeers;
  List<String> favoritePeers;

  AppSettings({
    this.nodeHost = 'localhost',
    this.nodePort = 42069,
    this.preferredAddressType = AddressType.nativeSegwit,
    this.peerDiscoveryEnabled = false,
    this.maxPeerConnections = 8,
    this.restoreHeight = 0,
    List<String>? bannedPeers,
    List<String>? favoritePeers,
  }) : bannedPeers = bannedPeers ?? [],
       favoritePeers = favoritePeers ?? [];

  String get nodeP2PUrl => '$nodeHost:$nodePort';
  String get nodeUrl => '$nodeHost:$nodePort';

  static const _keyNodeHost = 'node_host';
  static const _keyNodePort = 'node_port';
  static const _keyAddressType = 'address_type';
  static const _keyPeerDiscovery = 'peer_discovery';
  static const _keyMaxPeers = 'max_peer_connections';
  static const _keyRestoreHeight = 'restore_height';
  static const _keyBannedPeers = 'banned_peers';
  static const _keyFavoritePeers = 'favorite_peers';

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    
    List<String> bannedPeers = [];
    List<String> favoritePeers = [];
    
    final bannedJson = prefs.getString(_keyBannedPeers);
    if (bannedJson != null) {
      bannedPeers = List<String>.from(jsonDecode(bannedJson));
    }
    
    final favoritesJson = prefs.getString(_keyFavoritePeers);
    if (favoritesJson != null) {
      favoritePeers = List<String>.from(jsonDecode(favoritesJson));
    }
    
    var addressType = AddressType.values[prefs.getInt(_keyAddressType) ?? 0];
    if (addressType == AddressType.taproot) {
      addressType = AddressType.nativeSegwit;
    }
    
    return AppSettings(
      nodeHost: prefs.getString(_keyNodeHost) ?? 'localhost',
      nodePort: prefs.getInt(_keyNodePort) ?? 42069,
      preferredAddressType: addressType,
      peerDiscoveryEnabled: prefs.getBool(_keyPeerDiscovery) ?? false,
      maxPeerConnections: prefs.getInt(_keyMaxPeers) ?? 8,
      restoreHeight: prefs.getInt(_keyRestoreHeight) ?? 0,
      bannedPeers: bannedPeers,
      favoritePeers: favoritePeers,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNodeHost, nodeHost);
    await prefs.setInt(_keyNodePort, nodePort);
    await prefs.setInt(_keyAddressType, preferredAddressType.index);
    await prefs.setBool(_keyPeerDiscovery, peerDiscoveryEnabled);
    await prefs.setInt(_keyMaxPeers, maxPeerConnections);
    await prefs.setInt(_keyRestoreHeight, restoreHeight);
    await prefs.setString(_keyBannedPeers, jsonEncode(bannedPeers));
    await prefs.setString(_keyFavoritePeers, jsonEncode(favoritePeers));
  }

  void addBannedPeer(String peerId) {
    if (!bannedPeers.contains(peerId)) {
      bannedPeers.add(peerId);
    }
  }

  void removeBannedPeer(String peerId) {
    bannedPeers.remove(peerId);
  }

  void addFavoritePeer(String peerId) {
    if (!favoritePeers.contains(peerId)) {
      favoritePeers.add(peerId);
    }
  }

  void removeFavoritePeer(String peerId) {
    favoritePeers.remove(peerId);
  }

  bool isPeerBanned(String peerId) => bannedPeers.contains(peerId);
  bool isPeerFavorite(String peerId) => favoritePeers.contains(peerId);

  String get addressTypeName {
    switch (preferredAddressType) {
      case AddressType.nativeSegwit:
        return 'Native SegWit (P2WPKH)';
      case AddressType.taproot:
        return 'Taproot (P2TR)';
      case AddressType.legacy:
        return 'Legacy (P2PKH)';
      case AddressType.p2shSegwit:
        return 'P2SH-SegWit';
    }
  }
}

