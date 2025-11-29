import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../widgets/wallet_card.dart';
import '../services/wallet_service.dart';
import '../theme/colors.dart';
import 'package:flutter/services.dart';
import 'seed_phrase_backup_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final List<Map<String, dynamic>> _wallets = [];
  final WalletService _walletService = WalletService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedWallets();
  }

  Future<void> _loadSavedWallets() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final walletsJson = prefs.getStringList('wallets') ?? [];
      setState(() {
        _wallets.clear();
        _wallets.addAll(
          walletsJson
              .map((json) => Map<String, dynamic>.from(jsonDecode(json))),
        );
      });
    } catch (e) {
      _showError('Error loading wallets: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveWallets() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final walletsJson = _wallets.map((w) => jsonEncode(w)).toList();
      await prefs.setStringList('wallets', walletsJson);
    } catch (e) {
      _showError('Error saving wallets: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: AppColors.purple,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(8),
      ),
    );
  }

  Future<void> _createWallet(String? name) async {
    try {
      final mnemonic = await _walletService.generateMnemonic();
      final walletName = name ?? 'Wallet ${_wallets.length + 1}';

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SeedPhraseBackupScreen(
            mnemonic: mnemonic,
            onConfirmed: () async {
              final wallet = await _walletService.createWalletFromMnemonic(mnemonic);
              wallet['name'] = walletName;
              setState(() {
                _wallets.add(wallet);
              });
              await _saveWallets();
              _showSuccess('Wallet created successfully!');
            },
          ),
        ),
      );
    } catch (e) {
      _showError('Error creating wallet: $e');
    }
  }

  Future<void> _restoreWallet(String mnemonic, String? name) async {
    try {
      final wallet = await _walletService.createWalletFromMnemonic(mnemonic);
      wallet['name'] = name ?? 'Wallet ${_wallets.length + 1}';
      setState(() {
        _wallets.add(wallet);
      });
      await _saveWallets();
      _showSuccess('Wallet restored successfully!');
    } catch (e) {
      _showError('Error restoring wallet: $e');
    }
  }

  void _showCreateWalletSheet() {
    _createWallet(null);
  }

  void _showRenameDialog(int index) {
    final TextEditingController controller = TextEditingController(text: _wallets[index]['name']);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.darkGrey.withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.glassBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Rename Wallet',
                    style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: 'Wallet Name',
                      labelStyle: const TextStyle(color: AppColors.goldLight),
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
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel', style: TextStyle(color: AppColors.goldLight)),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _wallets[index]['name'] = controller.text.isNotEmpty 
                                ? controller.text 
                                : 'Wallet ${index + 1}';
                          });
                          _saveWallets();
                          Navigator.pop(context);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.gold,
                          side: const BorderSide(color: AppColors.gold, width: 1.5),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        ),
                        child: const Text('Rename'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showRestoreWalletSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => RestoreWalletSheet(
        onRestoreWallet: _restoreWallet,
      ),
    );
  }

  Future<void> _deleteWallet(int index) async {
    setState(() {
      _wallets.removeAt(index);
    });
    await _saveWallets();
    _showSuccess('Wallet deleted');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 32,
              color: AppColors.gold,
            ),
            const SizedBox(width: 8),
            const Text(
              'ShaiHive',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.gold,
                fontSize: 24,
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.black,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.add, color: AppColors.gold),
            ),
            color: AppColors.darkGrey.withOpacity(0.95),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.glassBorder),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'create',
                child: Row(
                  children: const [
                    Icon(Icons.add_circle_outline, color: AppColors.gold),
                    SizedBox(width: 12),
                    Text('Create New Wallet', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'restore',
                child: Row(
                  children: const [
                    Icon(Icons.restore, color: AppColors.gold),
                    SizedBox(width: 12),
                    Text('Restore Wallet', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              if (value == 'create') {
                _showCreateWalletSheet();
              } else if (value == 'restore') {
                _showRestoreWalletSheet();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.purple),
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(5.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_wallets.isEmpty) ...[
                          const SizedBox(height: 20),
                          const Center(
                            child: Text(
                              'No wallets yet. Create or restore one below.',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_wallets.isNotEmpty)
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => WalletCard(
                        wallet: _wallets[index],
                        index: index,
                        onDelete: _deleteWallet,
                        onRename: _showRenameDialog,
                      ),
                      childCount: _wallets.length,
                    ),
                  ),
              ],
            ),
    );
  }
}

class RestoreWalletSheet extends StatefulWidget {
  final Function(String mnemonic, String? name) onRestoreWallet;

  const RestoreWalletSheet({
    super.key,
    required this.onRestoreWallet,
  });

  @override
  State<RestoreWalletSheet> createState() => _RestoreWalletSheetState();
}

class _RestoreWalletSheetState extends State<RestoreWalletSheet> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _mnemonicController = TextEditingController();
  bool _isLoading = false;

  void _showAnimatedToast(BuildContext context, String message, bool isError) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 100,
        left: 32,
        right: 32,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 50 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: isError ? Colors.red.withOpacity(0.9) : AppColors.purple.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: (isError ? Colors.red : AppColors.purple).withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isError ? Icons.error_outline : Icons.check_circle_outline,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.darkGrey.withOpacity(0.85),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: const Border(
              top: BorderSide(color: AppColors.glassBorder),
              left: BorderSide(color: AppColors.glassBorder),
              right: BorderSide(color: AppColors.glassBorder),
            ),
          ),
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Restore Wallet',
                  style: TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Wallet Name (optional)',
                    labelStyle: const TextStyle(color: AppColors.goldLight),
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
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onLongPress: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      _mnemonicController.text = data!.text!;
                    }
                  },
                  child: TextFormField(
                    controller: _mnemonicController,
                    decoration: InputDecoration(
                      labelText: 'Seed Phrase',
                      labelStyle: const TextStyle(color: AppColors.goldLight),
                      hintText: 'Enter your 12 or 24 word seed phrase',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
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
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.content_paste, color: AppColors.goldLight),
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            _mnemonicController.text = data!.text!;
                          }
                        },
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    maxLines: 3,
                    textInputAction: TextInputAction.done,
                    enableInteractiveSelection: true,
                    keyboardType: TextInputType.multiline,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _isLoading
                      ? null
                      : () async {
                          if (_mnemonicController.text.isEmpty) {
                            _showAnimatedToast(context, 'Please enter your seed phrase', true);
                            return;
                          }
                          setState(() => _isLoading = true);
                          try {
                            await widget.onRestoreWallet(
                              _mnemonicController.text,
                              _nameController.text.isNotEmpty ? _nameController.text : null,
                            );
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _isLoading = false);
                            }
                          }
                        },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.purple,
                    side: BorderSide(color: _isLoading ? AppColors.purple.withOpacity(0.4) : AppColors.purple, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.purple),
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Restore Wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 