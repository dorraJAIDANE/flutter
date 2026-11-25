import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class TokenStorage {
  static const _tokenKey = 'xfy_jwt_token';
  static const _userKey = 'xfy_user_json';
  static const _storesKey = 'xfy_stores_json';
  static const _storeIdKey = 'xfy_selected_store_id';
  static const _rememberedIdKey = 'xfy_remembered_identifier';
  static const _langKey = 'xfy_app_language';

  Future<List<Map<String, dynamic>>> getCachedStores() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> saveCachedStores(List<Map<String, dynamic>> storesList) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storesKey, jsonEncode(storesList));
  }

  Future<String?> getLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_langKey);
  }

  Future<void> saveLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_langKey, code);
  }

  Future<String?> getRememberedIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_rememberedIdKey);
  }

  Future<void> saveRememberedIdentifier(String? identifier) async {
    final prefs = await SharedPreferences.getInstance();
    if (identifier == null || identifier.trim().isEmpty) {
      await prefs.remove(_rememberedIdKey);
    } else {
      await prefs.setString(_rememberedIdKey, identifier.trim());
    }
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<Map<String, dynamic>?> getCachedUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_userKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveCachedUser(Map<String, dynamic> userMap) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, jsonEncode(userMap));
  }

  Future<int?> getSelectedStoreId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_storeIdKey);
  }

  Future<void> saveSelectedStoreId(int storeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_storeIdKey, storeId);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_storesKey);
    await prefs.remove(_storeIdKey);
  }
}
