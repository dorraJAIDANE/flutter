import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/product_model.dart';
import '../../state/app_state.dart';

class StockEditSheet extends StatefulWidget {
  const StockEditSheet({
    super.key,
    required this.state,
    required this.product,
  });

  final AppState state;
  final ProductModel product;

  @override
  State<StockEditSheet> createState() => _StockEditSheetState();
}

class _StockEditSheetState extends State<StockEditSheet> {
  late int _simpleStock;
  late Map<String, int> _variantStocks;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _simpleStock = widget.product.stock ?? 0;
    _variantStocks = {
      for (final v in widget.product.variants) v.id: v.stock,
    };
  }

  Future<void> _saveSimple() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      await widget.state.updateSimpleProductStock(widget.product, _simpleStock);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stock mis à jour : $_simpleStock unité(s)'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveVariants() async {
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();
    try {
      for (final v in widget.product.variants) {
        final target = _variantStocks[v.id] ?? v.stock;
        if (target != v.stock) {
          await widget.state.updateVariantProductStock(widget.product, v, target);
        }
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stocks des variantes mis à jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final hasVariants = p.variants.isNotEmpty;

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
              p.nom,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: XfyColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Prix : ${XfyFormatters.formatTnd(p.price)}${p.sku != null && p.sku!.isNotEmpty ? ' • SKU: ${p.sku}' : ''}',
              style: const TextStyle(fontSize: 13, color: XfyColors.inkSecondary),
            ),
            const SizedBox(height: 18),
            if (!hasVariants)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: XfyColors.canvas,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: XfyColors.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Stock disponible',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: XfyColors.ink,
                      ),
                    ),
                    _StockStepper(
                      value: _simpleStock,
                      onChanged: (v) => setState(() => _simpleStock = v),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: p.variants.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, idx) {
                    final variant = p.variants[idx];
                    final val = _variantStocks[variant.id] ?? variant.stock;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: XfyColors.canvas,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: XfyColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  variant.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: XfyColors.ink,
                                  ),
                                ),
                                Text(
                                  XfyFormatters.formatTnd(variant.price),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: XfyColors.inkSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _StockStepper(
                            value: val,
                            onChanged: (v) =>
                                setState(() => _variantStocks[variant.id] = v),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _saving
                  ? null
                  : (hasVariants ? _saveVariants : _saveSimple),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Enregistrer le stock'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StockStepper extends StatelessWidget {
  const _StockStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          style: IconButton.styleFrom(
            backgroundColor: Colors.white,
            side: const BorderSide(color: XfyColors.border),
            fixedSize: const Size(38, 38),
          ),
          onPressed: value > 0
              ? () {
                  HapticFeedback.selectionClick();
                  onChanged(value - 1);
                }
              : null,
          icon: const Icon(Icons.remove_rounded, size: 18),
        ),
        SizedBox(
          width: 48,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: XfyColors.ink,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton.filled(
          style: IconButton.styleFrom(
            backgroundColor: XfyColors.primary,
            foregroundColor: Colors.white,
            fixedSize: const Size(38, 38),
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            onChanged(value + 1);
          },
          icon: const Icon(Icons.add_rounded, size: 18),
        ),
      ],
    );
  }
}
