class ClientModel {
  const ClientModel({
    required this.id,
    required this.nom,
    this.email,
    this.numeroTelephone,
    this.numeroTelephone2,
    this.adresse,
  });

  final int id;
  final String nom;
  final String? email;
  final String? numeroTelephone;
  final String? numeroTelephone2;
  final String? adresse;

  String get initials {
    final parts = nom.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'C';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  factory ClientModel.fromJson(Map<String, dynamic> json) {
    return ClientModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      nom: (json['nom'] ?? 'Client').toString(),
      email: json['email']?.toString(),
      numeroTelephone: (json['numeroTelephone'] ?? json['phoneNumber'])?.toString(),
      numeroTelephone2: json['numeroTelephone2']?.toString(),
      adresse: json['adresse']?.toString(),
    );
  }
}
