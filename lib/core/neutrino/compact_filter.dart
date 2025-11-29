import 'dart:typed_data';
import 'package:crypto/crypto.dart';

class CompactFilter {
  final Uint8List filterBytes;
  final int p;
  static const int _m = 784931;
  GolombCodedSet? _decoded;
  int? _n;

  CompactFilter({
    required this.filterBytes,
    this.p = 19,
  });

  bool get hasData => filterBytes.isNotEmpty;

  (int, int) _readN() {
    if (filterBytes.isEmpty) return (0, 0);
    final first = filterBytes[0];
    if (first < 0xfd) {
      return (first, 1);
    } else if (first == 0xfd && filterBytes.length >= 3) {
      return (filterBytes[1] | (filterBytes[2] << 8), 3);
    } else if (first == 0xfe && filterBytes.length >= 5) {
      return (filterBytes[1] | (filterBytes[2] << 8) | (filterBytes[3] << 16) | (filterBytes[4] << 24), 5);
    }
    return (0, 0);
  }

  GolombCodedSet _getDecoded() {
    if (_decoded != null) return _decoded!;
    
    final (n, nBytes) = _readN();
    _n = n;
    
    if (nBytes >= filterBytes.length) {
      _decoded = GolombCodedSet(values: [], p: p);
      return _decoded!;
    }
    
    final golombData = filterBytes.sublist(nBytes);
    _decoded = GolombCodedSet.decode(golombData, p, expectedCount: n);
    return _decoded!;
  }

  bool matches(List<Uint8List> items, Uint8List key) {
    if (items.isEmpty || !hasData) return false;

    final filter = _getDecoded();
    if (filter.isEmpty) return false;

    final n = _n ?? filter.length;
    final f = n * _m;
    if (f == 0) return false;
    
    for (final item in items) {
      final hash = _sipHash(item, key);
      final target = _fastReduce(hash, f);
      if (filter.containsSorted(target)) {
        return true;
      }
    }

    return false;
  }

  static const int _mask64 = 0xFFFFFFFFFFFFFFFF;

  static int _fastReduce(int hash, int n) {
    final hash64 = BigInt.from(hash).toUnsigned(64);
    final product = hash64 * BigInt.from(n);
    return (product >> 64).toInt();
  }

  int _sipHash(Uint8List data, Uint8List key) {
    if (key.length != 16) {
      throw ArgumentError('Key must be 16 bytes');
    }

    var v0 = 0x736f6d6570736575;
    var v1 = 0x646f72616e646f6d;
    var v2 = 0x6c7967656e657261;
    var v3 = 0x7465646279746573;

    final k0 = _readUint64LE(key, 0);
    final k1 = _readUint64LE(key, 8);

    v0 = _xor64(v0, k0);
    v1 = _xor64(v1, k1);
    v2 = _xor64(v2, k0);
    v3 = _xor64(v3, k1);

    void sipRound() {
      v0 = _add64(v0, v1);
      v1 = _rotateLeft(v1, 13);
      v1 = _xor64(v1, v0);
      v0 = _rotateLeft(v0, 32);
      v2 = _add64(v2, v3);
      v3 = _rotateLeft(v3, 16);
      v3 = _xor64(v3, v2);
      v0 = _add64(v0, v3);
      v3 = _rotateLeft(v3, 21);
      v3 = _xor64(v3, v0);
      v2 = _add64(v2, v1);
      v1 = _rotateLeft(v1, 17);
      v1 = _xor64(v1, v2);
      v2 = _rotateLeft(v2, 32);
    }

    var offset = 0;
    while (offset + 8 <= data.length) {
      final m = _readUint64LE(data, offset);
      offset += 8;
      v3 = _xor64(v3, m);
      sipRound();
      sipRound();
      v0 = _xor64(v0, m);
    }

    var b = (data.length & 0xff) << 56;
    var shift = 0;
    while (offset < data.length) {
      b |= (data[offset] & 0xff) << shift;
      offset++;
      shift += 8;
    }

    b &= _mask64;
    v3 = _xor64(v3, b);
    sipRound();
    sipRound();
    v0 = _xor64(v0, b);
    v2 = _xor64(v2, 0xff);
    for (var i = 0; i < 4; i++) {
      sipRound();
    }

    return (v0 ^ v1 ^ v2 ^ v3) & _mask64;
  }

  static int _readUint64LE(Uint8List data, int offset) {
    final low = data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
    final high = data[offset + 4] |
        (data[offset + 5] << 8) |
        (data[offset + 6] << 16) |
        (data[offset + 7] << 24);
    return (low & 0xFFFFFFFF) | ((high & 0xFFFFFFFF) << 32);
  }

  static int _rotateLeft(int value, int shift) {
    return ((value << shift) | (value >>> (64 - shift)));
  }

  static int _add64(int a, int b) {
    return (a + b) & _mask64;
  }

  static int _xor64(int a, int b) {
    return (a ^ b) & _mask64;
  }
}

class GolombCodedSet {
  final List<int> values;
  final int p;

  GolombCodedSet({
    required this.values,
    required this.p,
  });

  bool get isEmpty => values.isEmpty;
  int get length => values.length;

  static GolombCodedSet decode(Uint8List data, int p, {int? expectedCount}) {
    final values = <int>[];
    var bitPos = 0;
    var value = 0;

    final maxCount = expectedCount ?? 10000;
    
    while (bitPos < data.length * 8 && values.length < maxCount) {
      var quotient = 0;
      while (bitPos < data.length * 8 && _readBit(data, bitPos) == 1) {
        quotient++;
        bitPos++;
      }
      if (bitPos >= data.length * 8) break;
      bitPos++;

      var remainder = 0;
      for (var i = 0; i < p; i++) {
        if (bitPos >= data.length * 8) break;
        remainder = (remainder << 1) | _readBit(data, bitPos);
        bitPos++;
      }

      final delta = (quotient << p) + remainder;
      value += delta;
      values.add(value);
    }

    return GolombCodedSet(values: values, p: p);
  }

  bool contains(int target) {
    return values.contains(target);
  }

  bool containsSorted(int target) {
    if (values.isEmpty) return false;
    var low = 0;
    var high = values.length - 1;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final midVal = values[mid];
      if (midVal < target) {
        low = mid + 1;
      } else if (midVal > target) {
        high = mid - 1;
      } else {
        return true;
      }
    }
    return false;
  }

  static int _readBit(Uint8List data, int bitPos) {
    final bytePos = bitPos ~/ 8;
    final bitOffset = 7 - (bitPos % 8);
    if (bytePos >= data.length) return 0;
    return (data[bytePos] >> bitOffset) & 1;
  }
}

class FilterHeader {
  final Uint8List filterHash;
  final Uint8List prevFilterHash;
  final int height;

  FilterHeader({
    required this.filterHash,
    required this.prevFilterHash,
    required this.height,
  });

  Uint8List get hash {
    final combined = <int>[];
    combined.addAll(filterHash);
    combined.addAll(prevFilterHash);
    final result = sha256.convert(combined);
    return Uint8List.fromList(result.bytes);
  }
}


