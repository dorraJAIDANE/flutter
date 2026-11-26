import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/product_model.dart';
import '../../state/app_state.dart';
import 'add_product_sheet.dart';
import 'stock_edit_sheet.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchCtrl = TextEditingController();
  String _stockFilter = 'all'; // all | in | low | out

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ProductModel> _filtered(List<ProductModel> all) {
    final q = _searchCtrl.text.trim().toLowerCase();
    return all.where((p) {
      if (_stockFilter == 'in' && p.isOutOfStock) return false;
      if (_stockFilter == 'low' && !p.isLowStock) return false;
      if (_stockFilter == 'out' && !p.isOutOfStock) return false;
      if (q.isEmpty) return true;
      return p.nom.toLowerCase().contains(q) ||
          (p.sku ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final all = widget.state.products;
    final visible = _filtered(all);
    final outCount = all.where((p) => p.isOutOfStock).length;
    final lowCount = all.where((p) => p.isLowStock).length;

    return Scaffold(
      backgroundColor: XfyColors.canvas,
      appBar: AppBar(
        title: Row(
          children: [
            Text(AppL10n.t('products_title')),
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
                  color: XfyColors.primary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: AppL10n.t('refresh'),
            onPressed: () => widget.state.refreshProducts(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'xfy_add_product_fab',
        backgroundColor: XfyColors.primaryVibrant,
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: () {
          HapticFeedback.lightImpact();
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            builder: (_) => AddProductSheet(state: widget.state),
          );
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(
          AppL10n.t('products_new'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Container(
            color: XfyColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: AppL10n.t('products_search_hint'),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: XfyColors.inkSecondary,
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
          Container(
            color: XfyColors.surface,
            padding: const EdgeInsets.only(bottom: 12),
            child: SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _StockFilterChip(
                    label: AppL10n.t('products_all', {'n': '${all.length}'}),
                    selected: _stockFilter == 'all',
                    onTap: () => setState(() => _stockFilter = 'all'),
                  ),
                  _StockFilterChip(
                    label: AppL10n.t('products_in_stock'),
                    selected: _stockFilter == 'in',
                    color: XfyColors.emerald,
                    onTap: () => setState(() => _stockFilter = 'in'),
                  ),
                  _StockFilterChip(
                    label: AppL10n.t('products_low_stock', {'n': '$lowCount'}),
                    selected: _stockFilter == 'low',
                    color: XfyColors.amber,
                    onTap: () => setState(() => _stockFilter = 'low'),
                  ),
                  _StockFilterChip(
                    label: AppL10n.t('products_out_stock', {'n': '$outCount'}),
                    selected: _stockFilter == 'out',
                    color: XfyColors.rose,
                    onTap: () => setState(() => _stockFilter = 'out'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              color: XfyColors.primary,
              onRefresh: () => widget.state.refreshProducts(),
              child: widget.state.isProductsLoading && all.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(color: XfyColors.primary),
                    )
                  : widget.state.productsError != null && all.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(28),
                          children: [
                            const SizedBox(height: 60),
                            const Icon(
                              Icons.wifi_off_rounded,
                              size: 48,
                              color: XfyColors.rose,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppL10n.t('products_load_error'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: XfyColors.ink,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.state.productsError!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: XfyColors.inkSecondary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size(160, 44),
                                ),
                                onPressed: () => widget.state.refreshProducts(),
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: Text(AppL10n.t('retry')),
                              ),
                            ),
                          ],
                        )
                      : visible.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 90),
                            const Icon(
                              Icons.inventory_2_outlined,
                              size: 48,
                              color: XfyColors.inkMuted,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              AppL10n.t('products_empty'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: XfyColors.ink,
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 92),
                          itemCount: visible.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final product = visible[index];
                            return _ProductCard(
                              product: product,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => StockEditSheet(
                                    state: widget.state,
                                    product: product,
                                  ),
                                );
                              },
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

class _StockFilterChip extends StatelessWidget {
  const _StockFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? XfyColors.primaryVibrant;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? bg : XfyColors.canvas,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: selected ? bg : XfyColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : XfyColors.inkSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});

  final ProductModel product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color stockColor;
    final Color stockBg;
    final String stockLabel;

    if (product.isOutOfStock) {
      stockColor = XfyColors.rose;
      stockBg = XfyColors.roseSoft;
      stockLabel = AppL10n.t('stock_out');
    } else if (product.isLowStock) {
      stockColor = XfyColors.amber;
      stockBg = XfyColors.amberSoft;
      stockLabel = AppL10n.t('stock_in_count', {'n': '${product.totalStock}'});
    } else {
      stockColor = XfyColors.emerald;
      stockBg = XfyColors.emeraldSoft;
      stockLabel = AppL10n.t('stock_in_count', {'n': '${product.totalStock}'});
    }

    return RepaintBoundary(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: XfyColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: XfyColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  color: XfyColors.canvas,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: XfyColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: product.resolvedImageUrl != null
                    ? Image.network(
                        product.resolvedImageUrl!,
                        fit: BoxFit.cover,
                        cacheWidth: 180,
                        cacheHeight: 180,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.image_outlined,
                          color: XfyColors.inkMuted,
                        ),
                      )
                    : const Icon(Icons.image_outlined, color: XfyColors.inkMuted),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.nom,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: XfyColors.ink,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        XfyFormatters.formatTnd(product.price),
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: XfyColors.primary,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (product.compareAtPrice != null &&
                          product.compareAtPrice! > product.price) ...[
                        const SizedBox(width: 6),
                        Text(
                          XfyFormatters.formatTnd(product.compareAtPrice),
                          style: const TextStyle(
                            fontSize: 12,
                            color: XfyColors.inkMuted,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: stockBg,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          stockLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: stockColor,
                          ),
                        ),
                      ),
                      if (product.variants.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${product.variants.length} variantes',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: XfyColors.inkSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.tune_rounded,
              size: 20,
              color: XfyColors.inkMuted,
            ),
          ],
        ),
      ),
      ),
    );
  }
}
