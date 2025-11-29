import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' show Random;
import 'package:flutter/services.dart' show rootBundle;
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:bs58check/bs58check.dart' as bs58check;
import 'package:bech32/bech32.dart';
import '../core/crypto/bip44.dart';
import '../core/chain/chain_params.dart';

class WalletService {
  // Your custom network parameters
  static const int PUBKEY_ADDRESS = 137;
  static const int SCRIPT_ADDRESS = 135;
  static const int SECRET_KEY = 117;
  static final List<int> EXT_PUBLIC_KEY = [0x04, 0x88, 0xB2, 0x1E];
  static final List<int> EXT_SECRET_KEY = [0x04, 0x88, 0xAD, 0xE4];
  static const String BECH32_HRP = "sh";

  List<String>? _wordList;
  final Random _random = Random.secure();

  Future<List<String>> _loadWordList() async {
    if (_wordList != null) return _wordList!;

    final String words = await rootBundle.loadString('lib/bip39/english.txt');
    _wordList = words.split('\n');
    return _wordList!;
  }

  // Generate a new mnemonic (seed phrase)
  Future<String> generateMnemonic() async {
    try {
      // Generate 16 bytes (128 bits) of random data for a 12-word mnemonic
      final entropy = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        entropy[i] = _random.nextInt(256);
      }

      final checksumLength = entropy.length ~/ 4; // 4 bits for 16 bytes
      final checksum = sha256.convert(entropy).bytes[0] >> (8 - checksumLength);

      // Combine entropy and checksum bits
      final entropyBits = _bytesToBinary(entropy);
      final checksumBits = checksum.toRadixString(2).padLeft(4, '0');
      final bits = entropyBits + checksumBits;

      final wordList = await _loadWordList();

      final words = <String>[];

      // Split bits into 11-bit chunks and convert to words
      for (var i = 0; i < bits.length; i += 11) {
        if (i + 11 > bits.length) {
          throw Exception('Not enough bits for complete word');
        }
        final chunk = bits.substring(i, i + 11);
        final index = int.parse(chunk, radix: 2);

        if (index >= wordList.length) {
          throw Exception(
              'Invalid index generated: $index (from bits: $chunk)');
        }
        words.add(wordList[index]);
      }

      final result = words.join(' ');
      return result;
    } catch (e) {
      rethrow;
    }
  }

  // Convert bytes to binary string
  String _bytesToBinary(List<int> bytes) {
    return bytes.map((byte) => byte.toRadixString(2).padLeft(8, '0')).join();
  }

  // Generate address from public key
  String generateAddress(Uint8List publicKey) {
    final sha256Hash = sha256.convert(publicKey);
    final ripemd160Hash =
        pc.RIPEMD160Digest().process(Uint8List.fromList(sha256Hash.bytes));

    final versionedPayload = Uint8List(21);
    versionedPayload[0] = PUBKEY_ADDRESS;
    versionedPayload.setRange(1, 21, ripemd160Hash);

    return bs58check.encode(versionedPayload);
  }

  // Generate legacy address (P2PKH)
  String generateLegacyAddress(Uint8List publicKey) {
    final sha256Hash = sha256.convert(publicKey);
    final pubKeyHash =
        pc.RIPEMD160Digest().process(Uint8List.fromList(sha256Hash.bytes));

    final versionedPayload = Uint8List(21);
    versionedPayload[0] = PUBKEY_ADDRESS;
    versionedPayload.setRange(1, 21, pubKeyHash);

    return bs58check.encode(versionedPayload);
  }

  // Generate P2SH-SegWit address
  String generateP2SHSegWitAddress(Uint8List publicKey) {
    // First create the P2WPKH script
    final sha256Hash = sha256.convert(publicKey);
    final pubKeyHash =
        pc.RIPEMD160Digest().process(Uint8List.fromList(sha256Hash.bytes));

    // Create P2WPKH redeem script: OP_0 + 0x14 (20 bytes push) + pubKeyHash
    final redeemScript = Uint8List(22);
    redeemScript[0] = 0x00; // SegWit version 0
    redeemScript[1] = 0x14; // Push 20 bytes
    redeemScript.setRange(2, 22, pubKeyHash);

    // Hash the redeem script
    final scriptHash = pc.RIPEMD160Digest()
        .process(Uint8List.fromList(sha256.convert(redeemScript).bytes));

    // Create P2SH address with custom prefix
    final versionedPayload = Uint8List(21);
    versionedPayload[0] = SCRIPT_ADDRESS;
    versionedPayload.setRange(1, 21, scriptHash);

    return bs58check.encode(versionedPayload);
  }

  // Generate Native SegWit address (bech32)
  String generateNativeSegWitAddress(Uint8List publicKey) {
    // Hash the public key first to get 20 bytes
    final sha256Hash = sha256.convert(publicKey);
    final pubKeyHash =
        pc.RIPEMD160Digest().process(Uint8List.fromList(sha256Hash.bytes));

    // Convert to 5-bit words for bech32
    final program = convertBits(pubKeyHash, 8, 5, true);

    // Create bech32 address with witness version 0
    final data = [0, ...program]; // Witness version 0 for P2WPKH
    return bech32.encode(
      Bech32(BECH32_HRP, data),
    );
  }

  // Generate Taproot address (bech32m)
  String generateTaprootAddress(Uint8List publicKey) {
    // For Taproot, we need x-only pubkey (32 bytes)
    // If compressed (33 bytes), remove the prefix byte
    // If uncompressed (65 bytes), get x coordinate
    Uint8List xOnlyPubKey;

    if (publicKey.length == 33) {
      // Compressed public key, just remove the prefix byte
      xOnlyPubKey = publicKey.sublist(1);
    } else if (publicKey.length == 65) {
      // Uncompressed public key, take x coordinate
      xOnlyPubKey = publicKey.sublist(1, 33);
    } else {
      throw Exception('Invalid public key length: ${publicKey.length}');
    }

    // Convert to 5-bit words for bech32m
    final program = convertBits(xOnlyPubKey, 8, 5, true);

    // Create bech32m address with witness version 1
    final data = [1, ...program]; // Witness version 1 for P2TR
    return bech32.encode(Bech32(BECH32_HRP, data));
  }

  // Helper function to convert between bit lengths
  List<int> convertBits(List<int> data, int fromBits, int toBits, bool pad) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;

    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        throw Exception('Invalid value for conversion');
      }
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      throw Exception('Invalid padding');
    }

    return result;
  }

  // Create wallet from mnemonic
  Future<Map<String, dynamic>> createWalletFromMnemonic(String mnemonic) async {
    if (!await _validateMnemonic(mnemonic)) {
      throw Exception('Invalid mnemonic');
    }

    final seed = await _mnemonicToSeed(mnemonic);
    final chainParams = ShaicoinMainnetParams();
    final hdWallet = Bip44Wallet.fromSeed(seed, chainParams.coinType);
    
    final addressNode = hdWallet.getReceiveAddress(0, 0);
    final publicKey = addressNode.publicKey;
    final privateKey = addressNode.privateKey;

    return {
      'legacy_address': generateLegacyAddress(publicKey),
      'p2sh_segwit_address': generateP2SHSegWitAddress(publicKey),
      'native_segwit_address': generateNativeSegWitAddress(publicKey),
      'taproot_address': generateTaprootAddress(publicKey),
      'privateKey': base64.encode(privateKey),
      'publicKey': base64.encode(publicKey),
      'mnemonic': mnemonic,
      'seed': base64.encode(seed),
    };
  }

  // Validate mnemonic
  Future<bool> _validateMnemonic(String mnemonic) async {
    final words = mnemonic.split(' ');
    if (words.length != 12 && words.length != 24) return false;

    final wordList = await _loadWordList();
    return words.every((word) => wordList.contains(word));
  }

  // Convert mnemonic to seed
  Future<Uint8List> _mnemonicToSeed(String mnemonic,
      {String passphrase = ''}) async {
    final salt = utf8.encode('mnemonic$passphrase');
    final keyDerivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA512Digest(), 128))
      ..init(pc.Pbkdf2Parameters(Uint8List.fromList(salt), 2048, 64));

    return keyDerivator.process(Uint8List.fromList(utf8.encode(mnemonic)));
  }

  // Convert BigInt to bytes
  List<int> _bigIntToBytes(BigInt number) {
    var hexString = number.toRadixString(16);
    if (hexString.length % 2 != 0) {
      hexString = '0$hexString';
    }
    var bytes = <int>[];
    for (var i = 0; i < hexString.length; i += 2) {
      bytes.add(int.parse(hexString.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
