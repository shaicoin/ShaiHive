import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;

class Bip32Node {
  final Uint8List privateKey;
  final Uint8List publicKey;
  final Uint8List chainCode;
  final int depth;
  final int childNumber;
  final Uint8List fingerprint;

  Bip32Node({
    required this.privateKey,
    required this.publicKey,
    required this.chainCode,
    required this.depth,
    required this.childNumber,
    required this.fingerprint,
  });

  static Bip32Node fromSeed(Uint8List seed) {
    final hmacSha512 = Hmac(sha512, utf8.encode('Bitcoin seed'));
    final i = hmacSha512.convert(seed).bytes;

    final privateKey = Uint8List.fromList(i.sublist(0, 32));
    final chainCode = Uint8List.fromList(i.sublist(32, 64));

    final domainParams = pc.ECDomainParameters('secp256k1');
    final privKeyBigInt = _bytesToBigInt(privateKey);
    final publicPoint = domainParams.G * privKeyBigInt;
    final publicKey = publicPoint!.getEncoded(true);

    return Bip32Node(
      privateKey: privateKey,
      publicKey: publicKey,
      chainCode: chainCode,
      depth: 0,
      childNumber: 0,
      fingerprint: Uint8List(4),
    );
  }

  Bip32Node derive(int index) {
    final bool hardened = index >= 0x80000000;
    
    final data = <int>[];
    if (hardened) {
      data.add(0x00);
      data.addAll(privateKey);
    } else {
      data.addAll(publicKey);
    }
    
    data.add((index >> 24) & 0xff);
    data.add((index >> 16) & 0xff);
    data.add((index >> 8) & 0xff);
    data.add(index & 0xff);

    final hmacSha512 = Hmac(sha512, chainCode);
    final i = hmacSha512.convert(data).bytes;

    final il = Uint8List.fromList(i.sublist(0, 32));
    final newChainCode = Uint8List.fromList(i.sublist(32, 64));

    final ilBigInt = _bytesToBigInt(il);
    final privKeyBigInt = _bytesToBigInt(privateKey);
    
    final curve = pc.ECCurve_secp256k1();
    final n = curve.n;
    
    final newPrivKeyBigInt = (ilBigInt + privKeyBigInt) % n;
    final newPrivateKey = _bigIntToBytes(newPrivKeyBigInt, 32);

    final domainParams = pc.ECDomainParameters('secp256k1');
    final publicPoint = domainParams.G * newPrivKeyBigInt;
    final newPublicKey = publicPoint!.getEncoded(true);

    final parentFingerprint = _hash160(publicKey).sublist(0, 4);

    return Bip32Node(
      privateKey: newPrivateKey,
      publicKey: newPublicKey,
      chainCode: newChainCode,
      depth: depth + 1,
      childNumber: index,
      fingerprint: parentFingerprint,
    );
  }

  Bip32Node derivePath(String path) {
    if (!path.startsWith('m/') && !path.startsWith('M/')) {
      throw ArgumentError('Invalid path: must start with m/ or M/');
    }

    final segments = path.substring(2).split('/');
    var node = this;

    for (final segment in segments) {
      if (segment.isEmpty) continue;
      
      final hardened = segment.endsWith("'") || segment.endsWith('h');
      final indexStr = hardened ? segment.substring(0, segment.length - 1) : segment;
      var index = int.parse(indexStr);
      
      if (hardened) {
        index += 0x80000000;
      }
      
      node = node.derive(index);
    }

    return node;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    var result = BigInt.zero;
    for (var i = 0; i < bytes.length; i++) {
      result = (result << 8) | BigInt.from(bytes[i]);
    }
    return result;
  }

  static Uint8List _bigIntToBytes(BigInt number, int length) {
    final bytes = <int>[];
    var value = number;
    while (value > BigInt.zero) {
      bytes.insert(0, (value & BigInt.from(0xff)).toInt());
      value = value >> 8;
    }
    while (bytes.length < length) {
      bytes.insert(0, 0);
    }
    return Uint8List.fromList(bytes.sublist(bytes.length - length));
  }

  static Uint8List _hash160(Uint8List data) {
    final sha256Hash = sha256.convert(data);
    return Uint8List.fromList(
      pc.RIPEMD160Digest().process(Uint8List.fromList(sha256Hash.bytes)),
    );
  }
}

