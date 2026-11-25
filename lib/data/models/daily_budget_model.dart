import '../../core/utils/formatters.dart';

class DailyBudgetModel {
  const DailyBudgetModel({
    this.id,
    required this.productId,
    required this.dateYmd,
    this.purchasePrice = 0,
    this.packagingCost = 0,
    this.metaAdsCost = 0,
    this.otherCosts = 0,
  });

  final int? id;
  final int productId;
  final String dateYmd; // YYYY-MM-DD
  final double purchasePrice;
  final double packagingCost;
  final double metaAdsCost;
  final double otherCosts;

  /// Coût variable unitaire utilisé dans `statistics.component.ts` (hors Meta Ads qui est journalier)
  double get variableUnitCost => purchasePrice + packagingCost + otherCosts;

  factory DailyBudgetModel.fromJson(Map<String, dynamic> json) {
    double toDouble(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0;
    }

    int parseProdId() {
      final direct = json['productId'];
      if (direct is num) return direct.toInt();
      if (direct != null) {
        final p = int.tryParse(direct.toString());
        if (p != null) return p;
      }
      final nested = json['produit'];
      if (nested is Map && nested['id'] != null) {
        return int.tryParse(nested['id'].toString()) ?? 0;
      }
      return 0;
    }

    String parseDateYmd(dynamic raw) {
      if (raw == null) return '';
      if (raw is List && raw.length >= 3) {
        final y = raw[0].toString().padLeft(4, '0');
        final m = raw[1].toString().padLeft(2, '0');
        final d = raw[2].toString().padLeft(2, '0');
        return '$y-$m-$d';
      }
      final parsed = XfyFormatters.parseDateRobust(raw);
      if (parsed != null) return XfyFormatters.toYmd(parsed);
      return '';
    }

    return DailyBudgetModel(
      id: (json['id'] as num?)?.toInt(),
      productId: parseProdId(),
      dateYmd: parseDateYmd(json['date']),
      purchasePrice: toDouble(json['purchasePrice']),
      packagingCost: toDouble(json['packagingCost']),
      metaAdsCost: toDouble(json['metaAdsCost']),
      otherCosts: toDouble(json['otherCosts']),
    );
  }
}
