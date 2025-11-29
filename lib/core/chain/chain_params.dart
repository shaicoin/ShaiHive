import 'dart:typed_data';

abstract class ChainParams {
  String get name;
  int get magicBytes;
  int get defaultP2pPort;
  int get defaultRpcPort;
  int get headerLengthBytes;
  int get targetBlockSpacing;
  String get genesisHashHex;
  int get pubKeyAddressPrefix;
  int get scriptAddressPrefix;
  int get secretKeyPrefix;
  Uint8List get extPublicKeyPrefix;
  Uint8List get extSecretKeyPrefix;
  String get bech32Hrp;
  int get coinType;
}

class ShaicoinMainnetParams implements ChainParams {
  @override
  String get name => 'Shaicoin Mainnet';

  @override
  int get magicBytes => 0xd17cbee4;

  @override
  int get defaultP2pPort => 42069;

  @override
  int get defaultRpcPort => 42068;

  @override
  int get headerLengthBytes => 4096;

  @override
  int get targetBlockSpacing => 120;

  @override
  String get genesisHashHex =>
      '0019592cd5c0ef222adcaa85d4000602636a05e57b3541a844a90644815cacbb';

  @override
  int get pubKeyAddressPrefix => 137;

  @override
  int get scriptAddressPrefix => 135;

  @override
  int get secretKeyPrefix => 117;

  @override
  Uint8List get extPublicKeyPrefix => Uint8List.fromList([0x04, 0x88, 0xB2, 0x1E]);

  @override
  Uint8List get extSecretKeyPrefix => Uint8List.fromList([0x04, 0x88, 0xAD, 0xE4]);

  @override
  String get bech32Hrp => 'sh';

  @override
  int get coinType => 0;
}


