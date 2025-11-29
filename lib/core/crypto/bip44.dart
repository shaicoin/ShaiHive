import 'dart:typed_data';
import 'dart:math';
import 'package:pointycastle/export.dart' as pc;
import 'bip32.dart';

class Bip44Wallet {
  final Bip32Node masterNode;
  final int coinType;

  Bip44Wallet({
    required this.masterNode,
    required this.coinType,
  });

  static Bip44Wallet fromSeed(Uint8List seed, int coinType) {
    final masterNode = Bip32Node.fromSeed(seed);
    return Bip44Wallet(
      masterNode: masterNode,
      coinType: coinType,
    );
  }

  Bip32Node getAccountNode(int account) {
    return masterNode.derivePath("m/44'/$coinType'/$account'");
  }

  Bip32Node getAddressNode(int account, int chain, int index) {
    return getAccountNode(account).derivePath("m/$chain/$index");
  }

  Bip32Node getReceiveAddress(int account, int index) {
    return getAddressNode(account, 0, index);
  }

  Bip32Node getChangeAddress(int account, int index) {
    return getAddressNode(account, 1, index);
  }

  String getDerivationPath(int account, int chain, int index) {
    return "m/44'/$coinType'/$account'/$chain/$index";
  }
}

class SignatureHelper {
  static final BigInt _curveN = BigInt.parse(
    'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141',
    radix: 16,
  );
  static final BigInt _halfN = _curveN >> 1;

  static Uint8List signTransaction(
    Uint8List messageHash,
    Uint8List privateKey,
  ) {
    final domainParams = pc.ECDomainParameters('secp256k1');
    
    final privKeyBigInt = _bytesToBigInt(privateKey);
    final privKey = pc.ECPrivateKey(privKeyBigInt, domainParams);

    final signer = pc.ECDSASigner(null, pc.HMac(pc.SHA256Digest(), 64));
    final secureRandom = _getSecureRandom();
    
    signer.init(true, pc.ParametersWithRandom(
      pc.PrivateKeyParameter(privKey),
      secureRandom,
    ));

    final signature = signer.generateSignature(messageHash) as pc.ECSignature;
    
    var s = signature.s;
    if (s > _halfN) {
      s = _curveN - s;
    }
    
    return _encodeDER(signature.r, s);
  }

  static Uint8List _encodeDER(BigInt r, BigInt s) {
    final rBytes = _bigIntToBytes(r);
    final sBytes = _bigIntToBytes(s);
    
    final result = <int>[];
    result.add(0x30);
    
    final contentLength = 2 + rBytes.length + 2 + sBytes.length;
    result.add(contentLength);
    
    result.add(0x02);
    result.add(rBytes.length);
    result.addAll(rBytes);
    
    result.add(0x02);
    result.add(sBytes.length);
    result.addAll(sBytes);
    
    return Uint8List.fromList(result);
  }

  static Uint8List _bigIntToBytes(BigInt number) {
    final bytes = <int>[];
    var value = number;
    while (value > BigInt.zero) {
      bytes.insert(0, (value & BigInt.from(0xff)).toInt());
      value = value >> 8;
    }
    
    if (bytes.isNotEmpty && bytes[0] >= 0x80) {
      bytes.insert(0, 0x00);
    }
    
    return Uint8List.fromList(bytes);
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (var i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  static pc.SecureRandom _getSecureRandom() {
    final secureRandom = pc.FortunaRandom();
    final random = Random.secure();
    final seeds = <int>[];
    for (var i = 0; i < 32; i++) {
      seeds.add(random.nextInt(256));
    }
    secureRandom.seed(pc.KeyParameter(Uint8List.fromList(seeds)));
    return secureRandom;
  }
}

