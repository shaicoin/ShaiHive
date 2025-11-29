class Utxo {
  final String txid;
  final int vout;
  final int value;
  final String? scriptPubKey;
  final String? address;
  int? blockHeight;
  bool confirmed;
  bool frozen;

  Utxo({
    required this.txid,
    required this.vout,
    required this.value,
    this.scriptPubKey,
    this.address,
    this.blockHeight,
    this.confirmed = true,
    this.frozen = false,
  });

  factory Utxo.fromJson(Map<String, dynamic> json) {
    return Utxo(
      txid: json['txid'] as String,
      vout: json['vout'] as int,
      value: json['value'] as int,
      scriptPubKey: json['scriptPubKey'] as String?,
      address: json['address'] as String?,
      blockHeight: json['blockHeight'] as int? ?? json['height'] as int?,
      confirmed: json['confirmed'] as bool? ?? true,
      frozen: json['frozen'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'txid': txid,
      'vout': vout,
      'value': value,
      'scriptPubKey': scriptPubKey,
      'address': address,
      'blockHeight': blockHeight,
      'confirmed': confirmed,
      'frozen': frozen,
    };
  }

  String get outpoint => '$txid:$vout';

  bool get isSpendable => confirmed && !frozen;
}

