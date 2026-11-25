import 'dart:math' as math;
import '../../data/models/daily_budget_model.dart';
import '../../data/models/order_model.dart';
import '../../data/models/product_model.dart';
import '../../data/models/store_settings_model.dart';
import 'formatters.dart';

class PeriodBounds {
  const PeriodBounds({
    required this.start,
    required this.end,
    required this.prevStart,
    required this.prevEnd,
    required this.isAllTime,
  });

  final DateTime start;
  final DateTime end;
  final DateTime prevStart;
  final DateTime prevEnd;
  final bool isAllTime;

  String get startYmd => XfyFormatters.toYmd(start);
  String get endYmd => XfyFormatters.toYmd(end);
  String get prevStartYmd => XfyFormatters.toYmd(prevStart);
  String get prevEndYmd => XfyFormatters.toYmd(prevEnd);
}

class TrendMetric {
  const TrendMetric({required this.percent, required this.isUp});

  final double percent;
  final bool isUp;
}

class DailyChartPoint {
  DailyChartPoint({required this.date});

  final DateTime date;
  double revenue = 0;
  int deliveredOrdersCount = 0;
  int returnedOrdersCount = 0;
  int totalOrdersCount = 0;
}

class VipClientSummary {
  const VipClientSummary({
    required this.name,
    required this.phone,
    required this.totalSpent,
    required this.ordersCount,
  });

  final String name;
  final String phone;
  final double totalSpent;
  final int ordersCount;
}

class XfyComputedDashboard {
  const XfyComputedDashboard({
    required this.bounds,
    required this.periodAllOrders,
    required this.periodNonCancelledOrders,
    required this.deliveredOrders,
    required this.returnedOrders,
    required this.deliveredOrdersCount,
    required this.productsSold,
    required this.totalReturns,
    required this.activeClientsCount,
    required this.revenue,
    required this.avgBasket,
    required this.returnRate,
    required this.returnedAmount,
    required this.analyticsBudget,
    required this.analyticsProfit,
    required this.statisticsBudget,
    required this.statisticsProfit,
    required this.revenueTrend,
    required this.ordersTrend,
    required this.clientsTrend,
    required this.returnRateTrend,
    required this.avgBasketTrend,
    required this.analyticsProfitTrend,
    required this.statisticsProfitTrend,
    required this.dailyPoints,
    required this.topSoldProducts,
    required this.topReturnedProducts,
    required this.topCities,
    required this.vipClients,
    this.statusCounts = const {},
  });

  final PeriodBounds bounds;

  /// Toutes les commandes de la période (y compris annulées) — utile pour la transparence.
  final List<OrderModel> periodAllOrders;

  /// Commandes non-annulées de la période (pour le Donut des statuts).
  final List<OrderModel> periodNonCancelledOrders;

  /// Commandes livrées / encaissées (`unifiedStatus == 'encaissee'`).
  final List<OrderModel> deliveredOrders;

  /// Commandes retournées (`unifiedStatus == 'retournee'`).
  final List<OrderModel> returnedOrders;

  /// KPI exact Web : nombre de commandes livrées/encaissées sur la période.
  final int deliveredOrdersCount;

  /// KPI exact Web Statistiques : unités vendues (livrées/encaissées).
  final int productsSold;

  /// KPI exact Web : nombre de retours.
  final int totalReturns;

  /// KPI exact Web Analytics : clients uniques ayant au moins 1 commande livrée.
  final int activeClientsCount;

  /// KPI exact Web : CA produits + marge livraison sur commandes livrées/encaissées.
  final double revenue;

  /// KPI exact Web Analytics : revenue / deliveredOrdersCount.
  final double avgBasket;

  /// KPI exact Web : totalReturns / (deliveredOrdersCount + totalReturns) * 100.
  final double returnRate;

  /// KPI exact Web Statistiques : totalReturns * fraisRetourSociete.
  final double returnedAmount;

  /// Budget & Profit exacts Web Analytics (`analytics.component.ts`).
  final double analyticsBudget;
  final double analyticsProfit;

  /// Budget & Profit exacts Web Statistiques (`statistics.component.ts` avec daily budgets).
  final double statisticsBudget;
  final double statisticsProfit;

  final TrendMetric revenueTrend;
  final TrendMetric ordersTrend;
  final TrendMetric clientsTrend;
  final TrendMetric returnRateTrend;
  final TrendMetric avgBasketTrend;
  final TrendMetric analyticsProfitTrend;
  final TrendMetric statisticsProfitTrend;

  final List<DailyChartPoint> dailyPoints;
  final List<MapEntry<String, int>> topSoldProducts;
  final List<MapEntry<String, int>> topReturnedProducts;
  final List<MapEntry<String, int>> topCities;
  final List<VipClientSummary> vipClients;
  final Map<String, int> statusCounts;

  List<double> get dailyRevenueSeries =>
      dailyPoints.map((p) => p.revenue).toList();
  List<double> get dailyDeliveredSeries =>
      dailyPoints.map((p) => p.deliveredOrdersCount.toDouble()).toList();
  List<double> get dailyReturnsSeries =>
      dailyPoints.map((p) => p.returnedOrdersCount.toDouble()).toList();
}

/// Moteur de calcul 100 % aligné sur `analytics.component.ts` et `statistics.component.ts`
/// du site Web XFY (statut unifié avec `statutIntigo`, dates `dateLivraison`/`datePremierRetour`,
/// commandes multi-articles `;`, marge de livraison, frais retour société et budgets journaliers).
class XfyStatsEngine {
  XfyStatsEngine._();

  static final RegExp _wsRe = RegExp(r'\s+');

  static PeriodBounds resolveBounds({
    required String preset,
    DateTime? customStart,
    DateTime? customEnd,
    DateTime? nowOverride,
  }) {
    final now = nowOverride ?? DateTime.now();
    DateTime start;
    DateTime end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    DateTime prevStart;
    DateTime prevEnd;
    bool isAllTime = false;

    switch (preset) {
      case 'today':
        start = DateTime(now.year, now.month, now.day, 0, 0, 0);
        prevStart = DateTime(now.year, now.month, now.day - 1, 0, 0, 0);
        prevEnd = DateTime(now.year, now.month, now.day - 1, 23, 59, 59, 999);
        break;
      case 'yesterday':
        start = DateTime(now.year, now.month, now.day - 1, 0, 0, 0);
        end = DateTime(now.year, now.month, now.day - 1, 23, 59, 59, 999);
        prevStart = DateTime(now.year, now.month, now.day - 2, 0, 0, 0);
        prevEnd = DateTime(now.year, now.month, now.day - 2, 23, 59, 59, 999);
        break;
      case '7days':
        // Web : today - 7 jours à 00:00:00 → aujourd'hui 23:59:59
        final s7 = now.subtract(const Duration(days: 7));
        start = DateTime(s7.year, s7.month, s7.day, 0, 0, 0);
        final ps7 = start.subtract(const Duration(days: 7));
        prevStart = DateTime(ps7.year, ps7.month, ps7.day, 0, 0, 0);
        prevEnd = start.subtract(const Duration(milliseconds: 1));
        break;
      case '30days':
        // Web : today - 30 jours à 00:00:00 → aujourd'hui 23:59:59
        final s30 = now.subtract(const Duration(days: 30));
        start = DateTime(s30.year, s30.month, s30.day, 0, 0, 0);
        final ps30 = start.subtract(const Duration(days: 30));
        prevStart = DateTime(ps30.year, ps30.month, ps30.day, 0, 0, 0);
        prevEnd = start.subtract(const Duration(milliseconds: 1));
        break;
      case 'month':
      case 'thismonth':
        start = DateTime(now.year, now.month, 1, 0, 0, 0);
        prevStart = DateTime(now.year, now.month - 1, 1, 0, 0, 0);
        prevEnd = start.subtract(const Duration(milliseconds: 1));
        break;
      case 'thisyear':
        start = DateTime(now.year, 1, 1, 0, 0, 0);
        prevStart = DateTime(now.year - 1, 1, 1, 0, 0, 0);
        prevEnd = start.subtract(const Duration(milliseconds: 1));
        break;
      case 'all':
        isAllTime = true;
        start = DateTime(2020, 1, 1, 0, 0, 0);
        prevStart = DateTime(2015, 1, 1, 0, 0, 0);
        prevEnd = DateTime(2019, 12, 31, 23, 59, 59, 999);
        break;
      case 'custom':
        final cs = customStart ?? now.subtract(const Duration(days: 30));
        final ce = customEnd ?? now;
        start = DateTime(cs.year, cs.month, cs.day, 0, 0, 0);
        end = DateTime(ce.year, ce.month, ce.day, 23, 59, 59, 999);
        if (start.isAfter(end)) {
          final tmp = start;
          start = DateTime(end.year, end.month, end.day, 0, 0, 0);
          end = DateTime(tmp.year, tmp.month, tmp.day, 23, 59, 59, 999);
        }
        final duration = end.difference(start) + const Duration(milliseconds: 1);
        prevStart = start.subtract(duration);
        prevEnd = end.subtract(duration);
        break;
      default:
        final s30 = now.subtract(const Duration(days: 30));
        start = DateTime(s30.year, s30.month, s30.day, 0, 0, 0);
        final ps30 = start.subtract(const Duration(days: 30));
        prevStart = DateTime(ps30.year, ps30.month, ps30.day, 0, 0, 0);
        prevEnd = start.subtract(const Duration(milliseconds: 1));
    }

    return PeriodBounds(
      start: start,
      end: end,
      prevStart: prevStart,
      prevEnd: prevEnd,
      isAllTime: isAllTime,
    );
  }

  static XfyComputedDashboard compute({
    required List<OrderModel> allOrders,
    required List<ProductModel> products,
    required String preset,
    StoreSettingsModel? settings,
    List<DailyBudgetModel> dailyBudgets = const [],
    DateTime? customStart,
    DateTime? customEnd,
    DateTime? nowOverride,
  }) {
    final bounds = resolveBounds(
      preset: preset,
      customStart: customStart,
      customEnd: customEnd,
      nowOverride: nowOverride,
    );

    final fraisLivraisonDefault = settings?.fraisLivraison ?? 7.0;
    final fraisLivraisonSociete = settings?.fraisLivraisonSociete ?? 7.0;
    final fraisRetourSociete = settings?.fraisRetourSociete ?? 0.0;

    // Index O(1) des budgets journaliers : "${productId}_${YYYY-MM-DD}"
    final dailyBudgetMap = <String, DailyBudgetModel>{};
    for (final db in dailyBudgets) {
      if (db.productId > 0 && db.dateYmd.isNotEmpty) {
        dailyBudgetMap['${db.productId}_${db.dateYmd}'] = db;
      }
    }

    // Produits pré-indexés (nom en minuscules + mots découpés 1 seule fois)
    final sortedProducts = List<ProductModel>.from(products)
      ..sort((a, b) => b.nom.length.compareTo(a.nom.length));
    final indexedProducts = <({ProductModel prod, String lower, List<String> words})>[];
    for (final prod in sortedProducts) {
      final lowerProd = prod.nom.toLowerCase().trim();
      if (lowerProd.isEmpty) continue;
      final prodWords =
          lowerProd.split(_wsRe).where((w) => w.length > 1).toList();
      indexedProducts.add((prod: prod, lower: lowerProd, words: prodWords));
    }
    final matchCache = <String, ProductModel?>{};

    ProductModel? findBestProduct(String itemName) {
      final lowerItem = itemName.toLowerCase().trim();
      if (lowerItem.isEmpty || indexedProducts.isEmpty) return null;
      if (matchCache.containsKey(lowerItem)) return matchCache[lowerItem];

      ProductModel? best;
      int highestScore = -1;
      List<String>? itemWords;

      for (final entry in indexedProducts) {
        final lowerProd = entry.lower;
        if (lowerItem.contains(lowerProd) || lowerProd.contains(lowerItem)) {
          final score = lowerProd.length + 100;
          if (score > highestScore) {
            highestScore = score;
            best = entry.prod;
          }
          continue;
        }
        if (highestScore >= 100) continue;
        itemWords ??=
            lowerItem.split(_wsRe).where((w) => w.length > 1).toList();
        int matchedWords = 0;
        for (final w in itemWords) {
          if (entry.words.any((pw) => pw.contains(w) || w.contains(pw))) {
            matchedWords++;
          }
        }
        if (matchedWords > 0 && matchedWords > highestScore) {
          highestScore = matchedWords;
          best = entry.prod;
        }
      }

      matchCache[lowerItem] = best;
      return best;
    }

    bool inRange(DateTime? d, DateTime s, DateTime e) {
      if (d == null) return false;
      return !d.isBefore(s) && !d.isAfter(e);
    }

    final periodAll = <OrderModel>[];
    final periodValid = <OrderModel>[];
    final prevValid = <OrderModel>[];
    final statusCounts = <String, int>{};

    for (final o in allOrders) {
      final d = o.effectiveAnalyticsDate;
      if (bounds.isAllTime) {
        periodAll.add(o);
        final st = o.unifiedStatus;
        statusCounts[st] = (statusCounts[st] ?? 0) + 1;
        if (st != 'annulee') periodValid.add(o);
      } else {
        if (inRange(d, bounds.start, bounds.end)) {
          periodAll.add(o);
          final st = o.unifiedStatus;
          statusCounts[st] = (statusCounts[st] ?? 0) + 1;
          if (st != 'annulee') periodValid.add(o);
        } else if (inRange(d, bounds.prevStart, bounds.prevEnd)) {
          if (!o.isCancelled) prevValid.add(o);
        }
      }
    }

    final delivered = periodValid.where((o) => o.isDelivered).toList();
    final returned = periodValid.where((o) => o.isReturned).toList();
    final prevDelivered = prevValid.where((o) => o.isDelivered).toList();
    final prevReturned = prevValid.where((o) => o.isReturned).toList();

    double calcRevenue(List<OrderModel> ordersList) {
      double sum = 0;
      for (final o in ordersList) {
        final prodRev = o.productRevenue;
        final clientShipping =
            (o.fraisLivraison != null && o.fraisLivraison! > 0)
                ? o.fraisLivraison!
                : fraisLivraisonDefault;
        final effectiveClientShipping =
            math.max(clientShipping, fraisLivraisonDefault);
        final deliveryMargin = effectiveClientShipping - fraisLivraisonSociete;
        sum += prodRev + (deliveryMargin > 0 ? deliveryMargin : 0);
      }
      return sum;
    }

    double calcAnalyticsBudget(
      List<OrderModel> ordersList,
      List<OrderModel> returnsList,
    ) {
      double totalB = 0;
      for (final o in ordersList) {
        for (final item in o.parsedLineItems) {
          final matched = findBestProduct(item.name);
          final unitCost = matched?.analyticsUnitCost ?? 0;
          totalB += unitCost * item.quantity;
        }
      }
      totalB += returnsList.length * fraisRetourSociete;
      return totalB;
    }

    double calcStatisticsBudget(
      List<OrderModel> ordersList,
      List<OrderModel> returnsList,
      String startYmd,
      String endYmd,
    ) {
      double totalB = 0;
      for (final o in ordersList) {
        final d = o.effectiveAnalyticsDate;
        final ymd = d != null ? XfyFormatters.toYmd(d) : '';
        for (final item in o.parsedLineItems) {
          final matched = findBestProduct(item.name);
          if (matched != null && ymd.isNotEmpty) {
            final db = dailyBudgetMap['${matched.id}_$ymd'];
            if (db != null) {
              totalB += db.variableUnitCost * item.quantity;
            }
          }
        }
      }
      // Frais de retour facturés par la société de livraison
      totalB += returnsList.length * fraisRetourSociete;
      // Budget publicitaire Meta Ads compté 1 seule fois par produit et par jour sur la période
      for (final db in dailyBudgets) {
        if (db.dateYmd.isEmpty) continue;
        if (bounds.isAllTime ||
            (db.dateYmd.compareTo(startYmd) >= 0 &&
                db.dateYmd.compareTo(endYmd) <= 0)) {
          totalB += db.metaAdsCost;
        }
      }
      return totalB;
    }

    final revenue = calcRevenue(delivered);
    final prevRevenue = calcRevenue(prevDelivered);

    final analyticsBudget = calcAnalyticsBudget(delivered, returned);
    final prevAnalyticsBudget =
        calcAnalyticsBudget(prevDelivered, prevReturned);
    final analyticsProfit = revenue - analyticsBudget;
    final prevAnalyticsProfit = prevRevenue - prevAnalyticsBudget;

    final statisticsBudget = calcStatisticsBudget(
      delivered,
      returned,
      bounds.startYmd,
      bounds.endYmd,
    );
    final prevStatisticsBudget = calcStatisticsBudget(
      prevDelivered,
      prevReturned,
      bounds.prevStartYmd,
      bounds.prevEndYmd,
    );
    final statisticsProfit = revenue - statisticsBudget;
    final prevStatisticsProfit = prevRevenue - prevStatisticsBudget;

    final ordersCount = delivered.length;
    final prevOrdersCount = prevDelivered.length;

    int productsSold = 0;
    for (final o in delivered) {
      productsSold += o.totalUnitsCount;
    }

    final totalReturns = returned.length;
    final prevReturns = prevReturned.length;
    final returnedAmount = totalReturns * fraisRetourSociete;

    final totalProcessed = ordersCount + totalReturns;
    final returnRate =
        totalProcessed > 0 ? (totalReturns / totalProcessed) * 100.0 : 0.0;
    final prevProcessed = prevOrdersCount + prevReturns;
    final prevReturnRate =
        prevProcessed > 0 ? (prevReturns / prevProcessed) * 100.0 : 0.0;

    final avgBasket = ordersCount > 0 ? revenue / ordersCount : 0.0;
    final prevAvgBasket =
        prevOrdersCount > 0 ? prevRevenue / prevOrdersCount : 0.0;

    String clientIdentity(OrderModel o) {
      final ph = o.phoneNumber.trim();
      return ph.isNotEmpty ? ph : o.nom.trim();
    }

    final activeClientsCount =
        delivered.map(clientIdentity).where((k) => k.isNotEmpty).toSet().length;
    final prevActiveClientsCount = prevDelivered
        .map(clientIdentity)
        .where((k) => k.isNotEmpty)
        .toSet()
        .length;

    TrendMetric trendPct(double current, double previous, {bool lowerIsBetter = false}) {
      if (bounds.isAllTime) return const TrendMetric(percent: 0, isUp: true);
      if (previous == 0) {
        if (current > 0) return TrendMetric(percent: 100, isUp: !lowerIsBetter);
        return const TrendMetric(percent: 0, isUp: true);
      }
      final pct = ((current - previous) / previous) * 100.0;
      return TrendMetric(
        percent: pct.abs(),
        isUp: lowerIsBetter ? pct <= 0 : pct >= 0,
      );
    }

    final returnRateDiff = prevReturnRate > 0 ? returnRate - prevReturnRate : 0.0;
    final returnRateTrend = TrendMetric(
      percent: returnRateDiff.abs(),
      isUp: returnRateDiff <= 0,
    );

    // Agrégations pour graphiques (exactement comme Web : basées sur delivered & returned)
    final dailyMap = <String, DailyChartPoint>{};
    final soldProdCounts = <String, int>{};
    final returnedProdCounts = <String, int>{};
    final cityCounts = <String, int>{};
    final clientSpent =
        <String, ({String name, String phone, double spent, int count})>{};

    // Pré-remplir les jours de la période quand <= 31 jours (courbe fluide sans trous)
    final spanDays = bounds.end.difference(bounds.start).inDays;
    if (!bounds.isAllTime && spanDays >= 0 && spanDays <= 31) {
      var cursor = DateTime(bounds.start.year, bounds.start.month, bounds.start.day);
      final endDay = DateTime(bounds.end.year, bounds.end.month, bounds.end.day);
      while (!cursor.isAfter(endDay)) {
        final key = XfyFormatters.toYmd(cursor);
        dailyMap[key] = DailyChartPoint(date: cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
    }

    for (final o in delivered) {
      final d = o.effectiveAnalyticsDate;
      final prodRev = o.productRevenue;
      if (d != null) {
        final day = DateTime(d.year, d.month, d.day);
        final key = XfyFormatters.toYmd(day);
        final pt = dailyMap.putIfAbsent(key, () => DailyChartPoint(date: day));
        pt.revenue += prodRev;
        pt.deliveredOrdersCount++;
        pt.totalOrdersCount++;
      }

      for (final item in o.parsedLineItems) {
        final matched = findBestProduct(item.name);
        final label = matched?.nom ?? item.name;
        soldProdCounts[label] = (soldProdCounts[label] ?? 0) + item.quantity;
      }

      final gov = (o.gouvernorat?.trim().isNotEmpty == true)
          ? o.gouvernorat!.trim()
          : (o.ville?.trim() ?? '');
      if (gov.isNotEmpty) {
        cityCounts[gov] = (cityCounts[gov] ?? 0) + 1;
      }

      final cKey = (o.phoneNumber.trim().isNotEmpty
              ? XfyFormatters.cleanPhone(o.phoneNumber)
              : o.nom.trim().toLowerCase())
          .trim();
      if (cKey.isNotEmpty) {
        final prev = clientSpent[cKey];
        clientSpent[cKey] = (
          name: o.nom,
          phone: o.phoneNumber,
          spent: (prev?.spent ?? 0) + prodRev,
          count: (prev?.count ?? 0) + 1,
        );
      }
    }

    for (final o in returned) {
      final d = o.effectiveAnalyticsDate;
      if (d != null) {
        final day = DateTime(d.year, d.month, d.day);
        final key = XfyFormatters.toYmd(day);
        final pt = dailyMap.putIfAbsent(key, () => DailyChartPoint(date: day));
        pt.returnedOrdersCount++;
        pt.totalOrdersCount++;
      }

      for (final item in o.parsedLineItems) {
        final matched = findBestProduct(item.name);
        final label = matched?.nom ?? item.name;
        returnedProdCounts[label] =
            (returnedProdCounts[label] ?? 0) + item.quantity;
      }
    }

    final dailyPoints = dailyMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final trimmedDaily = dailyPoints.length > 31
        ? dailyPoints.sublist(dailyPoints.length - 31)
        : dailyPoints;

    List<MapEntry<String, int>> top5(Map<String, int> map) {
      final list = map.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return list.take(5).toList();
    }

    final vip = clientSpent.values
        .map(
          (v) => VipClientSummary(
            name: v.name,
            phone: v.phone,
            totalSpent: v.spent,
            ordersCount: v.count,
          ),
        )
        .toList()
      ..sort((a, b) => b.totalSpent.compareTo(a.totalSpent));

    return XfyComputedDashboard(
      bounds: bounds,
      periodAllOrders: periodAll,
      periodNonCancelledOrders: periodValid,
      deliveredOrders: delivered,
      returnedOrders: returned,
      deliveredOrdersCount: ordersCount,
      productsSold: productsSold,
      totalReturns: totalReturns,
      activeClientsCount: activeClientsCount,
      revenue: revenue,
      avgBasket: avgBasket,
      returnRate: returnRate,
      returnedAmount: returnedAmount,
      analyticsBudget: analyticsBudget,
      analyticsProfit: analyticsProfit,
      statisticsBudget: statisticsBudget,
      statisticsProfit: statisticsProfit,
      revenueTrend: trendPct(revenue, prevRevenue),
      ordersTrend: trendPct(ordersCount.toDouble(), prevOrdersCount.toDouble()),
      clientsTrend: trendPct(
        activeClientsCount.toDouble(),
        prevActiveClientsCount.toDouble(),
      ),
      returnRateTrend: returnRateTrend,
      avgBasketTrend: trendPct(avgBasket, prevAvgBasket),
      analyticsProfitTrend: trendPct(analyticsProfit, prevAnalyticsProfit),
      statisticsProfitTrend: trendPct(statisticsProfit, prevStatisticsProfit),
      dailyPoints: trimmedDaily,
      topSoldProducts: top5(soldProdCounts),
      topReturnedProducts: top5(returnedProdCounts),
      topCities: top5(cityCounts),
      vipClients: vip.take(5).toList(),
      statusCounts: statusCounts,
    );
  }
}
