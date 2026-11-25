import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';
import '../models/client_model.dart';
import '../models/daily_budget_model.dart';
import '../models/order_model.dart';
import '../models/product_model.dart';
import '../models/stats_model.dart';
import '../models/store_model.dart';
import '../models/store_settings_model.dart';
import '../models/user_model.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class SmsVerificationRequiredException extends ApiException {
  SmsVerificationRequiredException({
    required this.email,
    required this.phoneNumber,
  }) : super('Vérification SMS requise', statusCode: 403);

  final String email;
  final String phoneNumber;
}

class XfyApiService {
  XfyApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _token;

  String? get currentToken => _token;

  void setToken(String? token) {
    _token = token;
  }

  Map<String, String> _headers({bool jsonBody = true}) {
    return {
      'Accept': 'application/json',
      if (jsonBody) 'Content-Type': 'application/json',
      if (_token != null && _token!.isNotEmpty) 'Authorization': 'Bearer $_token',
    };
  }

  dynamic _decodeBody(http.Response res) {
    if (res.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return utf8.decode(res.bodyBytes);
    }
  }

  String _extractErrorMessage(http.Response res, dynamic decoded) {
    if (decoded is Map) {
      final msg = decoded['message'] ?? decoded['error'];
      if (msg != null && msg.toString().trim().isNotEmpty) {
        return msg.toString();
      }
    }
    if (decoded is String && decoded.trim().isNotEmpty && decoded.length < 200) {
      return decoded.trim();
    }
    if (res.statusCode == 401) {
      return 'Session expirée. Veuillez vous reconnecter.';
    }
    if (res.statusCode == 403) {
      return 'Accès refusé.';
    }
    return 'Erreur serveur (${res.statusCode}). Veuillez réessayer.';
  }

  Future<dynamic> _get(String path) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final res = await _client
        .get(uri, headers: _headers(jsonBody: false))
        .timeout(const Duration(seconds: 25));
    final decoded = _decodeBody(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded;
    }
    throw ApiException(_extractErrorMessage(res, decoded), statusCode: res.statusCode);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final res = await _client
        .post(uri, headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 25));
    final decoded = _decodeBody(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded;
    }
    if (res.statusCode == 403 &&
        decoded is Map &&
        decoded['requiresSmsVerification'] == true) {
      throw SmsVerificationRequiredException(
        email: (decoded['email'] ?? '').toString(),
        phoneNumber: (decoded['phoneNumber'] ?? '').toString(),
      );
    }
    throw ApiException(_extractErrorMessage(res, decoded), statusCode: res.statusCode);
  }

  Future<dynamic> _put(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final res = await _client
        .put(uri, headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 25));
    final decoded = _decodeBody(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded;
    }
    throw ApiException(_extractErrorMessage(res, decoded), statusCode: res.statusCode);
  }

  Future<dynamic> _patch(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final res = await _client
        .patch(uri, headers: _headers(), body: jsonEncode(body))
        .timeout(const Duration(seconds: 25));
    final decoded = _decodeBody(res);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return decoded;
    }
    throw ApiException(_extractErrorMessage(res, decoded), statusCode: res.statusCode);
  }

  Future<void> _delete(String path) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final res = await _client
        .delete(uri, headers: _headers(jsonBody: false))
        .timeout(const Duration(seconds: 25));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return;
    }
    throw ApiException(
      _extractErrorMessage(res, _decodeBody(res)),
      statusCode: res.statusCode,
    );
  }

  // ---------------- AUTH ----------------

  Future<Map<String, dynamic>> signin({
    required String identifier,
    required String password,
  }) async {
    final data = await _post('/auth/signin', {
      'username': identifier.trim(),
      'password': password,
    });
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw ApiException('Réponse de connexion invalide.');
  }

  Future<Map<String, dynamic>> verifySms({
    required String email,
    required String code,
  }) async {
    final data = await _post('/auth/verify-sms', {
      'email': email.trim(),
      'code': code.trim(),
    });
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw ApiException('Code SMS invalide.');
  }

  Future<XfyUser> validateToken() async {
    final data = await _get('/auth/validate-token');
    if (data is Map<String, dynamic>) {
      return XfyUser.fromJson(data);
    }
    throw ApiException('Impossible de valider la session.');
  }

  Future<String> forgotPassword(String email) async {
    final data = await _post('/auth/forgot-password', {
      'email': email.trim().toLowerCase(),
    });
    if (data is Map && data['message'] != null) {
      return data['message'].toString();
    }
    return 'E-mail de réinitialisation envoyé.';
  }

  Future<void> sendSmsCode({
    required String email,
    required String phoneNumber,
  }) async {
    await _post('/auth/send-sms-code', {
      'email': email.trim().toLowerCase(),
      'phoneNumber': phoneNumber.trim(),
    });
  }

  // ---------------- USERS / PROFILE ----------------

  Future<Map<String, dynamic>> getUserById(int userId) async {
    final data = await _get('/users/$userId');
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw ApiException('Impossible de charger les informations du compte.');
  }

  Future<Map<String, dynamic>> updateUser(
    int userId,
    Map<String, dynamic> payload,
  ) async {
    final data = await _put('/users/$userId', payload);
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw ApiException('Impossible de mettre à jour le profil.');
  }

  // ---------------- STORES ----------------

  Future<List<StoreModel>> getUserStores() async {
    final data = await _get('/stores/user');
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(StoreModel.fromJson)
          .toList();
    }
    return [];
  }

  Future<StoreModel> getStoreById(int storeId) async {
    final data = await _get('/stores/$storeId');
    if (data is Map<String, dynamic>) {
      return StoreModel.fromJson(data);
    }
    throw ApiException('Boutique introuvable.');
  }

  // ---------------- STATS ----------------

  Future<StatsModel> getStats(int storeId, String period) async {
    // period: 'day' | 'week' | 'month'
    final data = await _get('/commande/$storeId/$period');
    if (data is Map<String, dynamic>) {
      return StatsModel.fromJson(data);
    }
    return const StatsModel();
  }

  // ---------------- ORDERS ----------------

  Future<List<OrderModel>> getRecentOrders(int storeId) async {
    final data = await _get('/commande/recent/$storeId');
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(OrderModel.fromJson)
          .toList();
    }
    return [];
  }

  /// Décodage UTF-8 + JSON dans un Isolate en arrière-plan pour les grosses réponses
  /// (évite tout gel de l'interface lorsqu'une boutique possède des milliers de commandes).
  Future<dynamic> _getLargeJson(String path) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final res = await _client
        .get(uri, headers: _headers(jsonBody: false))
        .timeout(const Duration(seconds: 25));
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.bodyBytes.isEmpty) return null;
      if (res.bodyBytes.length > 24576) {
        return compute(_decodeJsonBytesInIsolate, res.bodyBytes);
      }
      return _decodeBody(res);
    }
    throw ApiException(
      _extractErrorMessage(res, _decodeBody(res)),
      statusCode: res.statusCode,
    );
  }

  Future<List<OrderModel>> getOrdersByStore(int storeId) async {
    final data = await _getLargeJson('/commande/store/$storeId');
    if (data is List) {
      if (data.length > 120) {
        return compute(_parseOrdersInIsolate, data);
      }
      return _parseOrdersInIsolate(data);
    }
    return [];
  }

  Future<OrderModel> updateOrder(
    OrderModel order, {
    String? newStatus,
    String? newComment,
  }) async {
    final payload = order.toUpdatePayload(
      newStatus: newStatus,
      newComment: newComment,
    );
    final data = await _put('/commande/orders/${order.id}', payload);
    if (data is Map<String, dynamic>) {
      return OrderModel.fromJson(data);
    }
    return order.copyWith(status: newStatus, commentaire: newComment);
  }

  Future<OrderModel> addOrder(int storeId, Map<String, dynamic> payload) async {
    final data = await _post('/commande/addOrder/$storeId', payload);
    if (data is Map<String, dynamic>) {
      return OrderModel.fromJson(data);
    }
    throw ApiException('Impossible de créer la commande.');
  }

  Future<OrderModel> getOrderByIdOrRef(String idOrRef) async {
    final cleaned = Uri.encodeComponent(idOrRef.trim());
    final data = await _get('/commande/getCommandeById/$cleaned');
    if (data is Map<String, dynamic>) {
      return OrderModel.fromJson(data);
    }
    throw ApiException('Commande introuvable.');
  }

  Future<OrderModel> createRetourFromBordereau(String numeroBordereau) async {
    final data = await _post('/commande/createRetour', {
      'numeroBordereau': numeroBordereau.trim(),
    });
    if (data is Map<String, dynamic>) {
      return OrderModel.fromJson(data);
    }
    throw ApiException('Impossible de créer le retour.');
  }

  Future<void> deleteOrder(int orderId) async {
    await _delete('/commande/delete/$orderId');
  }

  Future<List<String>> getDeliveryCompanies(int storeId) async {
    try {
      final data = await _get('/commande/stores/$storeId/delivery-company');
      if (data is Map && data['deliveryCompanies'] is List) {
        return (data['deliveryCompanies'] as List)
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList();
      }
    } catch (_) {
      // optionnel
    }
    return [];
  }

  Future<Map<String, dynamic>> sendOrderToCarrier({
    required int orderId,
    required String carrier,
  }) async {
    final key = carrier.toLowerCase().trim();
    String endpoint;
    if (key.contains('intigo')) {
      endpoint = '/commande/send-to-intigo/$orderId';
    } else if (key.contains('navex')) {
      endpoint = '/commande/send-to-navex/$orderId';
    } else if (key.contains('first')) {
      endpoint = '/commande/send-to-first/$orderId';
    } else if (key.contains('jax')) {
      endpoint = '/commande/send-to-jax/$orderId';
    } else if (key.contains('xdelivery') || key.contains('x-delivery')) {
      endpoint = '/commande/send-to-xdelivery/$orderId';
    } else if (key.contains('cosmos')) {
      endpoint = '/commande/send-to-cosmos/$orderId';
    } else if (key.contains('colissimo')) {
      endpoint = '/commande/send-to-colissimo/$orderId';
    } else if (key.contains('qwikpak')) {
      endpoint = '/commande/send-to-qwikpak/$orderId';
    } else {
      throw ApiException('Transporteur "$carrier" non pris en charge.');
    }

    final data = await _post(endpoint, {});
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {'success': true};
  }

  // ---------------- PRODUCTS & STOCK ----------------

  Future<List<ProductModel>> getProductsByStore(int storeId) async {
    // 1. Charger les produits complets (avecVariants, puis fallback /store/{storeId})
    List<ProductModel> products = [];
    Object? primaryError;
    try {
      final data = await _getLargeJson('/produits/avecVariants/$storeId');
      if (data is List) {
        products = data.length > 40
            ? await compute(_parseProductsInIsolate, data)
            : _parseProductsInIsolate(data);
      }
    } catch (e) {
      primaryError = e;
    }

    if (products.isEmpty) {
      try {
        final fallback = await _getLargeJson('/produits/store/$storeId');
        if (fallback is List) {
          products = fallback.length > 40
              ? await compute(_parseProductsInIsolate, fallback)
              : _parseProductsInIsolate(fallback);
        }
      } catch (e) {
        if (primaryError != null) rethrow;
        rethrow;
      }
    }

    // 2. Enrichir les stocks réels via /produits/store/{storeId}/variants (identique à stock-list Web)
    try {
      final stockData = await _getLargeJson('/produits/store/$storeId/variants');
      if (stockData is List && stockData.isNotEmpty) {
        final stockRows = stockData.length > 60
            ? await compute(_parseVariantsInIsolate, stockData)
            : _parseVariantsInIsolate(stockData);

        if (products.isEmpty) {
          // Construire directement la liste depuis les lignes de stock si /store était vide
          final grouped = <int, List<ProductVariantModel>>{};
          final names = <int, String>{};
          final images = <int, String?>{};
          final prices = <int, double>{};
          for (final row in stockRows) {
            final pid = row.produitId ??
                int.tryParse(row.id.replaceFirst('prod-', '')) ??
                0;
            if (pid <= 0) continue;
            grouped.putIfAbsent(pid, () => []).add(row);
            names.putIfAbsent(
              pid,
              () => row.variantName?.isNotEmpty == true ? row.variantName! : 'Produit #$pid',
            );
            images.putIfAbsent(pid, () => row.imageUrl);
            prices.putIfAbsent(pid, () => row.price);
          }
          products = grouped.entries.map((entry) {
            final rows = entry.value;
            final isSimple = rows.length == 1 && rows.first.isSimpleProductRow;
            return ProductModel(
              id: entry.key,
              nom: names[entry.key] ?? 'Produit #${entry.key}',
              price: prices[entry.key] ?? 0,
              imageUrl: images[entry.key],
              stock: isSimple ? rows.first.stock : null,
              variants: isSimple ? const [] : rows,
            );
          }).toList();
        } else {
          // Fusionner les quantités de stock exactes par produit / variante
          final byProdId = <int, List<ProductVariantModel>>{};
          for (final row in stockRows) {
            final pid = row.produitId ??
                (row.isSimpleProductRow
                    ? int.tryParse(row.id.replaceFirst('prod-', ''))
                    : null);
            if (pid != null && pid > 0) {
              byProdId.putIfAbsent(pid, () => []).add(row);
            }
          }

          products = products.map((p) {
            final rows = byProdId[p.id];
            if (rows == null || rows.isEmpty) return p;
            final simpleRow = rows.where((r) => r.isSimpleProductRow).toList();
            final realVariants = rows.where((r) => !r.isSimpleProductRow).toList();
            if (realVariants.isNotEmpty) {
              return p.copyWith(
                variants: realVariants,
                imageUrl: p.imageUrl ?? realVariants.first.imageUrl,
              );
            }
            if (simpleRow.isNotEmpty) {
              return p.copyWith(
                stock: simpleRow.first.stock,
                imageUrl: p.imageUrl ?? simpleRow.first.imageUrl,
              );
            }
            return p;
          }).toList();
        }
      }
    } catch (_) {
      // L'endpoint principal suffit déjà si /variants n'est pas disponible
    }

    return products;
  }

  Future<void> updateProductStock(int productId, int stock) async {
    await _patch('/produits/$productId/stock', {'stock': stock});
  }

  Future<void> updateVariantStock(String variantId, int stock) async {
    await _patch('/produits/variants/$variantId/stock', {'stock': stock});
  }

  Future<List<DailyBudgetModel>> getDailyBudgetsRange(
    int storeId,
    String startDate,
    String endDate,
  ) async {
    final data = await _get(
      '/produits/daily-budgets/range?storeId=$storeId&startDate=$startDate&endDate=$endDate',
    );
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(DailyBudgetModel.fromJson)
          .toList();
    }
    return [];
  }

  // ---------------- CLIENTS ----------------

  Future<List<ClientModel>> getClientsByStore(int storeId) async {
    final data = await _get('/clients/by-store/$storeId');
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(ClientModel.fromJson)
          .toList();
    }
    return [];
  }

  // ---------------- PARAMÈTRES BOUTIQUE ----------------

  Future<StoreSettingsModel> getStoreSettings(int storeId) async {
    final data = await _get('/parametres/store/$storeId');
    if (data is Map<String, dynamic>) {
      return StoreSettingsModel.fromJson(data, storeId);
    }
    return StoreSettingsModel(storeId: storeId);
  }

  Future<StoreSettingsModel> updateStoreSettings(
    int storeId,
    StoreSettingsModel settings,
  ) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}/parametres/store/$storeId');
    final request = http.MultipartRequest('PUT', uri);
    if (_token != null && _token!.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    request.fields['parametres'] = jsonEncode(settings.toBackendJson());

    final streamed = await request.send().timeout(const Duration(seconds: 25));
    final res = await http.Response.fromStream(streamed);
    final decoded = _decodeBody(res);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (decoded is Map<String, dynamic>) {
        return StoreSettingsModel.fromJson(decoded, storeId);
      }
      return settings;
    }
    throw ApiException(
      _extractErrorMessage(res, decoded),
      statusCode: res.statusCode,
    );
  }

  Future<void> updateStockZeroBehavior(
    int storeId,
    bool afficherRuptureStockZero,
  ) async {
    await _patch('/parametres/store/$storeId/stock-zero-behavior', {
      'afficherRuptureStockZero': afficherRuptureStockZero,
    });
  }
}

// Fonctions top-level exécutées dans un Dart Isolate (zero UI freeze)
dynamic _decodeJsonBytesInIsolate(Uint8List bytes) {
  return jsonDecode(utf8.decode(bytes));
}

List<OrderModel> _parseOrdersInIsolate(List<dynamic> rawList) {
  final list = <OrderModel>[];
  for (final item in rawList) {
    if (item is Map<String, dynamic>) {
      final order = OrderModel.fromJson(item);
      // Pré-chauffer les champs fréquents directement dans l'Isolate
      order.unifiedStatus;
      order.effectiveAnalyticsDate;
      list.add(order);
    } else if (item is Map) {
      final order = OrderModel.fromJson(Map<String, dynamic>.from(item));
      order.unifiedStatus;
      order.effectiveAnalyticsDate;
      list.add(order);
    }
  }
  list.sort((a, b) => b.id.compareTo(a.id));
  return list;
}

List<ProductModel> _parseProductsInIsolate(List<dynamic> rawList) {
  final list = <ProductModel>[];
  for (final item in rawList) {
    if (item is Map<String, dynamic>) {
      list.add(ProductModel.fromJson(item));
    } else if (item is Map) {
      list.add(ProductModel.fromJson(Map<String, dynamic>.from(item)));
    }
  }
  return list;
}

List<ProductVariantModel> _parseVariantsInIsolate(List<dynamic> rawList) {
  final list = <ProductVariantModel>[];
  for (final item in rawList) {
    if (item is Map<String, dynamic>) {
      list.add(ProductVariantModel.fromJson(item));
    } else if (item is Map) {
      list.add(ProductVariantModel.fromJson(Map<String, dynamic>.from(item)));
    }
  }
  return list;
}
