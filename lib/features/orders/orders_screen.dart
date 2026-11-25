import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/order_model.dart';
import '../../state/app_state.dart';
import '../widgets/status_badge.dart';
import 'add_order_sheet.dart';
import 'order_detail_sheet.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, required this.state});

  final AppState state;

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  final _searchCtrl = TextEditingController();
  String _selectedStatus = 'all';

  // Filtre de date : 'all' | 'today' | 'yesterday' | '7days' | 'month' | 'custom'
  String _datePreset = 'all';
  DateTimeRange? _customDateRange;

  // Cache O(1) du filtrage + compteurs par statut en 1 seule passe
  String? _cachedBaseKey;
  List<OrderModel> _cachedDateFiltered = const [];
  Map<String, int> _cachedStatusCounts = const {};
  String? _cachedVisibleKey;
  List<OrderModel> _cachedVisible = const [];
  double _cachedVisibleTotal = 0;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCustomDateRange() async {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 6)),
            end: now,
          ),
      helpText: AppL10n.t('orders_date_picker_help'),
      cancelText: AppL10n.t('cancel'),
      confirmText: AppL10n.t('apply'),
      saveText: AppL10n.t('apply'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: XfyColors.primaryVibrant,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: XfyColors.ink,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _datePreset = 'custom';
      });
    }
  }

  void _ensureFilteredCache(List<OrderModel> all) {
    final q = _searchCtrl.text.trim().toLowerCase();
    final baseKey =
        '${widget.state.ordersVersion}_${_datePreset}_${_customDateRange?.start.millisecondsSinceEpoch}_${_customDateRange?.end.millisecondsSinceEpoch}_$q';

    if (_cachedBaseKey != baseKey) {
      final filtered = <OrderModel>[];
      final counts = <String, int>{};

      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));
      final sevenDaysStart = todayStart.subtract(const Duration(days: 6));
      final customStart = _customDateRange != null
          ? DateTime(
              _customDateRange!.start.year,
              _customDateRange!.start.month,
              _customDateRange!.start.day,
            )
          : null;
      final customEnd = _customDateRange != null
          ? DateTime(
              _customDateRange!.end.year,
              _customDateRange!.end.month,
              _customDateRange!.end.day,
            )
          : null;

      for (final o in all) {
        if (_datePreset != 'all') {
          final d = o.creationDate;
          if (d == null) continue;
          final orderDay = DateTime(d.year, d.month, d.day);
          bool dateOk = true;
          switch (_datePreset) {
            case 'today':
              dateOk = orderDay == todayStart;
              break;
            case 'yesterday':
              dateOk = orderDay == yesterdayStart;
              break;
            case '7days':
              dateOk = !orderDay.isBefore(sevenDaysStart) &&
                  !orderDay.isAfter(todayStart);
              break;
            case 'month':
              dateOk = d.year == now.year && d.month == now.month;
              break;
            case 'custom':
              if (customStart != null && customEnd != null) {
                dateOk = !orderDay.isBefore(customStart) &&
                    !orderDay.isAfter(customEnd);
              }
              break;
          }
          if (!dateOk) continue;
        }
        if (q.isNotEmpty && !o.searchBlob.contains(q)) continue;

        filtered.add(o);
        final uStatus = o.unifiedStatus;
        counts[uStatus] = (counts[uStatus] ?? 0) + 1;
        if (o.normalizedStatus == 'pas_de_reponse') {
          counts['pas_de_reponse'] = (counts['pas_de_reponse'] ?? 0) + 1;
        }
      }

      counts['all'] = filtered.length;
      _cachedBaseKey = baseKey;
      _cachedDateFiltered = filtered;
      _cachedStatusCounts = counts;
      _cachedVisibleKey = null;
    }

    final visibleKey = '${baseKey}_$_selectedStatus';
    if (_cachedVisibleKey != visibleKey) {
      final List<OrderModel> vis;
      if (_selectedStatus == 'all') {
        vis = _cachedDateFiltered;
      } else if (_selectedStatus == 'pas_de_reponse') {
        vis = _cachedDateFiltered
            .where((o) => o.normalizedStatus == 'pas_de_reponse')
            .toList();
      } else {
        vis = _cachedDateFiltered
            .where((o) => o.unifiedStatus == _selectedStatus)
            .toList();
      }
      double sum = 0;
      for (final o in vis) {
        sum += o.effectiveTotal;
      }
      _cachedVisibleKey = visibleKey;
      _cachedVisible = vis;
      _cachedVisibleTotal = sum;
    }
  }

  int _countByStatus(String statusKey) => _cachedStatusCounts[statusKey] ?? 0;

  String get _customRangeLabel {
    if (_customDateRange == null) return AppL10n.t('period_calendar');
    final s = XfyFormatters.formatDayMonthShort(_customDateRange!.start);
    final e = XfyFormatters.formatDayMonthShort(_customDateRange!.end);
    return s == e ? s : '$s → $e';
  }

  Future<void> _quickChangeStatus(OrderModel order) async {
    HapticFeedback.selectionClick();
    final chosen = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: XfyColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppL10n.t('order_status_title', {'id': '${order.id}'}),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: XfyColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  order.nom,
                  style: const TextStyle(
                    fontSize: 13,
                    color: XfyColors.inkSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                ...XfyFormatters.statuses.map((meta) {
                  final active = order.normalizedStatus == meta.key;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.pop(ctx, meta.key),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: active ? meta.bgColor : XfyColors.canvas,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: active ? meta.color : XfyColors.border,
                            width: active ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(meta.icon, color: meta.color, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                meta.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: active ? meta.color : XfyColors.ink,
                                ),
                              ),
                            ),
                            if (active)
                              Icon(
                                Icons.check_rounded,
                                color: meta.color,
                                size: 20,
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (chosen == null || chosen == order.normalizedStatus) return;

    try {
      await widget.state.updateOrderStatus(order, chosen);
      if (!mounted) return;
      final label = XfyFormatters.statusMeta(chosen).label;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Commande #${order.id} → $label')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: XfyColors.rose,
          content: Text('Erreur : $e'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allOrders = widget.state.orders;
    _ensureFilteredCache(allOrders);
    final visible = _cachedVisible;
    final visibleTotalTnd = _cachedVisibleTotal;

    return Scaffold(
      backgroundColor: XfyColors.canvas,
      appBar: AppBar(
        title: Row(
          children: [
            Text(AppL10n.t('orders_title')),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: XfyColors.primarySoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${visible.length}',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: XfyColors.primaryVibrant,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: AppL10n.t('orders_date_filter_tooltip'),
            color: _datePreset == 'custom'
                ? XfyColors.primaryVibrant
                : XfyColors.inkSecondary,
            onPressed: _pickCustomDateRange,
            icon: const Icon(Icons.date_range_rounded),
          ),
          IconButton(
            tooltip: AppL10n.t('refresh'),
            onPressed: () => widget.state.refreshOrders(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: XfyColors.primaryVibrant,
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: () {
          HapticFeedback.lightImpact();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => AddOrderSheet(state: widget.state),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(
          AppL10n.t('orders_new'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // 1. Barre de recherche
          Container(
            color: XfyColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: AppL10n.t('orders_search_hint'),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: XfyColors.primaryVibrant,
                ),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                fillColor: XfyColors.canvas,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),

          // 2. Filtre DATE (Toutes, Aujourd'hui, Hier, 7 jours, Ce mois, Calendrier)
          Container(
            color: XfyColors.surface,
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _DateFilterPill(
                    label: AppL10n.t('orders_all_dates'),
                    icon: Icons.all_inclusive_rounded,
                    selected: _datePreset == 'all',
                    onTap: () => setState(() {
                      _datePreset = 'all';
                      _customDateRange = null;
                    }),
                  ),
                  _DateFilterPill(
                    label: AppL10n.t('period_today'),
                    selected: _datePreset == 'today',
                    onTap: () => setState(() => _datePreset = 'today'),
                  ),
                  _DateFilterPill(
                    label: AppL10n.t('period_yesterday'),
                    selected: _datePreset == 'yesterday',
                    onTap: () => setState(() => _datePreset = 'yesterday'),
                  ),
                  _DateFilterPill(
                    label: AppL10n.t('period_7days'),
                    selected: _datePreset == '7days',
                    onTap: () => setState(() => _datePreset = '7days'),
                  ),
                  _DateFilterPill(
                    label: AppL10n.t('period_month'),
                    selected: _datePreset == 'month',
                    onTap: () => setState(() => _datePreset = 'month'),
                  ),
                  _DateFilterPill(
                    label: _customRangeLabel,
                    icon: Icons.calendar_month_rounded,
                    selected: _datePreset == 'custom',
                    onTap: _pickCustomDateRange,
                  ),
                ],
              ),
            ),
          ),

          // 3. Filtres de statut (couleurs lumineuses Web XFY)
          Container(
            color: XfyColors.surface,
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _FilterChipPill(
                    label: AppL10n.t('orders_all'),
                    count: _countByStatus('all'),
                    selected: _selectedStatus == 'all',
                    onTap: () => setState(() => _selectedStatus = 'all'),
                  ),
                  ...XfyFormatters.statuses.map(
                    (meta) => _FilterChipPill(
                      label: meta.label,
                      count: _countByStatus(meta.key),
                      selected: _selectedStatus == meta.key,
                      accentColor: meta.color,
                      onTap: () => setState(() => _selectedStatus = meta.key),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bandeau résumé discret quand un filtre date est actif
          if (_datePreset != 'all')
            Container(
              width: double.infinity,
              color: XfyColors.primarySoft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(
                children: [
                  const Icon(
                    Icons.filter_alt_outlined,
                    size: 15,
                    color: XfyColors.primaryVibrant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      AppL10n.t('orders_summary_bar', {
                        'count': '${visible.length}',
                        'total': XfyFormatters.formatTnd(visibleTotalTnd),
                      }),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: XfyColors.primaryDark,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() {
                      _datePreset = 'all';
                      _customDateRange = null;
                    }),
                    child: Text(
                      AppL10n.t('reset'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: XfyColors.primaryVibrant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // 4. Liste des commandes
          Expanded(
            child: RefreshIndicator(
              color: XfyColors.primaryVibrant,
              onRefresh: () => widget.state.refreshOrders(),
              child: widget.state.isOrdersLoading && allOrders.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: XfyColors.primaryVibrant,
                      ),
                    )
                  : widget.state.ordersError != null && allOrders.isEmpty
                      ? _EmptyOrdersState(
                          icon: Icons.wifi_off_rounded,
                          title: AppL10n.t('orders_load_error'),
                          subtitle: widget.state.ordersError!,
                          onRetry: () => widget.state.refreshOrders(),
                        )
                      : visible.isEmpty
                          ? _EmptyOrdersState(
                              icon: Icons.event_busy_outlined,
                              title: AppL10n.t('orders_empty_title'),
                              subtitle: _datePreset != 'all'
                                  ? AppL10n.t('orders_empty_date')
                                  : AppL10n.t('orders_empty_all'),
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
                              itemCount: visible.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                final order = visible[index];
                                return _OrderCard(
                                  order: order,
                                  onTap: () => showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    builder: (_) => OrderDetailSheet(
                                      state: widget.state,
                                      order: order,
                                    ),
                                  ),
                                  onStatusTap: () => _quickChangeStatus(order),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateFilterPill extends StatelessWidget {
  const _DateFilterPill({
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
          padding: const EdgeInsets.symmetric(horizontal: 11),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selected ? XfyColors.statsGradient : null,
            color: selected ? null : XfyColors.canvas,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? Colors.transparent : XfyColors.border,
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

class _FilterChipPill extends StatelessWidget {
  const _FilterChipPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.accentColor,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final activeBg = accentColor ?? XfyColors.primaryVibrant;
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
            color: selected ? activeBg : XfyColors.canvas,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(
              color: selected ? activeBg : XfyColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white : XfyColors.inkSecondary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: selected
                      ? Colors.white.withValues(alpha: 0.24)
                      : XfyColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : XfyColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onTap,
    required this.onStatusTap,
  });

  final OrderModel order;
  final VoidCallback onTap;
  final VoidCallback onStatusTap;

  @override
  Widget build(BuildContext context) {
    final hasReturnHistory = (order.clientReturnedOrders ?? 0) > 0;

    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: XfyColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: XfyColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '#${order.id}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: XfyColors.primaryVibrant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            order.shortDateLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: XfyColors.inkMuted,
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: onStatusTap,
                        child: StatusBadge(
                          status: order.normalizedStatus == 'pas_de_reponse'
                              ? 'pas_de_reponse'
                              : order.unifiedStatus,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    order.nom,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: XfyColors.ink,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                if (hasReturnHistory) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: XfyColors.roseSoft,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${order.clientReturnedOrders} retour(s)',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w700,
                                        color: XfyColors.rose,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            if (order.produit != null &&
                                order.produit!.trim().isNotEmpty)
                              Text(
                                '${order.produit}${(order.quantite != null && order.quantite!.isNotEmpty && order.quantite != '0') ? ' × ${order.quantite}' : ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: XfyColors.ink,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 14,
                                  color: XfyColors.primaryVibrant,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    order.locationLabel,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      color: XfyColors.inkSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            XfyFormatters.formatTnd(order.effectiveTotal),
                            style: const TextStyle(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w800,
                              color: XfyColors.primaryDark,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (order.hasBordereau) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: XfyColors.primarySoft,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                order.numeroBordereau!,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: XfyColors.primaryVibrant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 1-Tap Action Bar (Couleurs claires Web)
            Container(
              decoration: const BoxDecoration(
                color: XfyColors.canvasAlt,
                border: Border(top: BorderSide(color: XfyColors.divider)),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: order.phoneNumber.isEmpty
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              XfyFormatters.launchPhoneCall(order.phoneNumber);
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: XfyColors.primaryBlue,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.call_outlined, size: 17),
                      label: const Text(
                        'Appeler',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 20, color: XfyColors.divider),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: order.phoneNumber.isEmpty
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              XfyFormatters.launchWhatsApp(
                                order.phoneNumber,
                                message:
                                    'Bonjour ${order.nom}, concernant votre commande #${order.id} (${order.produit ?? ''}) d\'un montant de ${XfyFormatters.formatTnd(order.effectiveTotal)}.',
                              );
                            },
                      style: TextButton.styleFrom(
                        foregroundColor: XfyColors.whatsapp,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.chat_outlined, size: 17),
                      label: const Text(
                        'WhatsApp',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  Container(width: 1, height: 20, color: XfyColors.divider),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: onStatusTap,
                      style: TextButton.styleFrom(
                        foregroundColor: XfyColors.primaryVibrant,
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                      label: const Text(
                        'Statut',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _EmptyOrdersState extends StatelessWidget {
  const _EmptyOrdersState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Icon(icon, size: 48, color: XfyColors.inkMuted),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: XfyColors.ink,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13.5, color: XfyColors.inkSecondary),
          ),
        ),
        if (onRetry != null) ...[
          const SizedBox(height: 18),
          Center(
            child: OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Réessayer'),
            ),
          ),
        ],
      ],
    );
  }
}
