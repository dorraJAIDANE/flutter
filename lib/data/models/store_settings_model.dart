class StoreSettingsModel {
  const StoreSettingsModel({
    this.id,
    required this.storeId,
    this.nomBoutique = '',
    this.telephone1 = '',
    this.telephone2 = '',
    this.adresse = '',
    this.matriculeFiscal = '',
    this.email = '',
    this.logo,
    this.paiementEnLigne = false,
    this.paiementALaLivraison = true,
    this.genererFacture = false,
    this.fraisLivraison = 7,
    this.fraisLivraisonSociete = 7,
    this.fraisRetourSociete = 0,
    this.facebookUrl = '',
    this.instagramUrl = '',
    this.tiktokUrl = '',
    this.youtubeUrl = '',
    this.deviseDefaut = 'TND',
    this.notificationsEmail = false,
    this.notifiedPersons = '',
    this.afficherRuptureStockZero = false,
    this.rawJson = const {},
  });

  final int? id;
  final int storeId;
  final String nomBoutique;
  final String telephone1;
  final String telephone2;
  final String adresse;
  final String matriculeFiscal;
  final String email;
  final String? logo;
  final bool paiementEnLigne;
  final bool paiementALaLivraison;
  final bool genererFacture;
  final double fraisLivraison;
  final double fraisLivraisonSociete;
  final double fraisRetourSociete;
  final String facebookUrl;
  final String instagramUrl;
  final String tiktokUrl;
  final String youtubeUrl;
  final String deviseDefaut;
  final bool notificationsEmail;
  final String notifiedPersons;
  final bool afficherRuptureStockZero;
  final Map<String, dynamic> rawJson;

  StoreSettingsModel copyWith({
    String? nomBoutique,
    String? telephone1,
    String? telephone2,
    String? adresse,
    String? matriculeFiscal,
    String? email,
    bool? paiementEnLigne,
    bool? paiementALaLivraison,
    bool? genererFacture,
    double? fraisLivraison,
    double? fraisLivraisonSociete,
    double? fraisRetourSociete,
    String? facebookUrl,
    String? instagramUrl,
    String? tiktokUrl,
    String? youtubeUrl,
    String? deviseDefaut,
    bool? notificationsEmail,
    String? notifiedPersons,
    bool? afficherRuptureStockZero,
  }) {
    return StoreSettingsModel(
      id: id,
      storeId: storeId,
      nomBoutique: nomBoutique ?? this.nomBoutique,
      telephone1: telephone1 ?? this.telephone1,
      telephone2: telephone2 ?? this.telephone2,
      adresse: adresse ?? this.adresse,
      matriculeFiscal: matriculeFiscal ?? this.matriculeFiscal,
      email: email ?? this.email,
      logo: logo,
      paiementEnLigne: paiementEnLigne ?? this.paiementEnLigne,
      paiementALaLivraison: paiementALaLivraison ?? this.paiementALaLivraison,
      genererFacture: genererFacture ?? this.genererFacture,
      fraisLivraison: fraisLivraison ?? this.fraisLivraison,
      fraisLivraisonSociete: fraisLivraisonSociete ?? this.fraisLivraisonSociete,
      fraisRetourSociete: fraisRetourSociete ?? this.fraisRetourSociete,
      facebookUrl: facebookUrl ?? this.facebookUrl,
      instagramUrl: instagramUrl ?? this.instagramUrl,
      tiktokUrl: tiktokUrl ?? this.tiktokUrl,
      youtubeUrl: youtubeUrl ?? this.youtubeUrl,
      deviseDefaut: deviseDefaut ?? this.deviseDefaut,
      notificationsEmail: notificationsEmail ?? this.notificationsEmail,
      notifiedPersons: notifiedPersons ?? this.notifiedPersons,
      afficherRuptureStockZero:
          afficherRuptureStockZero ?? this.afficherRuptureStockZero,
      rawJson: rawJson,
    );
  }

  /// Payload JSON compatible avec `@RequestPart("parametres")` de ParametresController.java
  Map<String, dynamic> toBackendJson() {
    final map = Map<String, dynamic>.from(rawJson);
    map.remove('store');
    if (id != null) map['id'] = id;
    map['nomBoutique'] = nomBoutique;
    map['telephone1'] = telephone1;
    map['telephone2'] = telephone2;
    map['adresse'] = adresse;
    map['matriculeFiscal'] = matriculeFiscal;
    map['email'] = email;
    map['paiementEnLigne'] = paiementEnLigne;
    map['paiementALaLivraison'] = paiementALaLivraison;
    map['genererFacture'] = genererFacture;
    map['fraisLivraison'] = fraisLivraison;
    map['fraisLivraisonSociete'] = fraisLivraisonSociete;
    map['fraisRetourSociete'] = fraisRetourSociete;
    map['facebookUrl'] = facebookUrl;
    map['instagramUrl'] = instagramUrl;
    map['tiktokUrl'] = tiktokUrl;
    map['youtubeUrl'] = youtubeUrl;
    map['deviseDefaut'] = deviseDefaut.isEmpty ? 'TND' : deviseDefaut;
    map['notificationsEmail'] = notificationsEmail;
    map['notifiedPersons'] = notifiedPersons;
    map['afficherRuptureStockZero'] = afficherRuptureStockZero;
    return map;
  }

  factory StoreSettingsModel.fromJson(Map<String, dynamic> json, int storeId) {
    double toDouble(dynamic v, {double fallback = 0}) {
      if (v == null) return fallback;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(',', '.')) ?? fallback;
    }

    return StoreSettingsModel(
      id: (json['id'] as num?)?.toInt(),
      storeId: storeId,
      nomBoutique: (json['nomBoutique'] ?? '').toString(),
      telephone1: (json['telephone1'] ?? '').toString(),
      telephone2: (json['telephone2'] ?? '').toString(),
      adresse: (json['adresse'] ?? '').toString(),
      matriculeFiscal: (json['matriculeFiscal'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      logo: json['logo']?.toString(),
      paiementEnLigne: json['paiementEnLigne'] == true,
      paiementALaLivraison: json['paiementALaLivraison'] != false,
      genererFacture: json['genererFacture'] == true,
      fraisLivraison: toDouble(json['fraisLivraison'], fallback: 7),
      fraisLivraisonSociete: toDouble(json['fraisLivraisonSociete'], fallback: 7),
      fraisRetourSociete: toDouble(json['fraisRetourSociete'], fallback: 0),
      facebookUrl: (json['facebookUrl'] ?? '').toString(),
      instagramUrl: (json['instagramUrl'] ?? '').toString(),
      tiktokUrl: (json['tiktokUrl'] ?? '').toString(),
      youtubeUrl: (json['youtubeUrl'] ?? '').toString(),
      deviseDefaut: (json['deviseDefaut'] ?? 'TND').toString(),
      notificationsEmail: json['notificationsEmail'] == true,
      notifiedPersons: (json['notifiedPersons'] ?? '').toString(),
      afficherRuptureStockZero: json['afficherRuptureStockZero'] == true,
      rawJson: Map<String, dynamic>.from(json),
    );
  }
}
