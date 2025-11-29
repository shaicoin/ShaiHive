import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' as pc;
import 'package:pointycastle/src/utils.dart' as pc_utils;

class VerifiableCredentialService {
  String generateDID(String address) {
    return 'did:$address';
  }

  // Create a verifiable credential
  Map<String, dynamic> createVerifiableCredential({
    required String did,
    required String type,
    required Map<String, dynamic> claims,
    required Uint8List privateKey,
  }) {
    final issuanceDate = DateTime.now().toIso8601String();
    
    final credential = {
      '@context': [
        'https://www.w3.org/2018/credentials/v1',
        'https://www.w3.org/2018/credentials/examples/v1'
      ],
      'type': ['VerifiableCredential', type],
      'issuer': did,
      'issuanceDate': issuanceDate,
      'credentialSubject': {
        'id': did,
        ...claims,
      }
    };

    // Sign the credential
    final signature = _signCredential(credential, privateKey);
    credential['proof'] = {
      'type': 'EcdsaSecp256k1Signature2019',
      'created': issuanceDate,
      'verificationMethod': '$did#keys-1',
      'proofPurpose': 'assertionMethod',
      'proofValue': base64Encode(signature),
    };

    return credential;
  }

  // Verify a credential
  bool verifyCredential(Map<String, dynamic> credential, Uint8List publicKey) {
    try {
      final proof = credential.remove('proof');
      if (proof == null) return false;

      final signature = base64Decode(proof['proofValue']);
      final message = jsonEncode(credential);

      return _verifySignature(
        message: Uint8List.fromList(utf8.encode(message)),
        signature: signature,
        publicKey: publicKey,
      );
    } catch (e) {
      return false;
    }
  }

  // Sign a credential using the private key
  Uint8List _signCredential(Map<String, dynamic> credential, Uint8List privateKey) {
    final message = jsonEncode(credential);
    final signer = pc.ECDSASigner(pc.SHA256Digest(), pc.HMac(pc.SHA256Digest(), 64));
    
    final privKey = pc.ECPrivateKey(
      pc_utils.decodeBigInt(privateKey),
      pc.ECDomainParameters('secp256k1'),
    );
    
    signer.init(true, pc.PrivateKeyParameter(privKey));
    final signature = signer.generateSignature(Uint8List.fromList(utf8.encode(message))) as pc.ECSignature;
    
    final r = pc_utils.encodeBigInt(signature.r);
    final s = pc_utils.encodeBigInt(signature.s);
    return Uint8List.fromList([...r, ...s]);
  }

  // Verify a signature
  bool _verifySignature({
    required Uint8List message,
    required Uint8List signature,
    required Uint8List publicKey,
  }) {
    try {
      final verifier = pc.ECDSASigner(pc.SHA256Digest(), pc.HMac(pc.SHA256Digest(), 64));
      
      final pubKey = pc.ECPublicKey(
        pc.ECCurve_secp256k1().curve.decodePoint(publicKey),
        pc.ECDomainParameters('secp256k1'),
      );
      
      verifier.init(false, pc.PublicKeyParameter(pubKey));
      
      // Split signature into r and s components
      final r = pc_utils.decodeBigInt(signature.sublist(0, 32));
      final s = pc_utils.decodeBigInt(signature.sublist(32));
      
      return verifier.verifySignature(message, pc.ECSignature(r, s));
    } catch (e) {
      return false;
    }
  }
} 