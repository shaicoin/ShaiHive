import 'dart:ui';
import 'package:flutter/material.dart';
import '../screens/wallet_detail_screen_enhanced.dart';
import '../theme/colors.dart';
import 'package:flutter/services.dart';

class WalletCard extends StatelessWidget {
  final Map<String, dynamic> wallet;
  final int index;
  final Function(int) onDelete;
  final Function(int) onRename;

  const WalletCard({
    super.key,
    required this.wallet,
    required this.index,
    required this.onDelete,
    required this.onRename,
  });

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _GlassAlertDialog(
        title: 'Delete Wallet',
        content: 'Are you sure you want to delete this wallet? This action cannot be undone.',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.goldLight)),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete(index);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _GlassAlertDialog(
        title: 'Warning: Sensitive Information',
        content: 'You are about to view your private keys. Make sure no one else can see your screen.',
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.goldLight)),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              _showKeysDialog(context);
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('View Keys'),
          ),
        ],
      ),
    );
  }

  void _showKeysDialog(BuildContext context) {
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
                    'Recovery Phrase',
                    style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                  const SizedBox(height: 16),
                  const Text('Write these words down in order:', style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.goldDark.withOpacity(0.5)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            wallet['mnemonic'],
                            style: const TextStyle(color: AppColors.goldLight, fontFamily: 'monospace'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.copy, color: AppColors.gold),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: wallet['mnemonic']));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Recovery phrase copied', style: TextStyle(color: Colors.white)),
                                backgroundColor: AppColors.purple.withOpacity(0.9),
                                behavior: SnackBarBehavior.floating,
                                margin: const EdgeInsets.all(8),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close', style: TextStyle(color: AppColors.goldLight)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.glassWhite,
                  AppColors.purple.withOpacity(0.05),
                ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WalletDetailScreenEnhanced(wallet: wallet),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.account_balance_wallet, color: AppColors.gold, size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${wallet['name'] ?? 'Wallet ${index + 1}'}',
                              style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, color: AppColors.gold),
                            color: AppColors.darkGrey.withOpacity(0.95),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: AppColors.glassBorder),
                            ),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'export',
                                child: Row(
                                  children: const [
                                    Icon(Icons.key, color: AppColors.gold),
                                    SizedBox(width: 12),
                                    Text('Export Keys', style: TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'rename',
                                child: Row(
                                  children: const [
                                    Icon(Icons.edit, color: AppColors.gold),
                                    SizedBox(width: 12),
                                    Text('Rename Wallet', style: TextStyle(color: Colors.white)),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: const [
                                    Icon(Icons.delete_forever, color: Colors.red),
                                    SizedBox(width: 12),
                                    Text('Delete Wallet', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) {
                              if (value == 'export') {
                                _showExportDialog(context);
                              } else if (value == 'rename') {
                                onRename(index);
                              } else if (value == 'delete') {
                                _showDeleteConfirmation(context);
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildAddressPreview('Native SegWit', wallet['native_segwit_address']),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddressPreview(String label, String address) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.glassBorder.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            address,
            style: const TextStyle(fontFamily: 'monospace', color: AppColors.goldLight, fontSize: 13),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _GlassAlertDialog extends StatelessWidget {
  final String title;
  final String content;
  final List<Widget> actions;

  const _GlassAlertDialog({
    required this.title,
    required this.content,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                Text(title, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 20)),
                const SizedBox(height: 16),
                Text(content, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 