import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:io';
import '../theme/colors.dart';
import '../core/models/app_settings.dart';
import '../presentation/providers/neutrino_wallet_provider.dart';
import '../core/p2p/peer.dart';

class SettingsScreen extends StatefulWidget {
  final NeutrinoWalletProvider? walletProvider;
  
  const SettingsScreen({super.key, this.walletProvider});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nodeHostController = TextEditingController();
  final _nodePortController = TextEditingController();
  final _maxPeersController = TextEditingController();
  final _restoreHeightController = TextEditingController();
  final _addPeerHostController = TextEditingController();
  final _addPeerPortController = TextEditingController();
  
  AppSettings? _settings;
  bool _isLoading = true;
  bool _isTesting = false;
  String? _testResult;
  bool _peerDiscoveryEnabled = false;
  bool _isRescanning = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    widget.walletProvider?.addListener(_onProviderChanged);
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSettings() async {
    final settings = await AppSettings.load();
    setState(() {
      _settings = settings;
      _nodeHostController.text = settings.nodeHost;
      _nodePortController.text = settings.nodePort.toString();
      _peerDiscoveryEnabled = settings.peerDiscoveryEnabled;
      _maxPeersController.text = settings.maxPeerConnections.toString();
      _restoreHeightController.text = settings.restoreHeight > 0 ? settings.restoreHeight.toString() : '';
      _isLoading = false;
    });
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final host = _nodeHostController.text.trim();
      final port = int.parse(_nodePortController.text.trim());
      
      setState(() {
        _testResult = '⚠️ Connecting to P2P port...\n$host:$port';
      });

      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );
      
      socket.destroy();
      
      setState(() {
        _testResult = '✓ P2P port is reachable!\n\nHost: $host\nPort: $port\n\nThe wallet will establish a full Neutrino connection when you open it.';
        _isTesting = false;
      });
    } on SocketException catch (e) {
      setState(() {
        _testResult = '✗ Cannot connect to P2P port:\n\n${e.message}\n\nMake sure:\n• Node is running\n• P2P port ${_nodePortController.text} is open\n• Firewall allows connections\n• Host/IP is correct';
        _isTesting = false;
      });
    } catch (e) {
      setState(() {
        _testResult = '✗ Connection failed:\n$e';
        _isTesting = false;
      });
    }
  }

  Future<void> _showRescanConfirmation() async {
    if (widget.walletProvider == null) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkGrey,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text('Confirm Rescan', style: TextStyle(color: AppColors.gold)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to perform a full rescan?',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 12),
            Text(
              'This will scan all blocks from your restore height to find transactions. This process may take several minutes depending on your connection speed.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(context, true),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.purple,
              side: const BorderSide(color: AppColors.purple, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Rescan'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      setState(() => _isRescanning = true);
      try {
        await widget.walletProvider!.rescan();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Full rescan complete'),
              backgroundColor: AppColors.purple,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isRescanning = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final maxPeers = int.tryParse(_maxPeersController.text.trim()) ?? 1;
    final restoreHeight = int.tryParse(_restoreHeightController.text.trim()) ?? 0;

    final settings = AppSettings(
      nodeHost: _nodeHostController.text.trim(),
      nodePort: int.parse(_nodePortController.text.trim()),
      preferredAddressType: _settings!.preferredAddressType,
      peerDiscoveryEnabled: _peerDiscoveryEnabled,
      maxPeerConnections: maxPeers.clamp(1, 16),
      restoreHeight: restoreHeight.clamp(0, 999999999),
      bannedPeers: widget.walletProvider?.bannedPeers.toList() ?? _settings!.bannedPeers,
      favoritePeers: widget.walletProvider?.favoritePeers.toList() ?? _settings!.favoritePeers,
    );

    await settings.save();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: AppColors.purple,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  void _showAddPeerDialog() {
    _addPeerHostController.clear();
    _addPeerPortController.text = '42069';
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkGrey,
        title: const Text('Add Peer', style: TextStyle(color: AppColors.gold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _addPeerHostController,
              decoration: InputDecoration(
                labelText: 'Host/IP',
                labelStyle: const TextStyle(color: AppColors.goldLight),
                hintText: '192.168.1.100',
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.goldDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.gold, width: 2),
                ),
              ),
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addPeerPortController,
              decoration: InputDecoration(
                labelText: 'Port',
                labelStyle: const TextStyle(color: AppColors.goldLight),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.goldDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.gold, width: 2),
                ),
              ),
              style: const TextStyle(color: Colors.white),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          OutlinedButton(
            onPressed: () async {
              final host = _addPeerHostController.text.trim();
              final port = int.tryParse(_addPeerPortController.text.trim()) ?? 42069;
              if (host.isNotEmpty && widget.walletProvider != null) {
                Navigator.pop(context);
                await widget.walletProvider!.connectToPeer(host, port);
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.purple,
              side: const BorderSide(color: AppColors.purple, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _showPeerActions(PeerInfo peer) {
    final isFavorite = widget.walletProvider?.isPeerFavorite(peer.id) ?? false;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              peer.id,
              style: const TextStyle(
                color: AppColors.gold,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (peer.pingTimeMs != null)
              Text(
                'Ping: ${peer.pingTimeMs}ms',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(
                isFavorite ? Icons.star : Icons.star_border,
                color: isFavorite ? Colors.amber : Colors.white54,
              ),
              title: Text(
                isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () {
                Navigator.pop(context);
                if (isFavorite) {
                  widget.walletProvider?.removeFavoritePeer(peer.id);
                } else {
                  widget.walletProvider?.addFavoritePeer(peer.id);
                }
              },
            ),
            if (!peer.isSeed) ...[
              ListTile(
                leading: const Icon(Icons.close, color: Colors.orange),
                title: const Text('Disconnect', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  widget.walletProvider?.disconnectPeer(peer.id);
                },
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: const Text('Ban Peer', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Prevents future connections', style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  widget.walletProvider?.banPeer(peer.id);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showBannedPeersDialog() {
    final bannedPeers = widget.walletProvider?.bannedPeers.toList() ?? _settings?.bannedPeers ?? [];
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkGrey,
        title: const Text('Banned Peers', style: TextStyle(color: AppColors.gold)),
        content: SizedBox(
          width: double.maxFinite,
          child: bannedPeers.isEmpty
              ? const Text('No banned peers', style: TextStyle(color: Colors.white54))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: bannedPeers.length,
                  itemBuilder: (context, index) {
                    final peerId = bannedPeers[index];
                    return ListTile(
                      title: Text(peerId, style: const TextStyle(color: Colors.white, fontSize: 14)),
                      trailing: IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.green),
                        onPressed: () {
                          widget.walletProvider?.unbanPeer(peerId);
                          Navigator.pop(context);
                          _showBannedPeersDialog();
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: AppColors.gold)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.walletProvider?.removeListener(_onProviderChanged);
    _nodeHostController.dispose();
    _nodePortController.dispose();
    _maxPeersController.dispose();
    _restoreHeightController.dispose();
    _addPeerHostController.dispose();
    _addPeerPortController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Settings', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.black,
          iconTheme: const IconThemeData(color: AppColors.gold),
        ),
        body: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppColors.purple))),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.black,
        iconTheme: const IconThemeData(color: AppColors.gold),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: IconButton(icon: const Icon(Icons.save), onPressed: _saveSettings),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildNodeConfigCard(),
              const SizedBox(height: 16),
              if (_peerDiscoveryEnabled && widget.walletProvider != null) ...[
                _buildPeerManagementCard(),
                const SizedBox(height: 16),
              ],
              _buildWalletActionsCard(),
              const SizedBox(height: 16),
              _buildRestoreCard(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNodeConfigCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.cloud, color: AppColors.gold),
                  ),
                  const SizedBox(width: 12),
                  const Text('Node Configuration', style: TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: const Text('✅ Full Neutrino Implementation', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 12),
              const Text(
                'This wallet uses the Bitcoin P2P protocol with BIP157/158 compact filters. Use your node\'s P2P port (default: 42069).\n\n✓ Privacy-preserving UTXO discovery\n✓ Compact block filters\n✓ No RPC needed',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _nodeHostController,
                      decoration: InputDecoration(
                        labelText: 'Node Host/IP',
                        labelStyle: const TextStyle(color: AppColors.goldLight),
                        hintText: 'localhost or 192.168.1.x',
                        prefixIcon: const Icon(Icons.dns, color: AppColors.goldLight),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.goldDark.withOpacity(0.5))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 2)),
                        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
                        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 2)),
                        filled: true,
                        fillColor: AppColors.black.withOpacity(0.3),
                      ),
                      style: const TextStyle(color: Colors.white),
                      validator: (value) => (value == null || value.isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      controller: _nodePortController,
                      decoration: InputDecoration(
                        labelText: 'P2P Port',
                        labelStyle: const TextStyle(color: AppColors.goldLight),
                        hintText: '42069',
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.goldDark.withOpacity(0.5))),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 2)),
                        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
                        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red, width: 2)),
                        filled: true,
                        fillColor: AppColors.black.withOpacity(0.3),
                      ),
                      style: const TextStyle(color: Colors.white),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Required';
                        final port = int.tryParse(value);
                        if (port == null || port < 1 || port > 65535) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(color: AppColors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: SwitchListTile(
                  value: _peerDiscoveryEnabled,
                  title: const Text('Peer Discovery', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Allow the wallet to find and maintain up to 8 peers', style: TextStyle(color: Colors.white60, fontSize: 12)),
                  activeColor: AppColors.gold,
                  onChanged: (value) => setState(() => _peerDiscoveryEnabled = value),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _maxPeersController,
                enabled: _peerDiscoveryEnabled,
                decoration: InputDecoration(
                  labelText: 'Max Peer Connections',
                  labelStyle: const TextStyle(color: AppColors.goldLight),
                  prefixIcon: const Icon(Icons.hub, color: AppColors.goldLight),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.goldDark.withOpacity(0.5))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 2)),
                  disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.withOpacity(0.3))),
                  filled: true,
                  fillColor: AppColors.black.withOpacity(0.3),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (!_peerDiscoveryEnabled) return null;
                  if (value == null || value.isEmpty) return 'Required';
                  final maxPeers = int.tryParse(value);
                  if (maxPeers == null || maxPeers < 1 || maxPeers > 16) return '1-16';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: OutlinedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.purple)))
                      : const Icon(Icons.wifi_find, size: 18),
                  label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.purple,
                    side: BorderSide(color: _isTesting ? AppColors.purple.withOpacity(0.4) : AppColors.purple, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (_testResult!.startsWith('✓') ? Colors.green : Colors.red).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: (_testResult!.startsWith('✓') ? Colors.green : Colors.red).withOpacity(0.5)),
                  ),
                  child: Text(_testResult!, style: TextStyle(color: _testResult!.startsWith('✓') ? Colors.green : Colors.red, fontFamily: 'monospace', fontSize: 12)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeerManagementCard() {
    final peers = widget.walletProvider?.peerInfoList ?? [];
    final bannedCount = widget.walletProvider?.bannedPeers.length ?? 0;
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.hub, color: AppColors.gold),
                    SizedBox(width: 8),
                    Text(
                      'Connected Peers',
                      style: TextStyle(
                        color: AppColors.gold,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    if (bannedCount > 0)
                      TextButton.icon(
                        onPressed: _showBannedPeersDialog,
                        icon: const Icon(Icons.block, color: Colors.red, size: 18),
                        label: Text('$bannedCount banned', style: const TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, color: AppColors.gold),
                      onPressed: _showAddPeerDialog,
                      tooltip: 'Add Peer',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap a peer to manage. Favorites are prioritized after your main node.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (peers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(
                  child: Text(
                    'No peers connected',
                    style: TextStyle(color: Colors.white54),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: peers.length,
                itemBuilder: (context, index) {
                  final peer = peers[index];
                  final isFavorite = widget.walletProvider?.isPeerFavorite(peer.id) ?? false;
                  
                  return Card(
                    color: AppColors.black,
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      onTap: () => _showPeerActions(peer),
                      leading: Stack(
                        children: [
                          Icon(
                            peer.isSeed ? Icons.cloud : Icons.computer,
                            color: peer.isConnected ? Colors.green : Colors.orange,
                          ),
                          if (isFavorite)
                            const Positioned(
                              right: -2,
                              top: -2,
                              child: Icon(Icons.star, color: Colors.amber, size: 12),
                            ),
                        ],
                      ),
                      title: Text(
                        peer.id,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontFamily: 'monospace',
                        ),
                      ),
                      subtitle: Row(
                        children: [
                          if (peer.isSeed)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'MAIN',
                                style: TextStyle(color: AppColors.gold, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          if (peer.supportsCompactFilters)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'BIP157',
                                style: TextStyle(color: Colors.green, fontSize: 10),
                              ),
                            ),
                          if (peer.pingTimeMs != null)
                            Text(
                              '${peer.pingTimeMs}ms',
                              style: TextStyle(
                                color: peer.pingTimeMs! < 100 ? Colors.green : 
                                       peer.pingTimeMs! < 500 ? Colors.orange : Colors.red,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                      trailing: Icon(
                        Icons.chevron_right,
                        color: Colors.white38,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletActionsCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.sync, color: AppColors.gold),
                  ),
                  const SizedBox(width: 12),
                  const Text('Wallet Actions', style: TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Perform a full rescan to find all transactions from your restore height. This is useful if you think some transactions are missing.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: OutlinedButton.icon(
                  onPressed: (widget.walletProvider == null || _isRescanning) ? null : _showRescanConfirmation,
                  icon: _isRescanning
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.orange)))
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(_isRescanning ? 'Rescanning...' : 'Full Rescan'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: BorderSide(color: _isRescanning ? Colors.orange.withOpacity(0.4) : Colors.orange, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (widget.walletProvider == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Open a wallet to enable rescan', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRestoreCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.restore, color: AppColors.gold),
                  ),
                  const SizedBox(width: 12),
                  const Text('Wallet Restore', style: TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Set a restore height to skip scanning old blocks when recovering a wallet. Use the block height from when your wallet was created.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _restoreHeightController,
                decoration: InputDecoration(
                  labelText: 'Restore Height (optional)',
                  labelStyle: const TextStyle(color: AppColors.goldLight),
                  hintText: '0 = scan from genesis',
                  hintStyle: const TextStyle(color: Colors.white30),
                  prefixIcon: const Icon(Icons.height, color: AppColors.goldLight),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.goldDark.withOpacity(0.5))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 2)),
                  filled: true,
                  fillColor: AppColors.black.withOpacity(0.3),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
