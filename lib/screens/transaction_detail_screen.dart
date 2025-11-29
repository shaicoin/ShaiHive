import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../core/models/utxo.dart';

class TransactionDetailScreen extends StatelessWidget {
  final Utxo utxo;

  const TransactionDetailScreen({super.key, required this.utxo});

  @override
  Widget build(BuildContext context) {
    final amountSha = utxo.value / 100000000;

    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        title: const Text('Transaction Details', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.gold),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAmountCard(amountSha),
            const SizedBox(height: 20),
            _buildInfoSection('Transaction Information', [
              _InfoRow(label: 'Transaction ID', value: utxo.txid, copyable: true, context: context),
              _InfoRow(label: 'Output Index', value: utxo.vout.toString()),
              _InfoRow(label: 'Amount', value: '${amountSha.toStringAsFixed(8)} SHA'),
              _InfoRow(label: 'Amount (sats)', value: '${utxo.value} sats'),
              _InfoRow(label: 'Status', value: utxo.confirmed ? 'Confirmed' : 'Pending', valueColor: utxo.confirmed ? Colors.green : Colors.orange),
            ]),
            const SizedBox(height: 20),
            _buildInfoSection('Block Information', [
              _InfoRow(label: 'Block Height', value: utxo.blockHeight?.toString() ?? 'Pending', valueColor: utxo.blockHeight != null ? Colors.white : Colors.orange),
              _InfoRow(label: 'Confirmations', value: utxo.confirmed ? 'Confirmed' : '0 (Unconfirmed)', valueColor: utxo.confirmed ? Colors.green : Colors.orange),
            ]),
            if (utxo.address != null) ...[
              const SizedBox(height: 20),
              _buildInfoSection('Receiving Address', [_InfoRow(label: 'Address', value: utxo.address!, copyable: true, context: context)]),
            ],
            if (utxo.scriptPubKey != null) ...[
              const SizedBox(height: 20),
              _buildInfoSection('Script', [_InfoRow(label: 'Script PubKey', value: utxo.scriptPubKey!, copyable: true, context: context, mono: true)]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAmountCard(double amountSha) {
    return SizedBox(
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [AppColors.glassWhite, Colors.green.withOpacity(0.05)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Column(
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(18)),
                  child: const Icon(Icons.arrow_downward, color: Colors.green, size: 32),
                ),
                const SizedBox(height: 16),
                Text('+${amountSha.toStringAsFixed(8)} SHA', style: const TextStyle(color: Colors.green, fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: (utxo.confirmed ? Colors.green : Colors.orange).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(utxo.confirmed ? 'Confirmed' : 'Pending', style: TextStyle(color: utxo.confirmed ? Colors.green : Colors.orange, fontSize: 14, fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoSection(String title, List<Widget> rows) {
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
              Text(title, style: const TextStyle(color: AppColors.gold, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              ...rows,
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool copyable;
  final Color? valueColor;
  final BuildContext? context;
  final bool mono;

  const _InfoRow({
    required this.label,
    required this.value,
    this.copyable = false,
    this.valueColor,
    this.context,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    color: valueColor ?? Colors.white,
                    fontSize: 14,
                    fontFamily: mono ? 'monospace' : null,
                  ),
                ),
              ),
              if (copyable && this.context != null)
                IconButton(
                  icon: const Icon(
                    Icons.copy,
                    color: AppColors.purple,
                    size: 18,
                  ),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(this.context!).showSnackBar(
                      SnackBar(
                        content: Text('$label copied'),
                        backgroundColor: AppColors.purple,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
