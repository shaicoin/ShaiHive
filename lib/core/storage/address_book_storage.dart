import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';

class AddressBookStorage {
  static const _keyPrefix = 'address_book_v1_';

  Future<Map<AddressType, int>> load(String walletId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_keyPrefix$walletId');
    if (raw == null) {
      return {};
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final result = <AddressType, int>{};
    decoded.forEach((key, value) {
      final index = int.tryParse(key);
      if (index == null) {
        return;
      }
      if (index < 0 || index >= AddressType.values.length) {
        return;
      }
      final parsedValue = value is int ? value : int.tryParse('$value');
      if (parsedValue == null) {
        return;
      }
      result[AddressType.values[index]] = parsedValue;
    });
    return result;
  }

  Future<void> save(String walletId, Map<AddressType, int> highestIndices) async {
    final prefs = await SharedPreferences.getInstance();
    final serialized = <String, int>{};
    highestIndices.forEach((type, value) {
      serialized['${type.index}'] = value;
    });
    await prefs.setString('$_keyPrefix$walletId', jsonEncode(serialized));
  }
}


