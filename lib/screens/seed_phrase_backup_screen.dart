import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import '../theme/colors.dart';

class SeedPhraseBackupScreen extends StatefulWidget {
  final String mnemonic;
  final VoidCallback onConfirmed;

  const SeedPhraseBackupScreen({
    super.key,
    required this.mnemonic,
    required this.onConfirmed,
  });

  @override
  State<SeedPhraseBackupScreen> createState() => _SeedPhraseBackupScreenState();
}

class _SeedPhraseBackupScreenState extends State<SeedPhraseBackupScreen> {
  int _currentStep = 0;
  late List<String> _words;
  late List<int> _verificationIndices;
  final Map<int, String> _userInputs = {};
  bool _isRevealed = false;

  @override
  void initState() {
    super.initState();
    _words = widget.mnemonic.split(' ');
    _generateVerificationIndices();
  }

  void _generateVerificationIndices() {
    final random = Random();
    final indices = <int>{};
    while (indices.length < 3) {
      indices.add(random.nextInt(_words.length));
    }
    _verificationIndices = indices.toList()..sort();
  }

  bool _verifyInputs() {
    for (final index in _verificationIndices) {
      final input = _userInputs[index]?.trim().toLowerCase();
      if (input != _words[index].toLowerCase()) {
        return false;
      }
    }
    return true;
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.mnemonic));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Recovery phrase copied to clipboard',
            style: TextStyle(color: Colors.white)),
        backgroundColor: AppColors.purple,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.gold),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _currentStep == 0 ? 'Backup Seed Phrase' : 'Verify Seed Phrase',
          style: const TextStyle(color: AppColors.gold),
        ),
      ),
      body: SafeArea(
        child: _currentStep == 0 ? _buildDisplayStep() : _buildVerificationStep(),
      ),
    );
  }

  Widget _buildDisplayStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.orange[400], size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Never share your seed phrase. Anyone with these words can access your funds.', style: TextStyle(color: Colors.orange[300], fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Write down these 12 words in order and keep them somewhere safe:', style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 24),
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _isRevealed = !_isRevealed),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.glassWhite,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Stack(
                      children: [
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 2.5, crossAxisSpacing: 10, mainAxisSpacing: 10),
                          itemCount: _words.length,
                          itemBuilder: (context, index) {
                            return Container(
                              decoration: BoxDecoration(
                                color: AppColors.black.withOpacity(0.4),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.glassBorder.withOpacity(0.5)),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}. ${_isRevealed ? _words[index] : '••••••'}',
                                  style: TextStyle(color: _isRevealed ? AppColors.goldLight : Colors.white38, fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'monospace'),
                                ),
                              ),
                            );
                          },
                        ),
                        if (!_isRevealed)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(14)),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(16)),
                                    child: const Icon(Icons.visibility_off, color: AppColors.gold, size: 40),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('Tap to reveal seed phrase', style: TextStyle(color: AppColors.goldLight, fontSize: 16)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _copyToClipboard,
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: BorderSide(color: AppColors.goldDark.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: _isRevealed ? () => setState(() => _currentStep = 1) : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: _isRevealed ? AppColors.purple : AppColors.purple.withOpacity(0.4),
              side: BorderSide(color: _isRevealed ? AppColors.purple : AppColors.purple.withOpacity(0.3), width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('I\'ve Written It Down', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.purple.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.quiz_outlined, color: AppColors.purpleLight, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('Verify you\'ve saved your seed phrase by entering the requested words.', style: TextStyle(color: AppColors.purpleLight, fontSize: 14)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text('Enter the following words from your seed phrase:', style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 24),
          ..._verificationIndices.map((index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextField(
              onChanged: (value) => _userInputs[index] = value,
              decoration: InputDecoration(
                labelText: 'Word #${index + 1}',
                labelStyle: const TextStyle(color: AppColors.goldLight),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppColors.goldDark.withOpacity(0.5))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.gold, width: 2)),
                filled: true,
                fillColor: AppColors.black.withOpacity(0.3),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 16),
              autocorrect: false,
              enableSuggestions: false,
            ),
          )),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep = 0),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.gold,
                    side: BorderSide(color: AppColors.goldDark.withOpacity(0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: OutlinedButton(
                  onPressed: () {
                    if (_verifyInputs()) {
                      widget.onConfirmed();
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Incorrect words. Please check and try again.', style: TextStyle(color: Colors.white)),
                          backgroundColor: Colors.red.withOpacity(0.9),
                          behavior: SnackBarBehavior.floating,
                          margin: const EdgeInsets.all(8),
                        ),
                      );
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.purple,
                    side: const BorderSide(color: AppColors.purple, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Confirm & Save Wallet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

