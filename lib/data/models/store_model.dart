import '../../core/constants/api_constants.dart';

class StoreModel {
  const StoreModel({
    required this.id,
    required this.name,
    this.subdomain,
    this.customDomain,
    this.logoUrl,
    this.description,
    this.active = true,
    this.isPublished = true,
  });

  final int id;
  final String name;
  final String? subdomain;
  final String? customDomain;
  final String? logoUrl;
  final String? description;
  final bool active;
  final bool isPublished;

  String? get resolvedLogoUrl => ApiConstants.resolveImageUrl(logoUrl);

  String? get publicUrl {
    if (customDomain != null && customDomain!.trim().isNotEmpty) {
      return customDomain!.startsWith('http')
          ? customDomain
          : 'https://$customDomain';
    }
    if (subdomain != null && subdomain!.trim().isNotEmpty) {
      final sub = subdomain!.trim();
      if (sub.contains('.')) return 'https://$sub';
      return 'https://$sub.xfy.tn';
    }
    return null;
  }

  factory StoreModel.fromJson(Map<String, dynamic> json) {
    return StoreModel(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: (json['name'] ?? json['storeName'] ?? 'Ma boutique').toString(),
      subdomain: json['subdomain']?.toString(),
      customDomain: json['customDomain']?.toString(),
      logoUrl: (json['logoUrl'] ?? json['logo'])?.toString(),
      description: json['description']?.toString(),
      active: json['active'] != false,
      isPublished: json['isPublished'] != false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (subdomain != null) 'subdomain': subdomain,
      if (customDomain != null) 'customDomain': customDomain,
      if (logoUrl != null) 'logoUrl': logoUrl,
      if (description != null) 'description': description,
      'active': active,
      'isPublished': isPublished,
    };
  }
}
