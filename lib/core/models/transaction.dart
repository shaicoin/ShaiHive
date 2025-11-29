import 'dart:typed_data';

class TransactionInput {
  final String txid;
  final int vout;
  final Uint8List? scriptSig;
  final int sequence;
  final List<Uint8List>? witness;
  final int value;
  final String? address;

  static const int rbfSequence = 0xfffffffd;
  static const int finalSequence = 0xffffffff;

  TransactionInput({
    required this.txid,
    required this.vout,
    this.scriptSig,
    this.sequence = rbfSequence,
    this.witness,
    this.value = 0,
    this.address,
  });

  TransactionInput copyWith({
    String? txid,
    int? vout,
    Uint8List? scriptSig,
    int? sequence,
    List<Uint8List>? witness,
    int? value,
    String? address,
  }) {
    return TransactionInput(
      txid: txid ?? this.txid,
      vout: vout ?? this.vout,
      scriptSig: scriptSig ?? this.scriptSig,
      sequence: sequence ?? this.sequence,
      witness: witness ?? this.witness,
      value: value ?? this.value,
      address: address ?? this.address,
    );
  }
}

class TransactionOutput {
  final int value;
  final Uint8List scriptPubKey;

  TransactionOutput({
    required this.value,
    required this.scriptPubKey,
  });
}

class Transaction {
  final int version;
  final List<TransactionInput> inputs;
  final List<TransactionOutput> outputs;
  final int locktime;
  final bool hasWitness;

  Transaction({
    required this.version,
    required this.inputs,
    required this.outputs,
    this.locktime = 0,
    this.hasWitness = false,
  });

  Uint8List serialize() {
    final buffer = <int>[];
    
    _writeUint32(buffer, version);
    
    if (hasWitness) {
      buffer.add(0x00);
      buffer.add(0x01);
    }
    
    _writeVarInt(buffer, inputs.length);
    for (final input in inputs) {
      final txidBytes = _hexToBytes(input.txid).reversed.toList();
      buffer.addAll(txidBytes);
      _writeUint32(buffer, input.vout);
      
      if (input.scriptSig != null) {
        _writeVarInt(buffer, input.scriptSig!.length);
        buffer.addAll(input.scriptSig!);
      } else {
        _writeVarInt(buffer, 0);
      }
      
      _writeUint32(buffer, input.sequence);
    }
    
    _writeVarInt(buffer, outputs.length);
    for (final output in outputs) {
      _writeUint64(buffer, output.value);
      _writeVarInt(buffer, output.scriptPubKey.length);
      buffer.addAll(output.scriptPubKey);
    }
    
    if (hasWitness) {
      for (final input in inputs) {
        if (input.witness != null) {
          _writeVarInt(buffer, input.witness!.length);
          for (final item in input.witness!) {
            _writeVarInt(buffer, item.length);
            buffer.addAll(item);
          }
        } else {
          _writeVarInt(buffer, 0);
        }
      }
    }
    
    _writeUint32(buffer, locktime);
    
    return Uint8List.fromList(buffer);
  }

  static void _writeUint32(List<int> buffer, int value) {
    buffer.add(value & 0xff);
    buffer.add((value >> 8) & 0xff);
    buffer.add((value >> 16) & 0xff);
    buffer.add((value >> 24) & 0xff);
  }

  static void _writeUint64(List<int> buffer, int value) {
    buffer.add(value & 0xff);
    buffer.add((value >> 8) & 0xff);
    buffer.add((value >> 16) & 0xff);
    buffer.add((value >> 24) & 0xff);
    buffer.add((value >> 32) & 0xff);
    buffer.add((value >> 40) & 0xff);
    buffer.add((value >> 48) & 0xff);
    buffer.add((value >> 56) & 0xff);
  }

  static void _writeVarInt(List<int> buffer, int value) {
    if (value < 0xfd) {
      buffer.add(value);
    } else if (value <= 0xffff) {
      buffer.add(0xfd);
      buffer.add(value & 0xff);
      buffer.add((value >> 8) & 0xff);
    } else if (value <= 0xffffffff) {
      buffer.add(0xfe);
      _writeUint32(buffer, value);
    } else {
      buffer.add(0xff);
      _writeUint64(buffer, value);
    }
  }

  static Uint8List _hexToBytes(String hex) {
    final result = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  String toHex() {
    final bytes = serialize();
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}


