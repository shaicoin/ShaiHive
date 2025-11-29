import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:typed_data';
import '../theme/colors.dart';
import '../core/models/app_settings.dart';
import '../presentation/providers/neutrino_wallet_provider.dart';
import 'receive_screen_enhanced.dart';
import 'send_screen.dart';
import 'credentials_screen.dart';
import 'settings_screen.dart';
import 'transaction_detail_screen.dart';

class WalletDetailScreenEnhanced extends StatefulWidget {
  final Map<String, dynamic> wallet;

  const WalletDetailScreenEnhanced({super.key, required this.wallet});

  @override
  State<WalletDetailScreenEnhanced> createState() => _WalletDetailScreenEnhancedState();
}

class _WalletDetailScreenEnhancedState extends State<WalletDetailScreenEnhanced> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  NeutrinoWalletProvider? _walletProvider;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeWallet();
  }

  Future<void> _initializeWallet() async {
    try {
      final settings = await AppSettings.load();
      
      print('Initializing Neutrino wallet with P2P node: ${settings.nodeHost}:${settings.nodePort}');
      
      final seedBase64 = widget.wallet['seed'] as String?;
      if (seedBase64 == null) {
        throw Exception('Wallet seed not found');
      }
      
      final seedBytes = Uint8List.fromList(base64.decode(seedBase64));
      final walletId = sha256.convert(seedBytes).toString();
      
      final walletProvider = NeutrinoWalletProvider(
        walletId: walletId,
        nodeHost: settings.nodeHost,
        nodePort: settings.nodePort,
        enablePeerDiscovery: settings.peerDiscoveryEnabled,
        maxPeerConnections: settings.maxPeerConnections,
        restoreHeight: settings.restoreHeight,
        bannedPeers: settings.bannedPeers,
        favoritePeers: settings.favoritePeers,
      );

      setState(() {
        _walletProvider = walletProvider;
        _isInitializing = false;
      });
      
      walletProvider.initializeWallet(seedBytes);
    } catch (e) {
      print('Failed to initialize Neutrino wallet: $e');
      setState(() {
        _walletProvider?.dispose();
        _walletProvider = null;
        _isInitializing = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect to P2P node: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _walletProvider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.wallet['name'] ?? 'Wallet',
          style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.gold),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppColors.gold.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SettingsScreen(walletProvider: _walletProvider)),
                );
                if (result == true) {
                  setState(() {
                    _isInitializing = true;
                    _walletProvider?.dispose();
                    _walletProvider = null;
                  });
                  _initializeWallet();
                }
              },
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.gold,
          indicatorWeight: 3,
          labelColor: AppColors.gold,
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(text: 'Wallet'),
            Tab(text: 'Credentials'),
          ],
        ),
      ),
      body: _isInitializing
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.purple),
              ),
            )
          : _walletProvider == null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'Failed to connect to P2P node',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Make sure your node is running on ${_walletProvider?.nodeHost ?? 'localhost'}:${_walletProvider?.nodePort ?? 7743}',
                        style: const TextStyle(color: Colors.white54, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _isInitializing = true;
                          });
                          _initializeWallet();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.purple,
                          side: const BorderSide(color: AppColors.purple, width: 1.5),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ChangeNotifierProvider.value(
                  value: _walletProvider,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildWalletTab(),
                      CredentialsScreen(wallet: widget.wallet),
                    ],
                  ),
                ),
    );
  }

  Widget _buildWalletTab() {
    return Consumer<NeutrinoWalletProvider>(
      builder: (context, walletProvider, child) {
        final syncPercentValue = (walletProvider.syncProgress * 100).clamp(0.0, 100.0);
        final syncPercentLabel = syncPercentValue.toStringAsFixed(1);
        final cachedHeaderAmount = walletProvider.cachedHeaderCount;
        final syncTargetLabel = walletProvider.targetHeight == 0
            ? cachedHeaderAmount.toString()
            : walletProvider.targetHeight.toString();
        final utxos = walletProvider.utxos;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppColors.glassWhite,
                              AppColors.purple.withOpacity(0.08),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Balance', style: TextStyle(color: Colors.white70, fontSize: 16)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (walletProvider.isSyncing
                                            ? Colors.orange
                                            : walletProvider.isConnected
                                                ? Colors.green
                                                : Colors.red)
                                        .withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: walletProvider.isSyncing
                                              ? Colors.orange
                                              : walletProvider.isConnected
                                                  ? Colors.green
                                                  : Colors.red,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        walletProvider.syncStatus,
                                        style: TextStyle(
                                          color: walletProvider.isSyncing
                                              ? Colors.orange
                                              : walletProvider.isConnected
                                                  ? Colors.green
                                                  : Colors.red,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Image.asset('assets/images/logo.png', height: 28, color: AppColors.gold),
                                const SizedBox(width: 10),
                                Text(
                                  '${walletProvider.balanceFormatted} SHA',
                                  style: const TextStyle(color: AppColors.gold, fontSize: 28, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Block ${walletProvider.blockHeight}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                if (walletProvider.isSyncing && walletProvider.syncProgress < 1.0)
                                  Text('$syncPercentLabel%', style: const TextStyle(color: AppColors.purple, fontSize: 11)),
                              ],
                            ),
                            if (walletProvider.isSyncing && walletProvider.syncProgress < 1.0) ...[
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: walletProvider.syncProgress == 0 ? null : walletProvider.syncProgress.clamp(0.0, 1.0),
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.purple),
                                  backgroundColor: AppColors.black.withOpacity(0.5),
                                  minHeight: 4,
                                ),
                              ),
                            ],
                            if (walletProvider.isScanning) ...[
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: walletProvider.scanTotal == 0 ? null : walletProvider.scanProgressPercent.clamp(0.0, 1.0),
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.gold),
                                  backgroundColor: AppColors.black.withOpacity(0.5),
                                  minHeight: 4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(walletProvider.syncStatus, style: const TextStyle(color: AppColors.gold, fontSize: 11)),
                            ],
                            if (!walletProvider.isConnected && !walletProvider.isSyncing) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 16),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Node: ${walletProvider.nodeHost}:${walletProvider.nodePort}',
                                      style: const TextStyle(color: Colors.orange, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (walletProvider.unconfirmedBalance > 0) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Pending: ${(walletProvider.unconfirmedBalance / 100000000).toStringAsFixed(8)} SHA',
                                style: const TextStyle(color: Colors.orange, fontSize: 14),
                              ),
                            ],
                            if (walletProvider.error != null) ...[
                              const SizedBox(height: 8),
                              Text('Error: ${walletProvider.error}', style: const TextStyle(color: Colors.red, fontSize: 12)),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => ReceiveScreenEnhanced(walletProvider: walletProvider)),
                            );
                          },
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          label: const Text('Receive'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.purple,
                            side: const BorderSide(color: AppColors.purple, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => SendScreen(walletProvider: walletProvider)),
                            );
                          },
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          label: const Text('Send'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.gold,
                            side: const BorderSide(color: AppColors.gold, width: 1.5),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('Transactions', style: TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                ],
              ),
            ),
            Expanded(
              child: utxos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.glassWhite,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(Icons.receipt_long_outlined, color: Colors.white24, size: 48),
                          ),
                          const SizedBox(height: 16),
                          const Text('No transactions yet', style: TextStyle(color: Colors.white54, fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: utxos.length,
                      itemBuilder: (context, index) {
                        final utxo = utxos[index];
                        final amountSha = utxo.value / 100000000;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.glassWhite,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: AppColors.glassBorder),
                                ),
                                child: ListTile(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => TransactionDetailScreen(utxo: utxo)),
                                    );
                                  },
                                  leading: Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(Icons.arrow_downward, color: Colors.green, size: 20),
                                  ),
                                  title: Text(
                                    '+${amountSha.toStringAsFixed(8)} SHA',
                                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Text(
                                    utxo.confirmed ? 'Block ${utxo.blockHeight ?? 'Unknown'}' : 'Pending',
                                    style: TextStyle(color: utxo.confirmed ? Colors.white54 : Colors.orange, fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        utxo.confirmed ? Icons.check_circle : Icons.pending,
                                        color: utxo.confirmed ? Colors.green : Colors.orange,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

}

