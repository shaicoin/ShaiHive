import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class BlockHeader {
  final int version;
  final Uint8List previousBlockHash;
  final Uint8List merkleRoot;
  final int timestamp;
  final int bits;
  final int nonce;
  final Uint8List vdfSolution; // raw bytes representing uint16 array

  BlockHeader({
    required this.version,
    required this.previousBlockHash,
    required this.merkleRoot,
    required this.timestamp,
    required this.bits,
    required this.nonce,
    required this.vdfSolution,
  });

  static const int _legacyVdfCutover1 = 1723869065;
  static const int _legacyVdfCutover2 = 1726799420;

  static BlockHeader parse(Uint8List data, int headerLength) {
    if (data.length < 80) {
      throw Exception('Invalid header data: too short');
    }

    final buffer = ByteData.sublistView(data);

    final version = buffer.getUint32(0, Endian.little);
    final previousBlockHash = Uint8List.fromList(data.sublist(4, 36));
    final merkleRoot = Uint8List.fromList(data.sublist(36, 68));
    final timestamp = buffer.getUint32(68, Endian.little);
    final bits = buffer.getUint32(72, Endian.little);
    final nonce = buffer.getUint32(76, Endian.little);

    final proofLength = headerLength > 80 ? headerLength - 80 : 0;
    final vdfSolution = proofLength > 0 && data.length >= headerLength
        ? Uint8List.fromList(data.sublist(80, headerLength))
        : Uint8List(proofLength);

    return BlockHeader(
      version: version,
      previousBlockHash: previousBlockHash,
      merkleRoot: merkleRoot,
      timestamp: timestamp,
      bits: bits,
      nonce: nonce,
      vdfSolution: vdfSolution,
    );
  }

  Uint8List serialize() {
    final headerLength = 80 + vdfSolution.length;
    final buffer = Uint8List(headerLength);
    final view = ByteData.sublistView(buffer);

    view.setUint32(0, version, Endian.little);
    buffer.setRange(4, 36, previousBlockHash);
    buffer.setRange(36, 68, merkleRoot);
    view.setUint32(68, timestamp, Endian.little);
    view.setUint32(72, bits, Endian.little);
    view.setUint32(76, nonce, Endian.little);

    if (vdfSolution.isNotEmpty) {
      buffer.setRange(80, headerLength, vdfSolution);
    }

    return buffer;
  }

  Uint8List getHash() {
    if (timestamp <= _legacyVdfCutover1) {
      return _hashBytes(vdfSolution, doubleSha: false);
    } else if (timestamp <= _legacyVdfCutover2) {
      return _hashBytes(serialize(), doubleSha: true);
    }
    return _hashBytes(serialize(), doubleSha: false);
  }

  Uint8List _hashBytes(
    Uint8List data, {
    required bool doubleSha,
  }) {
    final first = sha256.convert(data).bytes;
    final result = doubleSha ? sha256.convert(first).bytes : first;
    return Uint8List.fromList(result);
  }

  String getHashHex() {
    final hash = getHash();
    final reversed = Uint8List.fromList(hash.reversed.toList());
    return reversed.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}


