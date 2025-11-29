import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/models/utxo.dart';
import '../theme/colors.dart';

class UtxoSelector extends StatefulWidget {
  final List<Utxo> utxos;
  final Set<String> selectedOutpoints;
  final Function(Set<String>) onSelectionChanged;
  final int feePerByte;
  final int Function(int inputCount, int outputCount, int feePerByte) estimateFee;

  const UtxoSelector({
    super.key,
    required this.utxos,
    required this.selectedOutpoints,
    required this.onSelectionChanged,
    required this.feePerByte,
    required this.estimateFee,
  });

  @override
  State<UtxoSelector> createState() => _UtxoSelectorState();
}

class _UtxoSelectorState extends State<UtxoSelector> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.from(widget.selectedOutpoints);
  }

  @override
  void didUpdateWidget(UtxoSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedOutpoints != widget.selectedOutpoints) {
      _selected = Set.from(widget.selectedOutpoints);
    }
  }

  int get _selectedTotal {
    return widget.utxos
        .where((u) => _selected.contains(u.outpoint))
        .fold<int>(0, (sum, u) => sum + u.value);
  }

  int get _estimatedFee {
    if (_selected.isEmpty) return 0;
    return widget.estimateFee(_selected.length, 2, widget.feePerByte);
  }

  void _toggleUtxo(Utxo utxo) {
    setState(() {
      if (_selected.contains(utxo.outpoint)) {
        _selected.remove(utxo.outpoint);
      } else {
        _selected.add(utxo.outpoint);
      }
    });
    widget.onSelectionChanged(_selected);
  }

  void _selectAll() {
    setState(() {
      _selected = widget.utxos
          .where((u) => u.isSpendable)
          .map((u) => u.outpoint)
          .toSet();
    });
    widget.onSelectionChanged(_selected);
  }

  void _selectNone() {
    setState(() {
      _selected.clear();
    });
    widget.onSelectionChanged(_selected);
  }

  String _formatSha(int sats) {
    return (sats / 100000000).toStringAsFixed(8);
  }

  String _truncateTxid(String txid) {
    if (txid.length <= 16) return txid;
    return '${txid.substring(0, 8)}...${txid.substring(txid.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    final spendable = widget.utxos.where((u) => u.isSpendable).toList();
    final frozen = widget.utxos.where((u) => u.frozen).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            border: Border(bottom: BorderSide(color: AppColors.glassBorder.withOpacity(0.5))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected: ${_selected.length} / ${spendable.length}',
                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text('${_formatSha(_selectedTotal)} SHA', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  if (_selected.isNotEmpty)
                    Text('Fee: ~${_formatSha(_estimatedFee)} SHA', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
              Row(
                children: [
                  TextButton(onPressed: _selectAll, child: const Text('All', style: TextStyle(color: AppColors.gold))),
                  TextButton(onPressed: _selectNone, child: const Text('None', style: TextStyle(color: Colors.white70))),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (spendable.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    'SPENDABLE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                ...spendable.map((utxo) => _buildUtxoTile(utxo, isSpendable: true)),
              ],
              if (frozen.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'FROZEN',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                ...frozen.map((utxo) => _buildUtxoTile(utxo, isSpendable: false)),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUtxoTile(Utxo utxo, {required bool isSpendable}) {
    final isSelected = _selected.contains(utxo.outpoint);
    
    return InkWell(
      onTap: isSpendable ? () => _toggleUtxo(utxo) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppColors.gold.withOpacity(0.1)
              : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.05),
            ),
          ),
        ),
        child: Row(
          children: [
            if (isSpendable)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppColors.gold : Colors.transparent,
                  border: Border.all(
                    color: isSelected ? AppColors.gold : Colors.white38,
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: AppColors.black)
                    : null,
              )
            else
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white10,
                ),
                child: const Icon(Icons.lock, size: 14, color: Colors.white38),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _truncateTxid(utxo.txid),
                    style: TextStyle(
                      color: isSpendable ? Colors.white : Colors.white38,
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'Output #${utxo.vout}',
                        style: TextStyle(
                          color: isSpendable ? Colors.white54 : Colors.white24,
                          fontSize: 12,
                        ),
                      ),
                      if (utxo.blockHeight != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Block ${utxo.blockHeight}',
                          style: TextStyle(
                            color: isSpendable ? Colors.white54 : Colors.white24,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (!utxo.confirmed) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'Unconfirmed',
                            style: TextStyle(
                              color: Colors.orange,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${_formatSha(utxo.value)} SHA',
                  style: TextStyle(
                    color: isSpendable 
                        ? (isSelected ? AppColors.gold : Colors.white)
                        : Colors.white38,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${utxo.value} sats',
                  style: TextStyle(
                    color: isSpendable ? Colors.white38 : Colors.white24,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UtxoSelectorSheet extends StatelessWidget {
  final List<Utxo> utxos;
  final Set<String> selectedOutpoints;
  final Function(Set<String>) onSelectionChanged;
  final int feePerByte;
  final int Function(int inputCount, int outputCount, int feePerByte) estimateFee;

  const UtxoSelectorSheet({
    super.key,
    required this.utxos,
    required this.selectedOutpoints,
    required this.onSelectionChanged,
    required this.feePerByte,
    required this.estimateFee,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: AppColors.darkGrey.withOpacity(0.9),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: const Border(
              top: BorderSide(color: AppColors.glassBorder),
              left: BorderSide(color: AppColors.glassBorder),
              right: BorderSide(color: AppColors.glassBorder),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.1)))),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Select UTXOs', style: TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.bold)),
                        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white70)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: UtxoSelector(
                  utxos: utxos,
                  selectedOutpoints: selectedOutpoints,
                  onSelectionChanged: onSelectionChanged,
                  feePerByte: feePerByte,
                  estimateFee: estimateFee,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1)))),
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.purple,
                    side: const BorderSide(color: AppColors.purple, width: 1.5),
                    minimumSize: const Size.fromHeight(50),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirm Selection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

