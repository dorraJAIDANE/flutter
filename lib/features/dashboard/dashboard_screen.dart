import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/xfy_stats_engine.dart';
import '../../data/models/order_model.dart';
import '../../state/app_state.dart';
import '../orders/order_detail_sheet.dart';
import '../widgets/status_badge.dart';
import '../widgets/store_switcher_sheet.dart';

/// Page Accueil — Statistiques & Analytics 100 % alignée mathématiquement et visuellement sur le Web XFY :
/// • Statut unifié multi-transporteurs (`status` + `statutIntigo`)
/// • Dates exactes Web (`dateLivraison` pour encaissées, `datePremierRetour`/`dateRetour` pour retours)
/// • Commandes multi-articles `;`, marge de livraison, frais retour société & budgets journaliers
/// • Deux vues identiques au Web : `Analytics` & `Statistiques` avec graphiques `fl_chart`
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.state});

  final AppState state;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // 0 = Analytics (Web analytics.component), 1 = Statistiques (Web statistics.component)
  int _modeIndex = 0;

  // 'today' | 'yesterday' | '7days' | '30days' | 'thismonth' | 'thisyear' | 'all' | 'custom'
  String _datePreset = '30days';
  DateTimeRange? _customRange;

  // Cache O(1) du calcul dashboard pour éviter de recalculer à chaque frame / switch d'onglet
  String? _cachedStatsKey;
  XfyComputedDashboard? _cachedStats;

  XfyComputedDashboard _getOrComputeDashboard() {
    final s = widget.state;
    final key =
        '${s.ordersVersion}_${s.productsVersion}_${s.settingsVersion}_${s.budgetsVersion}_${_datePreset}_${_customRange?.start.millisecondsSinceEpoch}_${_customRange?.end.millisecondsSinceEpoch}';
    if (_cachedStats != null && _cachedStatsKey == key) {
      return _cachedStats!;
    }
    final computed = XfyStatsEngine.compute(
      allOrders: s.orders,
      products: s.products,
      preset: _datePreset,
      settings: s.storeSettings,
      dailyBudgets: s.dailyBudgets,
      customStart: _customRange?.start,
      customEnd: _customRange?.end,
    );
    _cachedStatsKey = key;
    _cachedStats = computed;
    return computed;
  }

  void _selectPreset(String preset) {
    setState(() => _datePreset = preset);
    final bounds = XfyStatsEngine.resolveBounds(
      preset: preset,
      customStart: _customRange?.start,
      customEnd: _customRange?.end,
    );
    widget.state.loadDailyBudgetsForBounds(bounds);
  }

  Future<void> _pickDateRange() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          ),
      helpText: AppL10n.t('period_picker_help'),
      cancelText: AppL10n.t('cancel'),
      confirmText: AppL10n.t('update'),
      saveText: AppL10n.t('update'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: XfyColors.primaryVibrant,
            onPrimary: Colors.white,
            surface: Colors.white,
            onSurface: XfyColors.ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _datePreset = 'custom';
      });
      final bounds = XfyStatsEngine.resolveBounds(
        preset: 'custom',
        customStart: picked.start,
        customEnd: picked.end,
      );
      widget.state.loadDailyBudgetsForBounds(bounds);
    }
  }

  String get _rangeDisplayLabel {
    switch (_datePreset) {
      case 'today':
        return AppL10n.t('period_today');
      case 'yesterday':
        return AppL10n.t('period_yesterday');
      case '7days':
        return AppL10n.t('period_7days');
      case '30days':
        return AppL10n.t('period_30days');
      case 'thismonth':
        return AppL10n.t('period_month');
      case 'thisyear':
        return AppL10n.t('period_year');
      case 'all':
        return AppL10n.t('period_all_dates');
      case 'custom':
        if (_customRange == null) return AppL10n.t('period_calendar');
        return '${XfyFormatters.formatDayMonthShort(_customRange!.start)} - ${XfyFormatters.formatDayMonthShort(_customRange!.end)}';
      default:
        return AppL10n.t('period_30days');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.state.selectedStore;
    final data = _getOrComputeDashboard();

    return Scaffold(
      backgroundColor: XfyColors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          color: XfyColors.primaryVibrant,
          onRefresh: () => widget.state.refreshAllStoreData(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // 1. Header Web XFY (Carte blanche, icône dégradée Indigo-Violet, Live badge)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: XfyColors.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: XfyColors.border),
                      boxShadow: XfyColors.cardShadow,
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                gradient: XfyColors.statsGradient,
                                borderRadius: BorderRadius.circular(13),
                                boxShadow: [
                                  BoxShadow(
                                    color: XfyColors.primaryVibrant
                                        .withValues(alpha: 0.30),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.bar_chart_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: widget.state.stores.length > 1
                                    ? () => showModalBottomSheet(
                                          context: context,
                                          builder: (_) => StoreSwitcherSheet(
                                            state: widget.state,
                                          ),
                                        )
                                    : null,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          _modeIndex == 0
                                              ? AppL10n.t('analytics')
                                              : AppL10n.t('statistics'),
                                          style: const TextStyle(
                                            fontSize: 17.5,
                                            fontWeight: FontWeight.w900,
                                            color: XfyColors.ink,
                                            letterSpacing: -0.3,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: XfyColors.emeraldSoft,
                                            borderRadius:
                                                BorderRadius.circular(99),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircleAvatar(
                                                radius: 3,
                                                backgroundColor: widget
                                                        .state.isStompConnected
                                                    ? XfyColors.emerald
                                                    : XfyColors.amber,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                widget.state.isStompConnected
                                                    ? 'LIVE'
                                                    : 'SYNC',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w800,
                                                  color: widget
                                                          .state.isStompConnected
                                                      ? XfyColors.emerald
                                                      : XfyColors.amber,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            store?.name ?? AppL10n.t('my_store'),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: XfyColors.inkSecondary,
                                            ),
                                          ),
                                        ),
                                        if (widget.state.stores.length > 1)
                                          const Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            size: 18,
                                            color: XfyColors.primaryVibrant,
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: AppL10n.t('refresh'),
                              style: IconButton.styleFrom(
                                backgroundColor: XfyColors.primarySoft,
                                foregroundColor: XfyColors.primaryVibrant,
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                widget.state.refreshAllStoreData();
                              },
                              icon: const Icon(Icons.refresh_rounded, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Switch Web : Analytics vs Statistiques
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: XfyColors.canvas,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _ModeTabButton(
                                  icon: Icons.insights_rounded,
                                  label: AppL10n.t('analytics'),
                                  selected: _modeIndex == 0,
                                  onTap: () => setState(() => _modeIndex = 0),
                                ),
                              ),
                              Expanded(
                                child: _ModeTabButton(
                                  icon: Icons.analytics_outlined,
                                  label: AppL10n.t('statistics'),
                                  selected: _modeIndex == 1,
                                  onTap: () => setState(() => _modeIndex = 1),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. Filtre de période + Calendrier (identique au Dual-Calendar Web)
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 38,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      _PeriodChip(
                        label: AppL10n.t('period_today'),
                        selected: _datePreset == 'today',
                        onTap: () => _selectPreset('today'),
                      ),
                      _PeriodChip(
                        label: AppL10n.t('period_yesterday'),
                        selected: _datePreset == 'yesterday',
                        onTap: () => _selectPreset('yesterday'),
                      ),
                      _PeriodChip(
                        label: AppL10n.t('period_7days'),
                        selected: _datePreset == '7days',
                        onTap: () => _selectPreset('7days'),
                      ),
                      _PeriodChip(
                        label: AppL10n.t('period_30days'),
                        selected: _datePreset == '30days',
                        onTap: () => _selectPreset('30days'),
                      ),
                      _PeriodChip(
                        label: AppL10n.t('period_month'),
                        selected: _datePreset == 'thismonth',
                        onTap: () => _selectPreset('thismonth'),
                      ),
                      _PeriodChip(
                        label: AppL10n.t('period_year'),
                        selected: _datePreset == 'thisyear',
                        onTap: () => _selectPreset('thisyear'),
                      ),
                      _PeriodChip(
                        label: AppL10n.t('period_all'),
                        selected: _datePreset == 'all',
                        onTap: () => _selectPreset('all'),
                      ),
                      _PeriodChip(
                        label: _datePreset == 'custom'
                            ? _rangeDisplayLabel
                            : AppL10n.t('period_calendar'),
                        icon: Icons.calendar_month_rounded,
                        selected: _datePreset == 'custom',
                        onTap: _pickDateRange,
                      ),
                    ],
                  ),
                ),
              ),

              // Bandeau résumé transparent aligné sur le calcul Web (livrées vs total période)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: XfyColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: XfyColors.primaryVibrant.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: XfyColors.primaryVibrant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            AppL10n.t('stats_summary', {
                              'delivered': '${data.deliveredOrdersCount}',
                              'returns': '${data.totalReturns}',
                              'active': '${data.periodNonCancelledOrders.length}',
                            }),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: XfyColors.primaryDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // 3. Contenu selon la vue choisie : Analytics OU Statistiques
              if (_modeIndex == 0)
                ..._buildAnalyticsSlivers(context, data)
              else
                ..._buildStatisticsSlivers(context, data),

              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== VUE ANALYTICS (100 % alignée sur analytics.component.ts) ====================
  List<Widget> _buildAnalyticsSlivers(
    BuildContext context,
    XfyComputedDashboard d,
  ) {
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.28,
          children: [
            _GradientKpiCard(
              title: AppL10n.t('kpi_total_revenue'),
              value: XfyFormatters.formatTndRounded(d.revenue),
              subtitle: AppL10n.t('kpi_sub_delivered'),
              trend: d.revenueTrend,
              icon: Icons.trending_up_rounded,
              gradient: XfyColors.kpiRevenueGradient,
              sparkline: d.dailyRevenueSeries,
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_delivered_orders'),
              value: '${d.deliveredOrdersCount}',
              subtitle: AppL10n.t('kpi_sub_active_total', {
                'n': '${d.periodNonCancelledOrders.length}',
              }),
              trend: d.ordersTrend,
              icon: Icons.shopping_bag_outlined,
              gradient: XfyColors.kpiOrdersGradient,
              sparkline: d.dailyDeliveredSeries,
              onTap: () => widget.state.setTab(0),
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_active_clients'),
              value: '${d.activeClientsCount}',
              subtitle: AppL10n.t('kpi_sub_buyers'),
              trend: d.clientsTrend,
              icon: Icons.people_outline_rounded,
              gradient: XfyColors.kpiGreenGradient,
              sparkline: d.dailyDeliveredSeries,
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_return_rate'),
              value: '${d.returnRate.toStringAsFixed(1)}%',
              subtitle: AppL10n.t('kpi_sub_returns', {'n': '${d.totalReturns}'}),
              trend: d.returnRateTrend,
              icon: Icons.rotate_left_rounded,
              gradient: XfyColors.kpiReturnsGradient,
              sparkline: d.dailyReturnsSeries,
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_avg_basket'),
              value: XfyFormatters.formatTndRounded(d.avgBasket),
              subtitle: AppL10n.t('kpi_sub_per_order'),
              trend: d.avgBasketTrend,
              icon: Icons.shopping_cart_outlined,
              gradient: XfyColors.kpiAmberGradient,
              sparkline: d.dailyRevenueSeries,
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_net_profit'),
              value: XfyFormatters.formatTndRounded(d.analyticsProfit),
              subtitle: AppL10n.t('kpi_sub_budget', {
                'v': XfyFormatters.formatTndRounded(d.analyticsBudget),
              }),
              trend: d.analyticsProfitTrend,
              icon: Icons.account_balance_wallet_outlined,
              gradient: XfyColors.kpiTealGradient,
              sparkline: d.dailyRevenueSeries,
            ),
          ],
        ),
      ),

      // Graphique 1 Analytics : Performance des Ventes (Area LineChart fl_chart)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: _SalesPerformanceChartCard(
            points: d.dailyPoints,
            periodLabel: _rangeDisplayLabel,
          ),
        ),
      ),

      // Graphique 2 Analytics : Donut Répartition des Statuts (compteurs pré-calculés O(1))
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _StatusDonutChartCard(
            total: d.periodAllOrders.length,
            statusCounts: d.statusCounts,
          ),
        ),
      ),

      // Graphique 3 Analytics : Performance Géographique (Commandes livrées)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _GeoBarChartCard(entries: d.topCities),
        ),
      ),

      // Graphique 4 Analytics : Top Produits (Commandes livrées)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _RankedBarsCard(
            title: AppL10n.t('top_products'),
            subtitle: AppL10n.t('top_products_sub'),
            icon: Icons.workspace_premium_outlined,
            gradient: XfyColors.kpiRevenueGradient,
            accentColor: XfyColors.primaryVibrant,
            entries: d.topSoldProducts,
            unitSuffix: AppL10n.t('unit_units'),
          ),
        ),
      ),

      // Carte 5 Analytics : Clients VIP
      if (d.vipClients.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _VipClientsCard(clients: d.vipClients),
          ),
        ),
    ];
  }

  // ==================== VUE STATISTIQUES (100 % alignée sur statistics.component.ts) ====================
  List<Widget> _buildStatisticsSlivers(
    BuildContext context,
    XfyComputedDashboard d,
  ) {
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.38,
          children: [
            _GradientKpiCard(
              title: AppL10n.t('kpi_total_orders'),
              value: '${d.deliveredOrdersCount}',
              subtitle: AppL10n.t('kpi_sub_encaissee'),
              trend: d.ordersTrend,
              icon: Icons.shopping_cart_outlined,
              gradient: XfyColors.kpiOrdersGradient,
              onTap: () => widget.state.setTab(0),
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_products_sold'),
              value: '${d.productsSold}',
              subtitle: AppL10n.t('kpi_sub_units'),
              icon: Icons.inventory_2_outlined,
              gradient: XfyColors.kpiPurpleGradient,
              onTap: () => widget.state.setTab(1),
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_total_returns'),
              value: '${d.totalReturns}',
              subtitle: AppL10n.t('kpi_sub_returned_parcels'),
              icon: Icons.assignment_return_outlined,
              gradient: XfyColors.kpiReturnsGradient,
              onTap: () => widget.state.setTab(0),
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_return_rate'),
              value: '${d.returnRate.toStringAsFixed(2)}%',
              subtitle: AppL10n.t('kpi_sub_processed', {
                'n': '${d.deliveredOrdersCount + d.totalReturns}',
              }),
              icon: Icons.percent_rounded,
              gradient: XfyColors.kpiAmberGradient,
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_turnover'),
              value: XfyFormatters.formatTnd(d.revenue),
              subtitle: AppL10n.t('kpi_sub_rev_margin'),
              trend: d.revenueTrend,
              icon: Icons.payments_outlined,
              gradient: XfyColors.kpiGreenGradient,
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_return_amount'),
              value: XfyFormatters.formatTnd(d.returnedAmount),
              subtitle: AppL10n.t('kpi_sub_carrier_return'),
              icon: Icons.money_off_csred_outlined,
              gradient: XfyColors.kpiPinkGradient,
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_budget_costs'),
              value: XfyFormatters.formatTnd(d.statisticsBudget),
              subtitle: AppL10n.t('kpi_sub_costs_detail'),
              icon: Icons.pie_chart_outline_rounded,
              gradient: XfyColors.kpiRevenueGradient,
            ),
            _GradientKpiCard(
              title: AppL10n.t('kpi_net_profit'),
              value: XfyFormatters.formatTnd(d.statisticsProfit),
              subtitle: AppL10n.t('kpi_sub_profit_detail'),
              trend: d.statisticsProfitTrend,
              icon: Icons.savings_outlined,
              gradient: XfyColors.kpiTealGradient,
            ),
          ],
        ),
      ),

      // Graphique 1 Statistiques : Évolution Combinée Ventes vs Retours (Dual LineChart)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: _SalesVsReturnsChartCard(points: d.dailyPoints),
        ),
      ),

      // Graphique 2 Statistiques : Top 5 Produits Vendus (Émeraude)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _RankedBarsCard(
            title: AppL10n.t('top5_sold'),
            subtitle: AppL10n.t('top5_sold_sub'),
            icon: Icons.trending_up_rounded,
            gradient: XfyColors.kpiGreenGradient,
            accentColor: XfyColors.emerald,
            entries: d.topSoldProducts,
            unitSuffix: AppL10n.t('unit_units'),
          ),
        ),
      ),

      // Graphique 3 Statistiques : Top 5 Produits Retournés (Rose-Rouge)
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: _RankedBarsCard(
            title: AppL10n.t('top5_returned'),
            subtitle: AppL10n.t('top5_returned_sub'),
            icon: Icons.assignment_return_outlined,
            gradient: XfyColors.kpiReturnsGradient,
            accentColor: XfyColors.rose,
            entries: d.topReturnedProducts,
            unitSuffix: AppL10n.t('unit_returns'),
            emptyText: AppL10n.t('no_returns_period'),
          ),
        ),
      ),

      // Dernières commandes cliquables
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppL10n.t('recent_orders'),
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                  color: XfyColors.ink,
                ),
              ),
              TextButton(
                onPressed: () => widget.state.setTab(0),
                child: Text(
                  AppL10n.t('see_all'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: XfyColors.primaryVibrant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      if (widget.state.recentOrders.isNotEmpty)
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList.separated(
            itemCount: widget.state.recentOrders.take(5).length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final order = widget.state.recentOrders[index];
              return _RecentOrderTile(
                order: order,
                onTap: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      OrderDetailSheet(state: widget.state, order: order),
                ),
              );
            },
          ),
        ),
    ];
  }
}

// ============================================================================
// WIDGETS GRAPHIQUES NATIFS WEB-STYLE (`fl_chart`)
// ============================================================================

class _ModeTabButton extends StatelessWidget {
  const _ModeTabButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          gradient: selected ? XfyColors.statsGradient : null,
          borderRadius: BorderRadius.circular(10),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: XfyColors.primaryVibrant.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : XfyColors.inkSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? Colors.white : XfyColors.inkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? XfyColors.primaryVibrant : XfyColors.surface,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? XfyColors.primaryVibrant : XfyColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 14,
                  color: selected ? Colors.white : XfyColors.primaryVibrant,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : XfyColors.inkSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte KPI lumineuse en dégradé exact du Web XFY (+ tendance + mini courbe sparkline blanche)
class _GradientKpiCard extends StatelessWidget {
  const _GradientKpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.gradient,
    this.subtitle,
    this.trend,
    this.sparkline,
    this.onTap,
  });

  final String title;
  final String value;
  final String? subtitle;
  final TrendMetric? trend;
  final IconData icon;
  final LinearGradient gradient;
  final List<double>? sparkline;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final shadowColor = gradient.colors.first;
    final hasSpark = sparkline != null && sparkline!.length >= 2;

    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: shadowColor.withValues(alpha: 0.22),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white, size: 16),
                ),
              ],
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (trend != null && trend!.percent > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${trend!.isUp ? '↑' : '↓'}${trend!.percent >= 100 ? trend!.percent.toStringAsFixed(0) : trend!.percent.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            if (hasSpark)
              SizedBox(
                height: 24,
                width: double.infinity,
                child: CustomPaint(
                  painter: _MiniSparklinePainter(values: sparkline!),
                ),
              )
            else if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.88),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Sparkline ultra-léger en `CustomPainter` (< 0.05 ms par carte KPI au lieu de 6 `LineChart` fl_chart).
class _MiniSparklinePainter extends CustomPainter {
  _MiniSparklinePainter({required this.values});

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width <= 0 || size.height <= 0) return;
    double minV = values.first;
    double maxV = values.first;
    for (final v in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    final range = (maxV - minV).abs();
    final stepX = size.width / (values.length - 1);

    final linePath = Path();
    final areaPath = Path();
    for (int i = 0; i < values.length; i++) {
      final x = i * stepX;
      final norm = range > 0 ? (values[i] - minV) / range : 0.5;
      final y = size.height - 2 - norm * (size.height - 4);
      if (i == 0) {
        linePath.moveTo(x, y);
        areaPath.moveTo(x, size.height);
        areaPath.lineTo(x, y);
      } else {
        linePath.lineTo(x, y);
        areaPath.lineTo(x, y);
      }
    }
    areaPath.lineTo(size.width, size.height);
    areaPath.close();

    canvas.drawPath(
      areaPath,
      Paint()..color = Colors.white.withValues(alpha: 0.16),
    );
    canvas.drawPath(
      linePath,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MiniSparklinePainter oldDelegate) =>
      oldDelegate.values != values;
}

/// Graphique Analytics : Performance des Ventes (Area LineChart fl_chart)
class _SalesPerformanceChartCard extends StatelessWidget {
  const _SalesPerformanceChartCard({
    required this.points,
    required this.periodLabel,
  });

  final List<DailyChartPoint> points;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final maxY = points.isEmpty
        ? 100.0
        : math.max(
            10.0,
            points.map((p) => p.revenue).reduce(math.max) * 1.2,
          );

    return _ChartContainerCard(
      title: 'Performance des Ventes',
      subtitle: 'Revenu livré ($periodLabel)',
      icon: Icons.show_chart_rounded,
      iconColor: XfyColors.primaryVibrant,
      child: points.isEmpty
          ? const _ChartEmptyPlaceholder()
          : SizedBox(
              height: 210,
              child: LineChart(
                duration: Duration.zero,
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: XfyColors.divider,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (val, _) => Text(
                          val >= 1000
                              ? '${(val / 1000).toStringAsFixed(1)}k'
                              : val.toStringAsFixed(0),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: XfyColors.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval:
                            math.max(1, (points.length / 4).ceil()).toDouble(),
                        getTitlesWidget: (val, _) {
                          final idx = val.toInt();
                          if (idx < 0 || idx >= points.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              XfyFormatters.formatDayMonthShort(
                                points[idx].date,
                              ),
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: XfyColors.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => XfyColors.primaryDark,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final idx = spot.x.toInt();
                          final pt = points[idx.clamp(0, points.length - 1)];
                          return LineTooltipItem(
                            '${XfyFormatters.formatDayMonthShort(pt.date)}\n${XfyFormatters.formatTnd(pt.revenue)} (${pt.deliveredOrdersCount} livrée(s))',
                            const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      preventCurveOverShooting: true,
                      gradient: XfyColors.statsGradient,
                      barWidth: 3.2,
                      dotData: FlDotData(
                        show: points.length <= 10,
                        getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                          radius: 3.5,
                          color: Colors.white,
                          strokeWidth: 2.2,
                          strokeColor: XfyColors.primaryVibrant,
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            XfyColors.primaryVibrant.withValues(alpha: 0.28),
                            XfyColors.primaryViolet.withValues(alpha: 0.02),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                      spots: [
                        for (int i = 0; i < points.length; i++)
                          FlSpot(i.toDouble(), points[i].revenue),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Graphique Statistiques : Évolution Combinée Ventes Livrées vs Retours (Dual LineChart)
class _SalesVsReturnsChartCard extends StatelessWidget {
  const _SalesVsReturnsChartCard({required this.points});

  final List<DailyChartPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxOrders = points.isEmpty
        ? 10.0
        : math.max(
            5.0,
            points
                    .map(
                      (p) =>
                          math.max(p.deliveredOrdersCount, p.returnedOrdersCount),
                    )
                    .reduce(math.max)
                    .toDouble() *
                1.25,
          );

    return _ChartContainerCard(
      title: 'Ventes Livrées vs Retours',
      subtitle: 'Évolution quotidienne des livraisons et retours',
      icon: Icons.compare_arrows_rounded,
      iconColor: XfyColors.emerald,
      trailing: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendDot(color: XfyColors.emerald, label: 'Livrées'),
          SizedBox(width: 10),
          _LegendDot(color: XfyColors.rose, label: 'Retours'),
        ],
      ),
      child: points.isEmpty
          ? const _ChartEmptyPlaceholder()
          : SizedBox(
              height: 210,
              child: LineChart(
                duration: Duration.zero,
                LineChartData(
                  minY: 0,
                  maxY: maxOrders,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: math.max(1, maxOrders / 4),
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: XfyColors.divider,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 32,
                        getTitlesWidget: (v, _) => Text(
                          v.toInt().toString(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: XfyColors.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval:
                            math.max(1, (points.length / 4).ceil()).toDouble(),
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= points.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              XfyFormatters.formatDayMonthShort(
                                points[idx].date,
                              ),
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: XfyColors.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (_) => XfyColors.primaryDark,
                      getTooltipItems: (spots) {
                        return spots.map((s) {
                          final isSales = s.barIndex == 0;
                          return LineTooltipItem(
                            '${isSales ? 'Livrées' : 'Retours'} : ${s.y.toInt()}',
                            TextStyle(
                              color: isSales
                                  ? const Color(0xFF6EE7B7)
                                  : const Color(0xFFFDA4AF),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: XfyColors.emerald,
                      barWidth: 3,
                      dotData: FlDotData(show: points.length <= 10),
                      belowBarData: BarAreaData(
                        show: true,
                        color: XfyColors.emerald.withValues(alpha: 0.14),
                      ),
                      spots: [
                        for (int i = 0; i < points.length; i++)
                          FlSpot(
                            i.toDouble(),
                            points[i].deliveredOrdersCount.toDouble(),
                          ),
                      ],
                    ),
                    LineChartBarData(
                      isCurved: true,
                      preventCurveOverShooting: true,
                      color: XfyColors.rose,
                      barWidth: 3,
                      dotData: FlDotData(show: points.length <= 10),
                      belowBarData: BarAreaData(
                        show: true,
                        color: XfyColors.rose.withValues(alpha: 0.12),
                      ),
                      spots: [
                        for (int i = 0; i < points.length; i++)
                          FlSpot(
                            i.toDouble(),
                            points[i].returnedOrdersCount.toDouble(),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Graphique Analytics : Donut Chart Répartition par Statut unifié (O(1) via `statusCounts`)
class _StatusDonutChartCard extends StatelessWidget {
  const _StatusDonutChartCard({
    required this.total,
    required this.statusCounts,
  });

  final int total;
  final Map<String, int> statusCounts;

  @override
  Widget build(BuildContext context) {
    final items = XfyFormatters.statuses
        .where((meta) => meta.key != 'pas_de_reponse')
        .map((meta) => (meta: meta, count: statusCounts[meta.key] ?? 0))
        .where((e) => e.count > 0)
        .toList();

    return _ChartContainerCard(
      title: 'Répartition par Statut',
      subtitle: 'Toutes les $total commande(s) de la période (statut unifié)',
      icon: Icons.donut_large_rounded,
      iconColor: XfyColors.primaryViolet,
      child: items.isEmpty
          ? const _ChartEmptyPlaceholder()
          : Row(
              children: [
                SizedBox(
                  width: 148,
                  height: 148,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        duration: Duration.zero,
                        PieChartData(
                          centerSpaceRadius: 42,
                          sectionsSpace: 2.5,
                          sections: items.map((e) {
                            return PieChartSectionData(
                              value: e.count.toDouble(),
                              color: e.meta.color,
                              radius: 26,
                              showTitle: false,
                            );
                          }).toList(),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: XfyColors.ink,
                            ),
                          ),
                          const Text(
                            'Total',
                            style: TextStyle(
                              fontSize: 11,
                              color: XfyColors.inkMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: items.map((e) {
                      final pct = total > 0 ? (e.count / total * 100).round() : 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: e.meta.color,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                e.meta.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: XfyColors.ink,
                                ),
                              ),
                            ),
                            Text(
                              '${e.count} ($pct%)',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: e.meta.color,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Graphique Analytics : Performance Géographique (BarChart vertical fl_chart)
class _GeoBarChartCard extends StatelessWidget {
  const _GeoBarChartCard({required this.entries});

  final List<MapEntry<String, int>> entries;

  @override
  Widget build(BuildContext context) {
    final maxVal = entries.isEmpty
        ? 10.0
        : math.max(4.0, entries.first.value.toDouble() * 1.25);

    return _ChartContainerCard(
      title: 'Performance Géographique',
      subtitle: 'Top gouvernorats par commandes livrées',
      icon: Icons.location_on_outlined,
      iconColor: XfyColors.cyan,
      child: entries.isEmpty
          ? const _ChartEmptyPlaceholder()
          : SizedBox(
              height: 195,
              child: BarChart(
                duration: Duration.zero,
                BarChartData(
                  maxY: maxVal,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: math.max(1, maxVal / 4),
                    getDrawingHorizontalLine: (_) => const FlLine(
                      color: XfyColors.divider,
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) => Text(
                          v.toInt().toString(),
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: XfyColors.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= entries.length) {
                            return const SizedBox.shrink();
                          }
                          final name = entries[idx].key;
                          final short = name.length > 8
                              ? '${name.substring(0, 7)}.'
                              : name;
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              short,
                              style: const TextStyle(
                                fontSize: 10.5,
                                color: XfyColors.inkSecondary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => XfyColors.primaryDark,
                      getTooltipItem: (group, _, rod, _) {
                        final item = entries[group.x];
                        return BarTooltipItem(
                          '${item.key}\n${item.value} livrée(s)',
                          const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        );
                      },
                    ),
                  ),
                  barGroups: [
                    for (int i = 0; i < entries.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: entries[i].value.toDouble(),
                            width: 24,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF06B6D4), Color(0xFF6366F1)],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _RankedBarsCard extends StatelessWidget {
  const _RankedBarsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.accentColor,
    required this.entries,
    required this.unitSuffix,
    this.emptyText = 'Aucune donnée sur cette période',
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final LinearGradient gradient;
  final Color accentColor;
  final List<MapEntry<String, int>> entries;
  final String unitSuffix;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final maxVal = entries.isNotEmpty ? entries.first.value : 1;

    return _ChartContainerCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      iconColor: accentColor,
      child: entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  emptyText,
                  style: const TextStyle(
                    fontSize: 13,
                    color: XfyColors.inkSecondary,
                  ),
                ),
              ),
            )
          : Column(
              children: entries.map((e) {
                final ratio = maxVal > 0 ? e.value / maxVal : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: XfyColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${e.value} $unitSuffix',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      LayoutBuilder(
                        builder: (_, constraints) {
                          return Stack(
                            children: [
                              Container(
                                height: 9,
                                width: constraints.maxWidth,
                                decoration: BoxDecoration(
                                  color: XfyColors.canvas,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                              Container(
                                height: 9,
                                width: math.max(10, constraints.maxWidth * ratio),
                                decoration: BoxDecoration(
                                  gradient: gradient,
                                  borderRadius: BorderRadius.circular(99),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _VipClientsCard extends StatelessWidget {
  const _VipClientsCard({required this.clients});

  final List<VipClientSummary> clients;

  static const _avatarColors = [
    Color(0xFF6366F1),
    Color(0xFF06B6D4),
    Color(0xFF10B981),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
  ];

  @override
  Widget build(BuildContext context) {
    return _ChartContainerCard(
      title: 'Clients VIP',
      subtitle: 'Meilleurs acheteurs livrés sur la période',
      icon: Icons.star_rounded,
      iconColor: XfyColors.amber,
      child: Column(
        children: [
          for (int i = 0; i < clients.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == clients.length - 1 ? 0 : 10),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: XfyColors.canvasAlt,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: XfyColors.divider),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 19,
                      backgroundColor: _avatarColors[i % _avatarColors.length],
                      foregroundColor: Colors.white,
                      child: Text(
                        clients[i].name.isNotEmpty
                            ? clients[i].name[0].toUpperCase()
                            : 'C',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            clients[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: XfyColors.ink,
                            ),
                          ),
                          if (clients[i].phone.isNotEmpty)
                            Text(
                              clients[i].phone,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: XfyColors.inkSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          XfyFormatters.formatTnd(clients[i].totalSpent),
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: XfyColors.primaryVibrant,
                          ),
                        ),
                        Text(
                          '${clients[i].ordersCount} cmd',
                          style: const TextStyle(
                            fontSize: 11,
                            color: XfyColors.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartContainerCard extends StatelessWidget {
  const _ChartContainerCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.iconColor,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: XfyColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: XfyColors.border),
          boxShadow: XfyColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: XfyColors.ink,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: XfyColors.inkSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: XfyColors.inkSecondary,
          ),
        ),
      ],
    );
  }
}

class _ChartEmptyPlaceholder extends StatelessWidget {
  const _ChartEmptyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 120,
      child: Center(
        child: Text(
          'Aucune donnée sur cette période',
          style: TextStyle(fontSize: 13, color: XfyColors.inkMuted),
        ),
      ),
    );
  }
}

class _RecentOrderTile extends StatelessWidget {
  const _RecentOrderTile({required this.order, required this.onTap});

  final OrderModel order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: XfyColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: XfyColors.border),
          boxShadow: XfyColors.cardShadow,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${order.id}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: XfyColors.primaryVibrant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          order.nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: XfyColors.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.produit ?? order.locationLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: XfyColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  XfyFormatters.formatTnd(order.effectiveTotal),
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: XfyColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                StatusBadge(
                  status: order.normalizedStatus,
                  compact: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
