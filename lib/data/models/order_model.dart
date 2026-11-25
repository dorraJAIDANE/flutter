import 'dart:math' as math;
import '../../core/utils/formatters.dart';

class OrderLineItem {
  const OrderLineItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  final String name;
  final int quantity;
  final double unitPrice;

  double get lineTotal => unitPrice * quantity;
}

class OrderModel {
  OrderModel({
    required this.id,
    required this.nom,
    required this.phoneNumber,
    required this.status,
    this.storeId,
    this.produit,
    this.quantite,
    this.prix,
    this.total,
    this.manualTotalValue,
    this.fraisLivraison,
    this.adresse,
    this.gouvernorat,
    this.ville,
    this.zone,
    this.commentaire,
    this.numeroBordereau,
    this.statutIntigo,
    this.deliveryCompany,
    this.timestamp,
    this.dateCommande,
    this.createdAt,
    this.dateLivraison,
    this.dateRetour,
    this.datePremierRetour,
    this.dayMonth,
    this.monthYear,
    this.paymentMethod,
    this.paymentStatus,
    this.isNewClient,
    this.clientTotalOrders,
    this.clientDeliveredOrders,
    this.clientReturnedOrders,
    this.clientCancelledOrders,
    this.rawJson = const {},
  });

  static final RegExp _nonNumericRe = RegExp(r'[^0-9.]');
  static final RegExp _nonSignedNumericRe = RegExp(r'[^0-9.-]');

  final int id;
  final int? storeId;
  final String nom;
  final String phoneNumber;
  final String status;
  final String? produit;
  final String? quantite;
  final String? prix;
  final double? total;
  final double? manualTotalValue;
  final double? fraisLivraison;
  final String? adresse;
  final String? gouvernorat;
  final String? ville;
  final String? zone;
  final String? commentaire;
  final String? numeroBordereau;
  final String? statutIntigo;
  final String? deliveryCompany;
  final String? timestamp;
  final String? dateCommande;
  final String? createdAt;
  final String? dateLivraison;
  final String? dateRetour;
  final String? datePremierRetour;
  final String? dayMonth;
  final String? monthYear;
  final String? paymentMethod;
  final String? paymentStatus;
  final bool? isNewClient;
  final int? clientTotalOrders;
  final int? clientDeliveredOrders;
  final int? clientReturnedOrders;
  final int? clientCancelledOrders;
  final Map<String, dynamic> rawJson;

  // Caches mémoïsés O(1) pour éviter de re-parser regex/dates/accents à chaque frame
  String? _cachedNormalizedStatus;
  String? _cachedUnifiedStatus;
  bool _creationDateComputed = false;
  DateTime? _cachedCreationDate;
  bool _analyticsDateComputed = false;
  DateTime? _cachedAnalyticsDate;
  List<OrderLineItem>? _cachedLineItems;
  double? _cachedProductRevenue;
  int? _cachedTotalUnits;
  double? _cachedEffectiveTotal;
  String? _cachedLocationLabel;
  String? _cachedSearchBlob;
  String? _cachedShortDate;

  /// Statut brut normalisé du champ `status`.
  String get normalizedStatus =>
      _cachedNormalizedStatus ??= XfyFormatters.normalizeStatus(status);

  /// Statut unifié multi-transporteurs 100 % IDENTIQUE au Web XFY (`status` + `statutIntigo`).
  String get unifiedStatus => _cachedUnifiedStatus ??=
      XfyFormatters.computeUnifiedStatus(
        status: status,
        statutIntigo: statutIntigo,
      );

  bool get isCancelled => unifiedStatus == 'annulee';
  bool get isReturned => unifiedStatus == 'retournee';
  bool get isDelivered => unifiedStatus == 'encaissee';

  /// Date de référence pour les statistiques/analytics, IDENTIQUE à `getOrderDate()` sur le Web :
  /// 1. Si livrée/encaissée -> `dateLivraison`
  /// 2. Si retournée -> `datePremierRetour` puis `dateRetour`
  /// 3. Sinon -> `timestamp` || `dateCommande` || `created_at` || `createdAt`
  DateTime? get effectiveAnalyticsDate {
    if (_analyticsDateComputed) return _cachedAnalyticsDate;
    _analyticsDateComputed = true;
    final st = unifiedStatus;
    if (st == 'encaissee' && dateLivraison != null && dateLivraison!.isNotEmpty) {
      final parsed = XfyFormatters.parseDateRobust(dateLivraison);
      if (parsed != null) return _cachedAnalyticsDate = parsed;
    }
    if (st == 'retournee') {
      final retCandidate =
          (datePremierRetour != null && datePremierRetour!.trim().isNotEmpty)
              ? datePremierRetour
              : dateRetour;
      if (retCandidate != null && retCandidate.isNotEmpty) {
        final parsed = XfyFormatters.parseDateRobust(retCandidate);
        if (parsed != null) return _cachedAnalyticsDate = parsed;
      }
    }
    return _cachedAnalyticsDate = creationDate;
  }

  /// Date de création (utilisée dans l'onglet Commandes).
  DateTime? get creationDate {
    if (_creationDateComputed) return _cachedCreationDate;
    _creationDateComputed = true;
    for (final candidate in [timestamp, dateCommande, createdAt]) {
      if (candidate != null && candidate.trim().isNotEmpty) {
        final parsed = XfyFormatters.parseDateRobust(candidate);
        if (parsed != null) return _cachedCreationDate = parsed;
      }
    }
    return _cachedCreationDate = XfyFormatters.parseOrderDate(
      dayMonth: dayMonth,
      monthYear: monthYear,
    );
  }

  /// Découpe les commandes multi-produits séparées par `;` exactement comme le Web XFY.
  List<OrderLineItem> get parsedLineItems {
    final existing = _cachedLineItems;
    if (existing != null) return existing;

    final rawProd = produit ?? '';
    if (rawProd.trim().isEmpty) return _cachedLineItems = const [];

    final items = rawProd.split(';');
    final qtys = (quantite ?? '').split(';');
    final prices = (prix ?? '').split(';');
    final result = <OrderLineItem>[];

    for (int i = 0; i < items.length; i++) {
      final name = items[i].trim();
      if (name.isEmpty) continue;
      final qRaw = i < qtys.length ? qtys[i].trim() : '';
      final parsedQ = int.tryParse(qRaw);
      final qty = (parsedQ != null && parsedQ > 0) ? parsedQ : 1;

      final pRaw = i < prices.length ? prices[i] : '0';
      final cleaned = pRaw.replaceAll(',', '.').replaceAll(_nonNumericRe, '');
      final unitPrice = double.tryParse(cleaned) ?? 0;

      result.add(OrderLineItem(name: name, quantity: qty, unitPrice: unitPrice));
    }
    return _cachedLineItems = result;
  }

  /// Revenu produits hors frais de livraison, 100 % IDENTIQUE à `getOrderProductRevenue()` du Web.
  double get productRevenue {
    final existing = _cachedProductRevenue;
    if (existing != null) return existing;

    double sum = 0;
    final items = parsedLineItems;
    if (items.isNotEmpty && (prix ?? '').trim().isNotEmpty) {
      for (final item in items) {
        sum += item.lineTotal;
      }
    }
    if (sum == 0) {
      final grandTotal = (total != null && total! > 0)
          ? total!
          : (manualTotalValue ?? 0);
      final shipping = (fraisLivraison != null && fraisLivraison! > 0)
          ? fraisLivraison!
          : (grandTotal > 0 ? 7.0 : 0.0);
      sum = math.max(0.0, grandTotal - shipping);
    }
    return _cachedProductRevenue = sum;
  }

  int get totalUnitsCount {
    final existing = _cachedTotalUnits;
    if (existing != null) return existing;
    final items = parsedLineItems;
    if (items.isNotEmpty) {
      int sum = 0;
      for (final item in items) {
        sum += item.quantity;
      }
      return _cachedTotalUnits = sum;
    }
    final q = int.tryParse((quantite ?? '').trim());
    return _cachedTotalUnits = (q != null && q > 0) ? q : 1;
  }

  /// Total affiché au client sur la fiche commande (incluant livraison).
  double get effectiveTotal {
    final existing = _cachedEffectiveTotal;
    if (existing != null) return existing;
    if (total != null && total! > 0) return _cachedEffectiveTotal = total!;
    final rev = productRevenue;
    if (rev > 0) return _cachedEffectiveTotal = rev + (fraisLivraison ?? 0);
    final parsedPrix = XfyFormatters.parsePrice(prix);
    if (parsedPrix > 0) return _cachedEffectiveTotal = parsedPrix;
    return _cachedEffectiveTotal = 0;
  }

  String get locationLabel {
    final existing = _cachedLocationLabel;
    if (existing != null) return existing;
    final parts = [gouvernorat, ville, zone]
        .where((e) => e != null && e.trim().isNotEmpty)
        .map((e) => e!.trim())
        .toList();
    if (parts.isNotEmpty) return _cachedLocationLabel = parts.join(' • ');
    if (adresse != null && adresse!.trim().isNotEmpty) {
      return _cachedLocationLabel = adresse!.trim();
    }
    return _cachedLocationLabel = 'Adresse non précisée';
  }

  /// Chaîne concaténée en minuscules pour filtrage O(1) sans allocations répétées.
  String get searchBlob => _cachedSearchBlob ??=
      '$nom $phoneNumber $id ${produit ?? ''} ${numeroBordereau ?? ''} $locationLabel'
          .toLowerCase();

  String get shortDateLabel => _cachedShortDate ??=
      XfyFormatters.formatShortDate(
        timestamp,
        dayMonth: dayMonth,
        monthYear: monthYear,
      );

  bool get hasBordereau =>
      numeroBordereau != null &&
      numeroBordereau!.trim().isNotEmpty &&
      numeroBordereau!.trim().toUpperCase() != 'N/A';

  OrderModel copyWith({
    String? status,
    String? commentaire,
    String? numeroBordereau,
    String? statutIntigo,
    String? deliveryCompany,
  }) {
    final updatedRaw = Map<String, dynamic>.from(rawJson);
    if (status != null) updatedRaw['status'] = status;
    if (commentaire != null) updatedRaw['commentaire'] = commentaire;
    if (numeroBordereau != null) updatedRaw['numeroBordereau'] = numeroBordereau;
    if (statutIntigo != null) updatedRaw['statutIntigo'] = statutIntigo;
    if (deliveryCompany != null) updatedRaw['deliveryCompany'] = deliveryCompany;

    return OrderModel(
      id: id,
      storeId: storeId,
      nom: nom,
      phoneNumber: phoneNumber,
      status: status ?? this.status,
      produit: produit,
      quantite: quantite,
      prix: prix,
      total: total,
      manualTotalValue: manualTotalValue,
      fraisLivraison: fraisLivraison,
      adresse: adresse,
      gouvernorat: gouvernorat,
      ville: ville,
      zone: zone,
      commentaire: commentaire ?? this.commentaire,
      numeroBordereau: numeroBordereau ?? this.numeroBordereau,
      statutIntigo: statutIntigo ?? this.statutIntigo,
      deliveryCompany: deliveryCompany ?? this.deliveryCompany,
      timestamp: timestamp,
      dateCommande: dateCommande,
      createdAt: createdAt,
      dateLivraison: dateLivraison,
      dateRetour: dateRetour,
      datePremierRetour: datePremierRetour,
      dayMonth: dayMonth,
      monthYear: monthYear,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      isNewClient: isNewClient,
      clientTotalOrders: clientTotalOrders,
      clientDeliveredOrders: clientDeliveredOrders,
      clientReturnedOrders: clientReturnedOrders,
      clientCancelledOrders: clientCancelledOrders,
      rawJson: updatedRaw,
    );
  }

  /// Construit un payload JSON propre aligné avec `CommandeService.sanitizeOrderPayload`.
  Map<String, dynamic> toUpdatePayload({String? newStatus, String? newComment}) {
    const allowedStringFields = [
      'nom',
      'adresse',
      'gouvernorat',
      'ville',
      'zone',
      'produit',
      'commentaire',
      'quantite',
      'dateLivraison',
      'dateRetour',
      'datePremierRetour',
      'prix',
      'phoneNumber',
      'envoyerAIntigo',
      'statutIntigo',
      'numeroBordereau',
      'emetteur',
      'monthYear',
      'dayMonth',
      'color',
      'lien',
      'phone2',
      'client_email',
      'description',
      'additionalInfo',
      'image',
      'deliveryCompany',
      'oldBordereau',
      'exchangeComment',
      'reference',
      'paymentMethod',
      'paymentStatus',
    ];

    final payload = <String, dynamic>{'id': id};
    for (final field in allowedStringFields) {
      final val = rawJson[field];
      if (val != null) {
        payload[field] = val.toString();
      }
    }

    payload['status'] = XfyFormatters.normalizeStatus(newStatus ?? status);
    if (newComment != null) {
      payload['commentaire'] = newComment;
    }
    if (total != null) payload['total'] = total;
    if (fraisLivraison != null) payload['fraisLivraison'] = fraisLivraison;
    if (rawJson['manualTotal'] is bool) {
      payload['manualTotal'] = rawJson['manualTotal'];
    }
    if (rawJson['exchange'] is bool) {
      payload['exchange'] = rawJson['exchange'];
    }

    return payload;
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    double? parseNullableDouble(dynamic v) {
      if (v == null || v is bool) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(
        v.toString().replaceAll(',', '.').replaceAll(_nonSignedNumericRe, ''),
      );
    }

    int? parseNullableInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    String? parseDateField(dynamic v) {
      if (v == null) return null;
      if (v is List && v.length >= 3) {
        final y = v[0].toString().padLeft(4, '0');
        final m = v[1].toString().padLeft(2, '0');
        final d = v[2].toString().padLeft(2, '0');
        if (v.length >= 5) {
          final h = v[3].toString().padLeft(2, '0');
          final min = v[4].toString().padLeft(2, '0');
          return '$y-$m-${d}T$h:$min:00';
        }
        return '$y-$m-$d';
      }
      final str = v.toString().trim();
      return str.isEmpty ? null : str;
    }

    // Produit texte ou tableau produits
    String? productLabel = json['produit']?.toString();
    if ((productLabel == null || productLabel.trim().isEmpty) &&
        json['produits'] is List &&
        (json['produits'] as List).isNotEmpty) {
      final names = (json['produits'] as List)
          .whereType<Map>()
          .map((p) => (p['nom'] ?? p['name'] ?? '').toString())
          .where((n) => n.isNotEmpty)
          .toList();
      if (names.isNotEmpty) {
        productLabel = names.join('; ');
      }
    }

    int? parsedStoreId = parseNullableInt(json['storeId']);
    if (parsedStoreId == null && json['store'] is Map) {
      parsedStoreId = parseNullableInt((json['store'] as Map)['id']);
    }

    return OrderModel(
      id: parseNullableInt(json['id']) ?? 0,
      storeId: parsedStoreId,
      nom: (json['nom'] ?? json['client']?['nom'] ?? 'Client').toString(),
      phoneNumber:
          (json['phoneNumber'] ?? json['client']?['numeroTelephone'] ?? '')
              .toString(),
      status: (json['status'] ?? 'en_cours').toString(),
      produit: productLabel,
      quantite: json['quantite']?.toString(),
      prix: json['prix']?.toString(),
      total: parseNullableDouble(json['total']),
      manualTotalValue: parseNullableDouble(json['manualTotal']),
      fraisLivraison:
          parseNullableDouble(json['fraisLivraison'] ?? json['frais_livraison']),
      adresse: json['adresse']?.toString(),
      gouvernorat: json['gouvernorat']?.toString(),
      ville: json['ville']?.toString(),
      zone: json['zone']?.toString(),
      commentaire: json['commentaire']?.toString(),
      numeroBordereau: json['numeroBordereau']?.toString(),
      statutIntigo: json['statutIntigo']?.toString(),
      deliveryCompany: json['deliveryCompany']?.toString(),
      timestamp: parseDateField(json['timestamp']),
      dateCommande: parseDateField(json['dateCommande'] ?? json['date_commande']),
      createdAt: parseDateField(json['created_at'] ?? json['createdAt']),
      dateLivraison: parseDateField(json['dateLivraison']),
      dateRetour: parseDateField(json['dateRetour']),
      datePremierRetour: parseDateField(
        json['datePremierRetour'] ?? json['date_premier_retour'],
      ),
      dayMonth: json['dayMonth']?.toString(),
      monthYear: json['monthYear']?.toString(),
      paymentMethod: json['paymentMethod']?.toString(),
      paymentStatus: json['paymentStatus']?.toString(),
      isNewClient: json['isNewClient'] is bool ? json['isNewClient'] as bool : null,
      clientTotalOrders: parseNullableInt(json['clientTotalOrders']),
      clientDeliveredOrders: parseNullableInt(json['clientDeliveredOrders']),
      clientReturnedOrders: parseNullableInt(json['clientReturnedOrders']),
      clientCancelledOrders: parseNullableInt(json['clientCancelledOrders']),
      rawJson: json,
    );
  }
}
