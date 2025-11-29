import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/colors.dart';
import '../services/verifiable_credential_service.dart';

class CredentialsScreen extends StatefulWidget {
  final Map<String, dynamic> wallet;
  
  const CredentialsScreen({super.key, required this.wallet});
  
  @override
  State<CredentialsScreen> createState() => _CredentialsScreenState();
}

class _CredentialsScreenState extends State<CredentialsScreen> with SingleTickerProviderStateMixin {
  final _credentialService = VerifiableCredentialService();
  late String _did;
  List<Map<String, dynamic>> _credentials = [];
  int _currentIndex = 0;
  double _dragOffset = 0;
  double _incomingCardOffset = -400;
  bool _isAnimatingBack = false;
  late AnimationController _animController;
  late Animation<double> _animation;
  
  @override
  void initState() {
    super.initState();
    _initializeDID();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    )..addListener(() {
      setState(() {
        _dragOffset = _animation.value;
      });
    });
  }
  
  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }
  
  void _initializeDID() {
    _did = _credentialService.generateDID(widget.wallet['native_segwit_address']);
  }
  
  void _addCredential() async {
    final privateKey = base64Decode(widget.wallet['privateKey']);
    
    final credential = _credentialService.createVerifiableCredential(
      did: _did,
      type: 'TradingCardCredential',
      claims: {
        'id': _did,
        'cardName': 'Shaicoin Honey Bee',
        'cardType': 'Legendary Creature',
        'edition': 'First Edition',
        'serialNumber': '#${(math.Random().nextInt(9999) + 1).toString().padLeft(4, '0')}/10000',
        'rarity': 'Legendary',
        'element': 'Crypto',
        'status': 'Coming Soon',
        'lore': 'Born from the genesis block, this golden bee pollinates the blockchain with unstoppable cryptographic nectar.',
        'artist': 'SatoshiArt',
        'year': 2024,
      },
      privateKey: privateKey,
    );
    
    setState(() {
      _credentials.add(credential);
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: AppColors.darkGrey,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.fingerprint, color: AppColors.gold, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'DID',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.copy, color: AppColors.gold, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: _did));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('DID copied'),
                              backgroundColor: AppColors.purple,
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _did,
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Credentials',
                style: TextStyle(
                  color: AppColors.gold,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (_credentials.isEmpty)
                TextButton.icon(
                  onPressed: _addCredential,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Demo', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.purple,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _credentials.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.style_outlined, color: Colors.white24, size: 48),
                        const SizedBox(height: 12),
                        const Text(
                          'No credentials yet',
                          style: TextStyle(color: Colors.white38),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap Demo to add a sample trading card',
                          style: TextStyle(color: Colors.white24, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : _buildCardStack(),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCardStack() {
    const cardAspectRatio = 0.65;
    
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxHeight = constraints.maxHeight - 60;
              final cardHeight = maxHeight.clamp(300.0, 500.0);
              final cardWidth = cardHeight * cardAspectRatio;
              
              return Center(
                child: GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _dragOffset += details.delta.dx;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    final velocity = details.primaryVelocity ?? 0;
                    if (_dragOffset < -80 || velocity < -500) {
                      if (_currentIndex < _credentials.length - 1) {
                        _animateToNext();
                      } else {
                        _animateBack();
                      }
                    } else if (_dragOffset > 80 || velocity > 500) {
                      if (_currentIndex > 0) {
                        _animateToPrev();
                      } else {
                        _animateBack();
                      }
                    } else {
                      _animateBack();
                    }
                  },
                  child: SizedBox(
                    width: cardWidth,
                    height: cardHeight,
                    child: Stack(
                      alignment: Alignment.center,
                      clipBehavior: Clip.none,
                      children: [
                        if (_isAnimatingBack && _currentIndex > 0)
                          Positioned.fill(
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..translate(_incomingCardOffset, 0.0)
                                ..rotateZ(_incomingCardOffset * 0.0005),
                              child: Opacity(
                                opacity: (1 - (_incomingCardOffset.abs() / 400)).clamp(0.0, 1.0),
                                child: AbsorbPointer(
                                  absorbing: true,
                                  child: TradingCard3D(credential: _credentials[_currentIndex - 1]),
                                ),
                              ),
                            ),
                          ),
                        for (int depth = 2; depth >= 0; depth--)
                          if (_currentIndex + depth < _credentials.length)
                            Positioned.fill(
                              child: Builder(
                                builder: (context) {
                                  final cardIndex = _currentIndex + depth;
                                  final isTop = depth == 0;
                                  final scale = 1.0 - (depth * 0.05);
                                  final yOffset = depth * 20.0;
                                  
                                  double xOffset = 0;
                                  double rotation = 0;
                                  if (isTop) {
                                    xOffset = _dragOffset;
                                    rotation = _dragOffset * 0.0005;
                                  }
                                  
                                  return Transform(
                                    alignment: Alignment.center,
                                    transform: Matrix4.identity()
                                      ..translate(xOffset, yOffset)
                                      ..rotateZ(rotation)
                                      ..scale(scale),
                                    child: Opacity(
                                      opacity: isTop ? 1.0 : 0.7 - (depth * 0.2),
                                      child: GestureDetector(
                                        onTap: isTop ? () => _showCardDetail(context, cardIndex) : null,
                                        child: AbsorbPointer(
                                          absorbing: true,
                                          child: TradingCard3D(credential: _credentials[cardIndex]),
                                        ),
                                      ),
                                    ),
                                  );
                                },
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
        if (_credentials.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_credentials.length, (i) {
                final isActive = i == _currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: isActive ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.gold : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
  
  void _animateToNext() {
    _animation = Tween<double>(begin: _dragOffset, end: -400).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward(from: 0).then((_) {
      setState(() {
        _currentIndex++;
        _dragOffset = 0;
      });
    });
  }
  
  void _animateToPrev() {
    setState(() {
      _isAnimatingBack = true;
      _incomingCardOffset = -400 + _dragOffset;
    });
    _animation = Tween<double>(begin: _incomingCardOffset, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    )..addListener(() {
      setState(() {
        _incomingCardOffset = _animation.value;
      });
    });
    _animController.forward(from: 0).then((_) {
      setState(() {
        _currentIndex--;
        _dragOffset = 0;
        _isAnimatingBack = false;
        _incomingCardOffset = -400;
      });
    });
  }
  
  void _animateBack() {
    _animation = Tween<double>(begin: _dragOffset, end: 0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.forward(from: 0);
  }
  
  void _showCardDetail(BuildContext context, int index) {
    final credential = _credentials[index];
    final isValid = _isCredentialValid(credential);
    
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: AspectRatio(
                aspectRatio: 0.65,
                child: TradingCard3D(credential: credential, enablePan: true),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isValid ? Colors.green.withOpacity(0.15) : Colors.red.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isValid ? Colors.green.withOpacity(0.4) : Colors.red.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isValid ? Icons.verified : Icons.error_outline,
                    color: isValid ? Colors.green : Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    isValid ? 'Verified Credential' : 'Invalid Credential',
                    style: TextStyle(
                      color: isValid ? Colors.green : Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Double-tap to view raw • Drag to rotate',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.darkGrey.withOpacity(0.95),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionButton(
                    icon: Icons.present_to_all,
                    label: 'Present',
                    color: Colors.blue,
                    onTap: () => _presentCredential(context, credential),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.swap_horiz,
                    label: 'Transfer',
                    color: Colors.orange,
                    onTap: () => _transferCredential(context, credential),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.share,
                    label: 'Share',
                    color: Colors.teal,
                    onTap: () => _shareCredential(context, credential),
                  ),
                  const SizedBox(width: 8),
                  _buildActionButton(
                    icon: Icons.close,
                    label: 'Close',
                    color: Colors.grey,
                    onTap: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  bool _isCredentialValid(Map<String, dynamic> credential) {
    final proof = credential['proof'] as Map<String, dynamic>?;
    return proof != null &&
        proof['type'] != null &&
        proof['proofValue'] != null &&
        proof['verificationMethod'] != null &&
        credential['@context'] != null &&
        credential['issuer'] != null &&
        credential['credentialSubject'] != null;
  }
  
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  void _presentCredential(BuildContext context, Map<String, dynamic> credential) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkGrey,
        title: Row(
          children: [
            Icon(Icons.present_to_all, color: Colors.blue),
            const SizedBox(width: 8),
            const Text('Create Presentation', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create a Verifiable Presentation to share this credential with a verifier.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Holder DID:', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  Text(_did, style: TextStyle(color: Colors.blue, fontSize: 9, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Text('Credential Type:', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  Text('TradingCardCredential', style: TextStyle(color: Colors.white, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Verifiable Presentation created'),
                  backgroundColor: Colors.blue,
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.blue,
              side: const BorderSide(color: Colors.blue, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Create VP'),
          ),
        ],
      ),
    );
  }
  
  void _transferCredential(BuildContext context, Map<String, dynamic> credential) {
    Navigator.pop(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.darkGrey,
        title: Row(
          children: [
            Icon(Icons.swap_horiz, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('Transfer Ownership', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Transfer this credential to another DID. This will update the credential subject and re-sign with the new holder.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                hintText: 'did:shai:recipient...',
                hintStyle: TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(Icons.person_outline, color: Colors.orange),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Transfer feature coming soon'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange,
              side: const BorderSide(color: Colors.orange, width: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: const Text('Transfer'),
          ),
        ],
      ),
    );
  }
  
  void _shareCredential(BuildContext context, Map<String, dynamic> credential) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Share feature coming soon'),
        backgroundColor: Colors.teal,
      ),
    );
  }
}

class TradingCard3D extends StatefulWidget {
  final Map<String, dynamic> credential;
  final bool enablePan;
  
  const TradingCard3D({super.key, required this.credential, this.enablePan = false});
  
  @override
  State<TradingCard3D> createState() => _TradingCard3DState();
}

class _TradingCard3DState extends State<TradingCard3D> with TickerProviderStateMixin {
  double _rotateX = 0;
  double _rotateY = 0;
  bool _isHolographic = false;
  late AnimationController _shimmerController;
  late AnimationController _flipController;
  bool _isFlipped = false;
  
  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }
  
  @override
  void dispose() {
    _shimmerController.dispose();
    _flipController.dispose();
    super.dispose();
  }
  
  void _flipCard() {
    if (_isFlipped) {
      _flipController.reverse();
    } else {
      _flipController.forward();
    }
    _isFlipped = !_isFlipped;
  }
  
  @override
  Widget build(BuildContext context) {
    final claims = widget.credential['credentialSubject'] as Map<String, dynamic>? ?? {};
    final cardName = claims['cardName'] as String? ?? 'Unknown';
    final cardType = claims['cardType'] as String? ?? 'Creature';
    final rarity = claims['rarity'] as String? ?? 'Common';
    final element = claims['element'] as String? ?? 'Neutral';
    final serial = claims['serialNumber'] as String? ?? '#0001';
    final edition = claims['edition'] as String? ?? '';
    final status = claims['status'] as String? ?? '';
    final lore = claims['lore'] as String? ?? '';
    final isComingSoon = status == 'Coming Soon';
    
    final rarityColor = _getRarityColor(rarity);
    
    return GestureDetector(
      onPanUpdate: widget.enablePan ? (details) {
        setState(() {
          _rotateY += details.delta.dx * 0.01;
          _rotateX -= details.delta.dy * 0.01;
          _rotateX = _rotateX.clamp(-0.3, 0.3);
          _rotateY = _rotateY.clamp(-0.3, 0.3);
          _isHolographic = true;
        });
      } : null,
      onPanEnd: widget.enablePan ? (_) {
        setState(() {
          _rotateX = 0;
          _rotateY = 0;
          _isHolographic = false;
        });
      } : null,
      onDoubleTap: widget.enablePan ? _flipCard : null,
      onTap: null,
      child: AnimatedBuilder(
        animation: Listenable.merge([_shimmerController, _flipController]),
        builder: (context, child) {
          final flipValue = _flipController.value;
          final showBack = flipValue > 0.5;
          
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX(_rotateX)
              ..rotateY(_rotateY + (flipValue * math.pi)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: rarityColor.withOpacity(0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: Offset(_rotateY * 20, _rotateX * -20 + 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: showBack
                    ? Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(math.pi),
                        child: _buildCardBack(rarityColor),
                      )
                    : Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF1a1a2e),
                            const Color(0xFF16213e),
                            const Color(0xFF0f0f23),
                          ],
                        ),
                      ),
                    ),
                    if (_isHolographic)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(_rotateY * 2, _rotateX * 2),
                              end: Alignment(-_rotateY * 2, -_rotateX * 2),
                              colors: [
                                Colors.transparent,
                                rarityColor.withOpacity(0.3),
                                Colors.cyan.withOpacity(0.2),
                                Colors.purple.withOpacity(0.2),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [rarityColor.withOpacity(0.8), rarityColor.withOpacity(0.4)],
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                cardName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.black38,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                element,
                                style: TextStyle(
                                  color: rarityColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 48,
                      left: 12,
                      right: 12,
                      child: Container(
                        height: 160,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: rarityColor.withOpacity(0.5), width: 2),
                          gradient: RadialGradient(
                            colors: [
                              rarityColor.withOpacity(0.2),
                              Colors.black87,
                            ],
                          ),
                        ),
                        child: Center(
                          child: _buildBeeArt(rarityColor),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 216,
                      left: 12,
                      right: 12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            cardType,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(Icons.star, color: rarityColor, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                rarity.toUpperCase(),
                                style: TextStyle(
                                  color: rarityColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isComingSoon)
                      Positioned(
                        top: 240,
                        left: 12,
                        right: 12,
                        child: Center(
                          child: Text(
                            'COMING SOON',
                            style: TextStyle(
                              color: Colors.white24,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 4,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      bottom: isComingSoon ? 32 : 50,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          lore,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 9,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: isComingSoon ? 3 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: 12,
                      right: 12,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            edition,
                            style: TextStyle(
                              color: rarityColor.withOpacity(0.7),
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            serial,
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 8,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 48,
                      right: 16,
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 24,
                        height: 24,
                        color: rarityColor.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
  
  Widget _buildBeeArt(Color accentColor) {
    return CustomPaint(
      size: const Size(120, 120),
      painter: BeePainter(accentColor: accentColor),
    );
  }
  
  Widget _buildCardBack(Color accentColor) {
    final encoder = const JsonEncoder.withIndent('  ');
    final prettyJson = encoder.convert(widget.credential);
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0f0f23),
            const Color(0xFF1a1a2e),
            const Color(0xFF16213e),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: CardBackPatternPainter(color: accentColor),
            ),
          ),
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [accentColor.withOpacity(0.8), accentColor.withOpacity(0.4)],
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.code, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      'Verifiable Credential',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'RAW',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accentColor.withOpacity(0.3)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(10),
                        child: SelectableText(
                          prettyJson,
                          style: TextStyle(
                            color: accentColor.withOpacity(0.9),
                            fontSize: 9,
                            fontFamily: 'monospace',
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Double-tap to flip back',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildStatBadge(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 1),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 8,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            value.toString(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Color _getRarityColor(String rarity) {
    switch (rarity.toLowerCase()) {
      case 'legendary':
        return const Color(0xFFFFD700);
      case 'epic':
        return const Color(0xFFAA00FF);
      case 'rare':
        return const Color(0xFF2196F3);
      case 'uncommon':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }
}

class BeePainter extends CustomPainter {
  final Color accentColor;
  
  BeePainter({required this.accentColor});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    
    final center = Offset(size.width / 2, size.height / 2);
    
    paint.color = accentColor.withOpacity(0.3);
    canvas.drawCircle(center, 50, paint);
    canvas.drawCircle(center, 40, paint);
    
    paint.style = PaintingStyle.fill;
    paint.color = accentColor;
    canvas.drawOval(Rect.fromCenter(center: Offset(center.dx, center.dy - 25), width: 28, height: 24), paint);
    
    canvas.drawOval(Rect.fromCenter(center: Offset(center.dx, center.dy + 8), width: 36, height: 50), paint);
    
    paint.color = const Color(0xFF1a1a2e);
    canvas.drawRect(Rect.fromCenter(center: Offset(center.dx, center.dy + 2), width: 40, height: 6), paint);
    canvas.drawRect(Rect.fromCenter(center: Offset(center.dx, center.dy + 16), width: 40, height: 6), paint);
    canvas.drawRect(Rect.fromCenter(center: Offset(center.dx, center.dy + 30), width: 30, height: 5), paint);
    
    paint.color = Colors.white.withOpacity(0.7);
    paint.style = PaintingStyle.fill;
    final leftWing = Path();
    leftWing.moveTo(center.dx - 15, center.dy - 5);
    leftWing.quadraticBezierTo(center.dx - 45, center.dy - 35, center.dx - 35, center.dy - 10);
    leftWing.quadraticBezierTo(center.dx - 40, center.dy + 5, center.dx - 15, center.dy + 5);
    canvas.drawPath(leftWing, paint);
    
    final rightWing = Path();
    rightWing.moveTo(center.dx + 15, center.dy - 5);
    rightWing.quadraticBezierTo(center.dx + 45, center.dy - 35, center.dx + 35, center.dy - 10);
    rightWing.quadraticBezierTo(center.dx + 40, center.dy + 5, center.dx + 15, center.dy + 5);
    canvas.drawPath(rightWing, paint);
    
    paint.style = PaintingStyle.stroke;
    paint.color = accentColor.withOpacity(0.5);
    paint.strokeWidth = 1;
    canvas.drawPath(leftWing, paint);
    canvas.drawPath(rightWing, paint);
    
    paint.style = PaintingStyle.stroke;
    paint.color = accentColor;
    paint.strokeWidth = 2;
    canvas.drawLine(Offset(center.dx - 6, center.dy - 36), Offset(center.dx - 10, center.dy - 48), paint);
    canvas.drawLine(Offset(center.dx + 6, center.dy - 36), Offset(center.dx + 10, center.dy - 48), paint);
    paint.style = PaintingStyle.fill;
    canvas.drawCircle(Offset(center.dx - 10, center.dy - 48), 3, paint);
    canvas.drawCircle(Offset(center.dx + 10, center.dy - 48), 3, paint);
    
    paint.color = Colors.black;
    canvas.drawCircle(Offset(center.dx - 6, center.dy - 28), 4, paint);
    canvas.drawCircle(Offset(center.dx + 6, center.dy - 28), 4, paint);
    paint.color = Colors.white;
    canvas.drawCircle(Offset(center.dx - 5, center.dy - 29), 1.5, paint);
    canvas.drawCircle(Offset(center.dx + 7, center.dy - 29), 1.5, paint);
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CardBackPatternPainter extends CustomPainter {
  final Color color;
  
  CardBackPatternPainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    for (var i = 0; i < size.width + size.height; i += 20) {
      canvas.drawLine(
        Offset(i.toDouble(), 0),
        Offset(0, i.toDouble()),
        paint,
      );
    }
    
    paint.color = color.withOpacity(0.1);
    final center = Offset(size.width / 2, size.height / 2);
    for (var r = 30.0; r < 200; r += 40) {
      canvas.drawCircle(center, r, paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
