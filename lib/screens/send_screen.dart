import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../presentation/providers/neutrino_wallet_provider.dart';
import '../widgets/utxo_selector.dart';

class SendScreen extends StatefulWidget {
  final NeutrinoWalletProvider walletProvider;

  const SendScreen({super.key, required this.walletProvider});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  late final TextEditingController _feeController;
  bool _isSending = false;
  bool _sweepEnabled = false;
  bool _rbfEnabled = true;
  bool _manualUtxoSelection = false;
  int _estimatedFee = 0;
  int _maxSendAmount = 0;
  Set<String> _selectedUtxoOutpoints = {};

  @override
  void initState() {
    super.initState();
    final minFee = widget.walletProvider.minFeeRate;
    _feeController = TextEditingController(text: minFee.toString());
    _feeController.addListener(_updateFeeEstimate);
    _amountController.addListener(_updateFeeEstimate);
    _updateFeeEstimate();
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  Future<void> _updateFeeEstimate() async {
    final minFee = widget.walletProvider.minFeeRate;
    final feePerByte = int.tryParse(_feeController.text.trim()) ?? minFee;
    try {
      final selectedOutpoints = _manualUtxoSelection && _selectedUtxoOutpoints.isNotEmpty
          ? _selectedUtxoOutpoints.toList()
          : null;
      final maxData = await widget.walletProvider.calculateMaxSendAmount(
        feePerByte,
        selectedOutpoints: selectedOutpoints,
      );
      if (mounted) {
        setState(() {
          _maxSendAmount = maxData['maxAmount'] as int;
          _estimatedFee = maxData['fee'] as int;
        });
      }
    } catch (_) {}
  }

  int _getSelectedUtxoTotal() {
    final utxos = widget.walletProvider.utxos;
    return utxos
        .where((u) => _selectedUtxoOutpoints.contains(u.outpoint))
        .fold<int>(0, (sum, u) => sum + u.value);
  }

  void _openUtxoSelector() {
    final utxos = widget.walletProvider.utxos;
    final feePerByte = int.tryParse(_feeController.text.trim()) ?? widget.walletProvider.minFeeRate;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => UtxoSelectorSheet(
        utxos: utxos,
        selectedOutpoints: _selectedUtxoOutpoints,
        onSelectionChanged: (selected) {
          setState(() {
            _selectedUtxoOutpoints = selected;
          });
          _updateFeeEstimate();
        },
        feePerByte: feePerByte,
        estimateFee: widget.walletProvider.estimateFee,
      ),
    );
  }

  void _onSweepToggled(bool value) {
    setState(() {
      _sweepEnabled = value;
      if (value) {
        if (_manualUtxoSelection && _selectedUtxoOutpoints.isNotEmpty) {
          final feePerByte = int.tryParse(_feeController.text.trim()) ?? widget.walletProvider.minFeeRate;
          final total = _getSelectedUtxoTotal();
          final fee = widget.walletProvider.estimateFee(_selectedUtxoOutpoints.length, 1, feePerByte);
          final maxAmount = total - fee;
          final amountSha = maxAmount / 100000000;
          _amountController.text = amountSha.toStringAsFixed(8);
        } else {
          final amountSha = _maxSendAmount / 100000000;
          _amountController.text = amountSha.toStringAsFixed(8);
        }
      }
    });
  }

  void _onManualUtxoToggled(bool value) {
    setState(() {
      _manualUtxoSelection = value;
      if (!value) {
        _selectedUtxoOutpoints.clear();
      }
    });
    _updateFeeEstimate();
  }

  Future<void> _sendTransaction() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_manualUtxoSelection && _selectedUtxoOutpoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one UTXO'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final address = _addressController.text.trim();
    final amountSha = double.tryParse(_amountController.text.trim()) ?? 0;
    final amountSatoshis = (amountSha * 100000000).toInt();
    final feePerByte = int.tryParse(_feeController.text.trim()) ?? widget.walletProvider.minFeeRate;
    final feeSha = _estimatedFee / 100000000;

    final confirm = await showDialog<bool>(
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
                  const Text('Confirm Transaction', style: TextStyle(color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildConfirmRow('To:', address),
                        const SizedBox(height: 8),
                        _buildConfirmRow('Amount:', '$amountSha SHA'),
                        const SizedBox(height: 8),
                        _buildConfirmRow('Fee Rate:', '$feePerByte sat/byte'),
                        const SizedBox(height: 8),
                        _buildConfirmRow('Est. Fee:', '~${feeSha.toStringAsFixed(8)} SHA'),
                      ],
                    ),
                  ),
                  if (_sweepEnabled) ...[
                    const SizedBox(height: 12),
                    const Text('⚠️ Sweep mode: Fee deducted from amount', style: TextStyle(color: AppColors.gold, fontSize: 12)),
                  ],
                  if (_rbfEnabled) ...[
                    const SizedBox(height: 4),
                    const Text('✓ RBF enabled (can bump fee later)', style: TextStyle(color: Colors.green, fontSize: 12)),
                  ],
                  if (_manualUtxoSelection && _selectedUtxoOutpoints.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '⚙️ Using ${_selectedUtxoOutpoints.length} selected UTXO${_selectedUtxoOutpoints.length > 1 ? 's' : ''}',
                      style: const TextStyle(color: AppColors.goldLight, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Are you sure you want to send this transaction?', style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.purple,
                          side: const BorderSide(color: AppColors.purple, width: 1.5),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                        child: const Text('Send'),
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

    if (confirm != true) return;

    setState(() {
      _isSending = true;
    });

    try {
      final selectedOutpoints = _manualUtxoSelection && _selectedUtxoOutpoints.isNotEmpty
          ? _selectedUtxoOutpoints.toList()
          : null;
      final txid = await widget.walletProvider.sendTransaction(
        recipientAddress: address,
        amount: amountSatoshis,
        feePerByte: feePerByte,
        subtractFeeFromAmount: _sweepEnabled,
        enableRbf: _rbfEnabled,
        selectedOutpoints: selectedOutpoints,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transaction sent! TXID: ${txid.substring(0, 16)}...'),
            backgroundColor: AppColors.purple,
            duration: const Duration(seconds: 3),
          ),
        );

        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send transaction: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Widget _buildConfirmRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.gold),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.glassWhite, AppColors.purple.withOpacity(0.05)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _manualUtxoSelection && _selectedUtxoOutpoints.isNotEmpty ? 'Selected UTXOs' : 'Available Balance',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Image.asset('assets/images/logo.png', height: 22, color: AppColors.gold),
                            const SizedBox(width: 8),
                            Text(
                              _manualUtxoSelection && _selectedUtxoOutpoints.isNotEmpty
                                  ? '${(_getSelectedUtxoTotal() / 100000000).toStringAsFixed(8)} SHA'
                                  : '${widget.walletProvider.balanceFormatted} SHA',
                              style: const TextStyle(color: AppColors.gold, fontSize: 22, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        if (_manualUtxoSelection && _selectedUtxoOutpoints.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${_selectedUtxoOutpoints.length} UTXO${_selectedUtxoOutpoints.length != 1 ? 's' : ''} • Total: ${widget.walletProvider.balanceFormatted} SHA',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: 'Recipient Address',
                  labelStyle: const TextStyle(color: AppColors.goldLight),
                  hintText: 'sh1...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.goldDark.withOpacity(0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.gold, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                  filled: true,
                  fillColor: AppColors.black.withOpacity(0.3),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste, color: AppColors.goldLight),
                    onPressed: () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) _addressController.text = data!.text!;
                    },
                  ),
                ),
                style: const TextStyle(color: Colors.white),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter a recipient address';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amountController,
                enabled: !_sweepEnabled,
                decoration: InputDecoration(
                  labelText: 'Amount (SHA)',
                  labelStyle: const TextStyle(color: AppColors.goldLight),
                  hintText: '0.00000000',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.goldDark.withOpacity(0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.gold, width: 2),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.goldDark.withOpacity(0.3)),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                  filled: true,
                  fillColor: AppColors.black.withOpacity(0.3),
                  suffixIcon: TextButton(
                    onPressed: _sweepEnabled ? null : () => _onSweepToggled(true),
                    child: Text('MAX', style: TextStyle(color: _sweepEnabled ? Colors.grey : AppColors.gold)),
                  ),
                ),
                style: TextStyle(color: _sweepEnabled ? Colors.white70 : Colors.white),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter an amount';
                  final amount = double.tryParse(value);
                  if (amount == null || amount <= 0) return 'Please enter a valid amount';
                  final amountSatoshis = (amount * 100000000).toInt();
                  if (!_sweepEnabled) {
                    final availableBalance = _manualUtxoSelection && _selectedUtxoOutpoints.isNotEmpty
                        ? _getSelectedUtxoTotal()
                        : widget.walletProvider.balance;
                    if (amountSatoshis > availableBalance) return 'Insufficient funds';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: SwitchListTile(
                      title: const Text('Sweep (Send All)', style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: Text(
                        _sweepEnabled ? 'Fee will be deducted from amount' : 'Send entire balance minus fee',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      value: _sweepEnabled,
                      onChanged: _onSweepToggled,
                      activeColor: AppColors.gold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _feeController,
                decoration: InputDecoration(
                  labelText: 'Fee Rate (sat/byte) • Min: ${widget.walletProvider.minFeeRate}',
                  labelStyle: const TextStyle(color: AppColors.goldLight),
                  hintText: '${widget.walletProvider.minFeeRate}',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.goldDark.withOpacity(0.5)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.gold, width: 2),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                  ),
                  filled: true,
                  fillColor: AppColors.black.withOpacity(0.3),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please enter a fee rate';
                  final fee = int.tryParse(value);
                  final minFee = widget.walletProvider.minFeeRate;
                  if (fee == null || fee < minFee) return 'Fee rate must be at least $minFee sat/byte';
                  return null;
                },
              ),
              if (_estimatedFee > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Estimated fee: ${(_estimatedFee / 100000000).toStringAsFixed(8)} SHA ($_estimatedFee sats)',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: SwitchListTile(
                      title: const Text('Enable RBF', style: TextStyle(color: Colors.white, fontSize: 14)),
                      subtitle: const Text('Allow fee bumping if transaction is stuck', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      value: _rbfEnabled,
                      onChanged: (value) => setState(() => _rbfEnabled = value),
                      activeColor: AppColors.gold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Manual UTXO Selection', style: TextStyle(color: Colors.white, fontSize: 14)),
                          subtitle: Text(
                            _manualUtxoSelection
                                ? '${_selectedUtxoOutpoints.length} UTXO${_selectedUtxoOutpoints.length != 1 ? 's' : ''} selected'
                                : 'Choose specific coins to spend',
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          value: _manualUtxoSelection,
                          onChanged: _onManualUtxoToggled,
                          activeColor: AppColors.gold,
                        ),
                        if (_manualUtxoSelection)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _openUtxoSelector,
                                icon: const Icon(Icons.account_balance_wallet, size: 18),
                                label: Text(
                                  _selectedUtxoOutpoints.isEmpty
                                      ? 'Select UTXOs'
                                      : 'Change Selection (${(_getSelectedUtxoTotal() / 100000000).toStringAsFixed(8)} SHA)',
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.gold,
                                  side: BorderSide(color: AppColors.goldDark.withOpacity(0.5)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: _isSending ? null : _sendTransaction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.purple,
                  side: BorderSide(color: _isSending ? AppColors.purple.withOpacity(0.4) : AppColors.purple, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppColors.purple), strokeWidth: 2),
                      )
                    : const Text('Send Transaction', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

