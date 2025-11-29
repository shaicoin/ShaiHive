import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class HeaderStorage {
  HeaderStorage._(this._file, this.headerLength);

  final File _file;
  final int headerLength;
  RandomAccessFile? _raf;

  static Future<HeaderStorage> create(int headerLength) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/headers.bin');
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return HeaderStorage._(file, headerLength);
  }

  Future<int> getHeaderCount() async {
    if (!await _file.exists()) return 0;
    final length = await _file.length();
    return length ~/ headerLength;
  }

  Future<Uint8List?> readHeader(int index) async {
    if (index < 0) return null;
    final offset = index * headerLength;
    final fileLength = await _file.length();
    if (offset + headerLength > fileLength) return null;

    _raf ??= await _file.open(mode: FileMode.read);
    await _raf!.setPosition(offset);
    final bytes = await _raf!.read(headerLength);
    if (bytes.length != headerLength) return null;
    return Uint8List.fromList(bytes);
  }

  Future<List<Uint8List>> readHeaders(int startIndex, int count) async {
    if (startIndex < 0 || count <= 0) return [];
    final offset = startIndex * headerLength;
    final fileLength = await _file.length();
    final available = (fileLength - offset) ~/ headerLength;
    final toRead = count < available ? count : available;
    if (toRead <= 0) return [];

    _raf ??= await _file.open(mode: FileMode.read);
    await _raf!.setPosition(offset);
    final bytes = await _raf!.read(toRead * headerLength);

    final records = <Uint8List>[];
    for (var i = 0; i < toRead; i++) {
      final start = i * headerLength;
      records.add(Uint8List.fromList(bytes.sublist(start, start + headerLength)));
    }
    return records;
  }

  Future<void> append(Uint8List headerBytes) async {
    if (headerBytes.length != headerLength) {
      throw ArgumentError('Invalid header length: ${headerBytes.length}');
    }
    await _closeRaf();
    final sink = _file.openWrite(mode: FileMode.append);
    sink.add(headerBytes);
    await sink.close();
  }

  Future<void> appendBatch(List<Uint8List> headers) async {
    if (headers.isEmpty) return;
    await _closeRaf();
    final sink = _file.openWrite(mode: FileMode.append);
    for (final header in headers) {
      if (header.length != headerLength) {
        throw ArgumentError('Invalid header length: ${header.length}');
      }
      sink.add(header);
    }
    await sink.close();
  }

  Future<void> reset() async {
    await _closeRaf();
    if (await _file.exists()) {
      await _file.writeAsBytes([]);
    }
  }

  Future<void> truncate(int headerCount) async {
    if (headerCount < 0) return;
    await _closeRaf();
    final raf = await _file.open(mode: FileMode.writeOnly);
    await raf.truncate(headerCount * headerLength);
    await raf.close();
  }

  Future<void> _closeRaf() async {
    if (_raf != null) {
      await _raf!.close();
      _raf = null;
    }
  }

  Future<void> dispose() async {
    await _closeRaf();
  }
}
