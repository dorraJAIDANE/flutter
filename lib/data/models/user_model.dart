import 'store_model.dart';

class CollaborationModel {
  const CollaborationModel({
    required this.storeId,
    required this.storeName,
    required this.accepted,
    this.roleName,
  });

  final int storeId;
  final String storeName;
  final bool accepted;
  final String? roleName;

  factory CollaborationModel.fromJson(Map<String, dynamic> json) {
    return CollaborationModel(
      storeId: (json['storeId'] as num?)?.toInt() ?? 0,
      storeName: (json['storeName'] ?? 'Boutique').toString(),
      accepted: json['accepted'] == true,
      roleName: json['roleName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'storeId': storeId,
      'storeName': storeName,
      'accepted': accepted,
      if (roleName != null) 'roleName': roleName,
    };
  }
}

class XfyUser {
  const XfyUser({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.language = 'fr',
    this.token,
    this.stores = const [],
    this.collaborations = const [],
  });

  final int id;
  final String username;
  final String email;
  final String role;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;
  final String language;
  final String? token;
  final List<StoreModel> stores;
  final List<CollaborationModel> collaborations;

  /// Mapping exact Web XFY (`profile-settings.component.ts`) :
  /// Prénom affiché dans l'UI = colonne DB `username`
  String get uiFirstName => username.trim();

  /// Mapping exact Web XFY (`profile-settings.component.ts`) :
  /// Nom affiché dans l'UI = colonne DB `firstName` (ou `lastName` si présent)
  String get uiLastName => (firstName ?? lastName ?? '').trim();

  String get displayName {
    final first = uiFirstName;
    final last = uiLastName;
    if (first.isNotEmpty && last.isNotEmpty && first.toLowerCase() != last.toLowerCase()) {
      return '$first $last';
    }
    if (first.isNotEmpty) return first;
    if (last.isNotEmpty) return last;
    return email;
  }

  String get initials {
    final first = uiFirstName;
    final last = uiLastName;
    if (first.isNotEmpty && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    }
    final name = displayName.trim();
    if (name.isEmpty) return 'X';
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  XfyUser copyWith({
    int? id,
    String? username,
    String? email,
    String? role,
    String? firstName,
    String? lastName,
    String? phoneNumber,
    String? language,
    String? token,
    List<StoreModel>? stores,
    List<CollaborationModel>? collaborations,
  }) {
    return XfyUser(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      role: role ?? this.role,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      language: language ?? this.language,
      token: token ?? this.token,
      stores: stores ?? this.stores,
      collaborations: collaborations ?? this.collaborations,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'role': role,
      if (firstName != null) 'firstName': firstName,
      if (lastName != null) 'lastName': lastName,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      'language': language,
      if (token != null) 'token': token,
      'stores': stores.map((s) => {'id': s.id, 'name': s.name}).toList(),
      'collaborations': collaborations.map((c) => c.toJson()).toList(),
    };
  }

  factory XfyUser.fromJson(Map<String, dynamic> json) {
    final rawStores = json['stores'];
    final stores = rawStores is List
        ? rawStores
            .whereType<Map<String, dynamic>>()
            .map(StoreModel.fromJson)
            .toList()
        : <StoreModel>[];

    final rawCollabs = json['collaborations'];
    final collabs = rawCollabs is List
        ? rawCollabs
            .whereType<Map<String, dynamic>>()
            .map(CollaborationModel.fromJson)
            .toList()
        : <CollaborationModel>[];

    return XfyUser(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: (json['username'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      role: (json['role'] ?? 'SELLER').toString(),
      firstName: json['firstName']?.toString(),
      lastName: json['lastName']?.toString(),
      phoneNumber: (json['phoneNumber'] ?? json['phone'])?.toString(),
      language: (json['language'] ?? 'fr').toString(),
      token: json['token']?.toString(),
      stores: stores,
      collaborations: collabs,
    );
  }
}
