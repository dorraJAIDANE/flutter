import '../../core/constants/api_constants.dart';

class ProductVariantModel {
  const ProductVariantModel({
    required this.id,
    required this.price,
    required this.stock,
    this.variantName,
    this.sku,
    this.option1,
    this.option2,
    this.option3,
    this.imageUrl,
    this.produitId,
    this.afficherRuptureStockZero = false,
  });

  /// ID brut renvoyé par le backend (`ProduitVariantDTO.id` est un `String`, ex: `"42"` ou `"prod-15"`).
  final String id;
  final double price;
  final int stock;
  final String? variantName;
  final String? sku;
  final String? option1;
  final String? option2;
  final String? option3;
  final String? imageUrl;
  final int? produitId;
  final bool afficherRuptureStockZero;

  bool get isSimpleProductRow => id.startsWith('prod-');

  String get label {
    if (variantName != null &&
        variantName!.trim().isNotEmpty &&
        variantName!.trim().toLowerCase() != 'null') {
      return variantName!.trim();
    }
    final opts = [option1, option2, option3]
        .where((e) => e != null && e.trim().isNotEmpty && e.trim() != 'null')
        .map((e) => e!.trim())
        .toList();
    return opts.isEmpty ? 'Variante #$id' : opts.join(' / ');
  }

  String? get resolvedImageUrl => ApiConstants.resolveImageUrl(imageUrl);

  ProductVariantModel copyWith({int? stock}) => ProductVariantModel(
        id: id,
        price: price,
        stock: stock ?? this.stock,
        variantName: variantName,
        sku: sku,
        option1: option1,
        option2: option2,
        option3: option3,
        imageUrl: imageUrl,
        produitId: produitId,
        afficherRuptureStockZero: afficherRuptureStockZero,
      );

  static double _parseDouble(dynamic v) {
    if (v == null || v is bool) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  static int? _parseNullableInt(dynamic v) {
    if (v == null || v is bool) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  factory ProductVariantModel.fromJson(Map<String, dynamic> json) {
    final stockVal = _parseNullableInt(json['inStock']) ??
        _parseNullableInt(json['in_stock']) ??
        _parseNullableInt(json['available']) ??
        _parseNullableInt(json['stock']) ??
        0;

    final img = (json['imageUrl'] ??
            json['productImage'] ??
            json['product_image'])
        ?.toString();

    return ProductVariantModel(
      id: (json['id'] ?? '').toString(),
      price: _parseDouble(json['price']),
      stock: stockVal,
      variantName: (json['variantName'] ?? json['variant_name'])?.toString(),
      sku: json['sku']?.toString(),
      option1: json['option1']?.toString(),
      option2: json['option2']?.toString(),
      option3: json['option3']?.toString(),
      imageUrl: img,
      produitId: _parseNullableInt(json['produitId'] ?? json['produit_id']),
      afficherRuptureStockZero: json['afficherRuptureStockZero'] == true ||
          json['afficher_rupture_stock_zero'] == true,
    );
  }
}

class ProductModel {
  const ProductModel({
    required this.id,
    required this.nom,
    required this.price,
    this.compareAtPrice,
    this.sku,
    this.slug,
    this.description,
    this.stock,
    this.imageUrl,
    this.livraisonGratuite = false,
    this.salesCount = 0,
    this.purchasePrice = 0,
    this.packagingCost = 0,
    this.metaAdsCost = 0,
    this.otherCosts = 0,
    this.variants = const [],
  });

  final int id;
  final String nom;
  final double price;
  final double? compareAtPrice;
  final String? sku;
  final String? slug;
  final String? description;
  final int? stock;
  final String? imageUrl;
  final bool livraisonGratuite;
  final int salesCount;
  final double purchasePrice;
  final double packagingCost;
  final double metaAdsCost;
  final double otherCosts;
  final List<ProductVariantModel> variants;

  /// Coût unitaire utilisé dans Analytics Web (`analytics.component.ts:1043`).
  double get analyticsUnitCost =>
      purchasePrice + packagingCost + metaAdsCost + otherCosts;

  String? get resolvedImageUrl => ApiConstants.resolveImageUrl(imageUrl);

  int get totalStock {
    if (variants.isNotEmpty) {
      return variants.fold<int>(0, (sum, v) => sum + v.stock);
    }
    return stock ?? 0;
  }

  bool get isOutOfStock => totalStock <= 0;
  bool get isLowStock => totalStock > 0 && totalStock <= 5;

  ProductModel copyWith({
    int? stock,
    String? imageUrl,
    List<ProductVariantModel>? variants,
  }) =>
      ProductModel(
        id: id,
        nom: nom,
        price: price,
        compareAtPrice: compareAtPrice,
        sku: sku,
        slug: slug,
        description: description,
        stock: stock ?? this.stock,
        imageUrl: imageUrl ?? this.imageUrl,
        livraisonGratuite: livraisonGratuite,
        salesCount: salesCount,
        purchasePrice: purchasePrice,
        packagingCost: packagingCost,
        metaAdsCost: metaAdsCost,
        otherCosts: otherCosts,
        variants: variants ?? this.variants,
      );

  static double _parseDouble(dynamic v) {
    if (v == null || v is bool) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
  }

  static double? _parseNullableDouble(dynamic v) {
    if (v == null || v is bool) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.'));
  }

  static int? _parseNullableInt(dynamic v) {
    if (v == null || v is bool) return null;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    String? thumb = json['imageUrl']?.toString();
    if ((thumb == null || thumb.trim().isEmpty || thumb == 'null') &&
        json['images'] is List) {
      final imgs = json['images'] as List;
      for (final item in imgs) {
        if (item is String && item.trim().isNotEmpty && item != 'null') {
          thumb = item.trim();
          break;
        }
        if (item is Map) {
          final url = (item['imageUrl'] ?? item['url'])?.toString();
          if (url != null && url.trim().isNotEmpty && url != 'null') {
            thumb = url.trim();
            break;
          }
        }
      }
    }

    final rawVariants = json['variants'];
    final variants = <ProductVariantModel>[];
    if (rawVariants is List) {
      for (final item in rawVariants) {
        if (item is Map) {
          variants.add(
            ProductVariantModel.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    // Fallback image depuis la première variante si le produit n'a pas d'image directe
    if ((thumb == null || thumb.trim().isEmpty || thumb == 'null') &&
        variants.isNotEmpty) {
      for (final v in variants) {
        if (v.imageUrl != null && v.imageUrl!.trim().isNotEmpty) {
          thumb = v.imageUrl;
          break;
        }
      }
    }

    return ProductModel(
      id: _parseNullableInt(json['id']) ?? 0,
      nom: (json['nom'] ?? json['productName'] ?? 'Produit').toString(),
      price: _parseDouble(json['price']),
      compareAtPrice: _parseNullableDouble(json['compareAtPrice']),
      sku: json['sku']?.toString(),
      slug: json['slug']?.toString(),
      description: json['description']?.toString(),
      stock: _parseNullableInt(json['stock'] ?? json['inStock'] ?? json['available']),
      imageUrl: thumb,
      livraisonGratuite: json['livraisonGratuite'] == true,
      salesCount: _parseNullableInt(json['salesCount']) ?? 0,
      purchasePrice: _parseDouble(json['purchasePrice']),
      packagingCost: _parseDouble(json['packagingCost']),
      metaAdsCost: _parseDouble(json['metaAdsCost']),
      otherCosts: _parseDouble(json['otherCosts']),
      variants: variants,
    );
  }
}
