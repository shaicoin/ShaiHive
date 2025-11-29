import 'dart:typed_data';

class BinaryUtils {
  static int readUint32LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static int readUint64LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24) |
        (data[offset + 4] << 32) |
        (data[offset + 5] << 40) |
        (data[offset + 6] << 48) |
        (data[offset + 7] << 56);
  }

  static void writeUint32LE(List<int> buffer, int value) {
    buffer.add(value & 0xff);
    buffer.add((value >> 8) & 0xff);
    buffer.add((value >> 16) & 0xff);
    buffer.add((value >> 24) & 0xff);
  }

  static void writeUint64LE(List<int> buffer, int value) {
    buffer.add(value & 0xff);
    buffer.add((value >> 8) & 0xff);
    buffer.add((value >> 16) & 0xff);
    buffer.add((value >> 24) & 0xff);
    buffer.add((value >> 32) & 0xff);
    buffer.add((value >> 40) & 0xff);
    buffer.add((value >> 48) & 0xff);
    buffer.add((value >> 56) & 0xff);
  }

  static VarIntResult readVarInt(Uint8List data, int offset) {
    if (offset >= data.length) {
      return VarIntResult(value: 0, bytesRead: 0);
    }

    final first = data[offset];

    if (first < 0xfd) {
      return VarIntResult(value: first, bytesRead: 1);
    } else if (first == 0xfd) {
      if (offset + 2 >= data.length) {
        return VarIntResult(value: 0, bytesRead: 0);
      }
      final value = data[offset + 1] | (data[offset + 2] << 8);
      return VarIntResult(value: value, bytesRead: 3);
    } else if (first == 0xfe) {
      if (offset + 4 >= data.length) {
        return VarIntResult(value: 0, bytesRead: 0);
      }
      final value = readUint32LE(data, offset + 1);
      return VarIntResult(value: value, bytesRead: 5);
    } else {
      if (offset + 8 >= data.length) {
        return VarIntResult(value: 0, bytesRead: 0);
      }
      final value = readUint64LE(data, offset + 1);
      return VarIntResult(value: value, bytesRead: 9);
    }
  }

  static void writeVarInt(List<int> buffer, int value) {
    if (value < 0xfd) {
      buffer.add(value);
    } else if (value <= 0xffff) {
      buffer.add(0xfd);
      buffer.add(value & 0xff);
      buffer.add((value >> 8) & 0xff);
    } else if (value <= 0xffffffff) {
      buffer.add(0xfe);
      buffer.addAll([
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ]);
    } else {
      buffer.add(0xff);
      buffer.addAll([
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
        (value >> 32) & 0xff,
        (value >> 40) & 0xff,
        (value >> 48) & 0xff,
        (value >> 56) & 0xff,
      ]);
    }
  }

  static bool compareBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static String bytesToHex(Uint8List bytes) {
    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Uint8List hexToBytes(String hex) {
    final clean = hex.startsWith('0x') ? hex.substring(2) : hex;
    final result = Uint8List(clean.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}

class VarIntResult {
  final int value;
  final int bytesRead;

  VarIntResult({required this.value, required this.bytesRead});

  int get newOffset => bytesRead;
}

