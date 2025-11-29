import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/colors.dart';
import '../core/models/app_settings.dart';
import '../presentation/providers/neutrino_wallet_provider.dart';

class ReceiveScreenEnhanced extends StatefulWidget {
  final NeutrinoWalletProvider walletProvider;

  const ReceiveScreenEnhanced({super.key, required this.walletProvider});

  @override
  State<ReceiveScreenEnhanced> createState() => _ReceiveScreenEnhancedState();
}

class _ReceiveScreenEnhancedState extends State<ReceiveScreenEnhanced> {
  AddressType _selectedAddressType = AddressType.nativeSegwit;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  AppSettings? _settings;
  late final PageController _pageController;
  int _currentPage = 0;
  List<String> _addresses = [];
  int _totalAddressCount = 0;
  static const int _pageSize = 10;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
    widget.walletProvider.addListener(_onProviderChanged);
    _loadSettings();
  }

  @override
  void dispose() {
    widget.walletProvider.removeListener(_onProviderChanged);
    _pageController.dispose();
    super.dispose();
  }

  void _onProviderChanged() {
    if (!mounted) return;
    if (widget.walletProvider.isInitialized && _addresses.isEmpty) {
      _loadInitialAddresses();
    }
  }

  Future<void> _loadSettings() async {
    final settings = await AppSettings.load();
    _settings = settings;
    _selectedAddressType = settings.preferredAddressType;
    _loadInitialAddresses();
    setState(() {
      _isLoading = false;
    });
  }

  void _loadInitialAddresses() {
    if (!widget.walletProvider.isInitialized) return;
    _totalAddressCount = widget.walletProvider.getAddressCount(_selectedAddressType);
    if (_totalAddressCount == 0) {
      _addresses = [];
      return;
    }
    final endIndex = (_pageSize - 1).clamp(0, _totalAddressCount - 1);
    _addresses = widget.walletProvider.getAddressesInRange(
      _selectedAddressType,
      0,
      endIndex,
    );
    _currentPage = 0;
  }

  void _loadMoreAddresses() {
    if (_isLoadingMore) return;
    final loadedEnd = _addresses.length;
    if (loadedEnd >= _totalAddressCount) return;
    _isLoadingMore = true;
    final newEnd = (loadedEnd + _pageSize - 1).clamp(0, _totalAddressCount - 1);
    final newAddresses = widget.walletProvider.getAddressesInRange(
      _selectedAddressType,
      loadedEnd,
      newEnd,
    );
    setState(() {
      _addresses = [..._addresses, ...newAddresses];
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildLoadingScaffold();
    }

    final isReady = widget.walletProvider.isInitialized;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.gold),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAddressTypeSelector(),
            const SizedBox(height: 20),
            if (!isReady)
              _buildProviderPending()
            else if (_addresses.isEmpty)
              _buildEmptyState()
            else
              _buildAddressCarousel(_addresses),
          ],
        ),
      ),
    );
  }

  Scaffold _buildLoadingScaffold() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.gold),
      ),
      body: const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppColors.purple))),
    );
  }

  Widget _buildAddressTypeSelector() {
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
              const Text('Address Type', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              DropdownButtonFormField<AddressType>(
                value: _selectedAddressType,
                dropdownColor: AppColors.darkGrey.withOpacity(0.95),
                decoration: InputDecoration(
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.goldDark.withOpacity(0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.gold, width: 2),
                  ),
                  filled: true,
                  fillColor: AppColors.black.withOpacity(0.3),
                ),
                items: AddressType.values.where((type) => type != AddressType.taproot).map((type) {
                  return DropdownMenuItem(value: type, child: Text(_getAddressTypeName(type), style: const TextStyle(color: Colors.white)));
                }).toList(),
                onChanged: (AddressType? newValue) {
                  if (newValue != null) _updateAddressType(newValue);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderPending() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
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
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3, valueColor: AlwaysStoppedAnimation<Color>(AppColors.purple)),
                  ),
                  const SizedBox(width: 12),
                  Text(widget.walletProvider.syncStatus, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Wallet is connecting to the network. Balances will update once syncing finishes.', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Column(
            children: [
              Container(
                height: 72,
                width: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: AppColors.purple.withOpacity(0.2),
                ),
                child: const Icon(Icons.wallet_rounded, color: AppColors.gold, size: 36),
              ),
              const SizedBox(height: 16),
              const Text('No addresses yet', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('No receive addresses have been generated yet.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddressCarousel(List<String> addresses) {
    return Column(
      children: [
        SizedBox(
          height: 430,
          child: PageView.builder(
            controller: _pageController,
            itemCount: addresses.length,
            allowImplicitScrolling: true,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
              if (index >= addresses.length - 3 && addresses.length < _totalAddressCount && !_isLoadingMore) {
                _loadMoreAddresses();
              }
            },
            itemBuilder: (context, index) {
              final isActive = index == _currentPage;
              return RepaintBoundary(
                child: AnimatedScale(
                  scale: isActive ? 1.0 : 0.95,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: _buildAddressCard(index, addresses[index]),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        _buildPageIndicator(_totalAddressCount),
      ],
    );
  }

  Widget _buildPageIndicator(int totalCount) {
    if (totalCount <= 1) {
      return const SizedBox.shrink();
    }
    return Text(
      '${_currentPage + 1} / $totalCount',
      style: TextStyle(
        color: AppColors.gold.withOpacity(0.8),
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildAddressCard(int index, String address) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.glassWhite,
                  AppColors.purple.withOpacity(0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
              boxShadow: [
                BoxShadow(color: AppColors.purple.withOpacity(0.15), blurRadius: 30, offset: const Offset(0, 15)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Address #${index + 1}', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 16),
                Expanded(
                  child: Center(
                    child: RepaintBoundary(
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(color: AppColors.purple.withOpacity(0.3), blurRadius: 30, spreadRadius: 2),
                            BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10)),
                          ],
                        ),
                        child: QrImageView(
                          data: address,
                          version: QrVersions.auto,
                          size: 260,
                          eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.black),
                          dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.black),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.glassBorder.withOpacity(0.5)),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Receive Address', style: TextStyle(color: Colors.white60, fontSize: 12)),
                      const SizedBox(height: 6),
                      SelectableText(address, style: const TextStyle(fontFamily: 'monospace', color: Colors.white, fontSize: 12, height: 1.3)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _copyToClipboard(context, address, 'Address'),
                        icon: const Icon(Icons.copy, color: AppColors.gold, size: 18),
                        label: const Text('Copy', style: TextStyle(color: AppColors.gold)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.goldDark.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showQRDialog(context, 'Address #${index + 1}', address),
                        icon: const Icon(Icons.qr_code_2, color: AppColors.gold, size: 18),
                        label: const Text('Full QR', style: TextStyle(color: AppColors.gold)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: AppColors.goldDark.withOpacity(0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _updateAddressType(AddressType type) async {
    _selectedAddressType = type;
    _loadInitialAddresses();
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients && _addresses.isNotEmpty) {
        _pageController.jumpToPage(_currentPage);
      }
    });
    final currentSettings = _settings;
    if (currentSettings != null) {
      currentSettings.preferredAddressType = type;
      await currentSettings.save();
    }
  }

  String _getAddressTypeName(AddressType type) {
    switch (type) {
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

  void _showQRDialog(BuildContext context, String label, String address) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.darkGrey.withOpacity(0.85),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$label QR Code', style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 20)),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(color: AppColors.purple.withOpacity(0.3), blurRadius: 25, spreadRadius: 2),
                        BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8)),
                      ],
                    ),
                    child: QrImageView(
                      data: address,
                      version: QrVersions.auto,
                      size: 280,
                      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: AppColors.black),
                      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: AppColors.black),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SelectableText(address, style: const TextStyle(fontFamily: 'monospace', color: Colors.white70, fontSize: 11), textAlign: TextAlign.center),
                  ),
                  const SizedBox(height: 20),
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: AppColors.goldLight, fontSize: 16))),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard',
            style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.purple,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
      ),
    );
  }
}

