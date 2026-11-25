import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/product_model.dart';
import '../../state/app_state.dart';

class AddOrderSheet extends StatefulWidget {
  const AddOrderSheet({super.key, required this.state});

  final AppState state;

  @override
  State<AddOrderSheet> createState() => _AddOrderSheetState();
}

class _AddOrderSheetState extends State<AddOrderSheet> {
  static const _gouvernorats = [
    'Tunis',
    'Ariana',
    'Ben Arous',
    'Manouba',
    'Nabeul',
    'Zaghouan',
    'Bizerte',
    'Béja',
    'Jendouba',
    'Le Kef',
    'Siliana',
    'Sousse',
    'Monastir',
    'Mahdia',
    'Sfax',
    'Kairouan',
    'Kasserine',
    'Sidi Bouzid',
    'Gabès',
    'Médenine',
    'Tataouine',
    'Gafsa',
    'Tozeur',
    'Kébili',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _productCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _villeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _commentCtrl = TextEditingController();

  String _gouvernorat = 'Tunis';
  int _quantity = 1;
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _productCtrl.dispose();
    _priceCtrl.dispose();
    _villeCtrl.dispose();
    _addressCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  void _pickProduct(ProductModel p) {
    HapticFeedback.selectionClick();
    setState(() {
      _productCtrl.text = p.nom;
      _priceCtrl.text = (p.price * _quantity).toStringAsFixed(0);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    HapticFeedback.mediumImpact();

    try {
      final total = double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0;
      await widget.state.createQuickOrder(
        clientName: _nameCtrl.text,
        phone: _phoneCtrl.text,
        productName: _productCtrl.text,
        quantity: _quantity,
        totalPrice: total,
        gouvernorat: _gouvernorat,
        ville: _villeCtrl.text,
        adresse: _addressCtrl.text,
        commentaire: _commentCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nouvelle commande ajoutée !')),
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
    final products = widget.state.products;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: XfyColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Nouvelle commande',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: XfyColors.ink,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollCtrl,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      16,
                      20,
                      MediaQuery.of(context).viewInsets.bottom + 24,
                    ),
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nom du client *',
                          prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Téléphone *',
                          hintText: 'ex: 92 557 500',
                          prefixIcon: Icon(Icons.phone_outlined, size: 20),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
                      ),
                      const SizedBox(height: 14),

                      // Quick Product Picker from catalog
                      if (products.isNotEmpty) ...[
                        const Text(
                          'Choisir un produit rapide',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: XfyColors.inkSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: products.take(12).length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (_, idx) {
                              final p = products[idx];
                              return ActionChip(
                                label: Text(
                                  '${p.nom} (${p.price.toStringAsFixed(0)} DT)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                backgroundColor: XfyColors.canvas,
                                side: const BorderSide(color: XfyColors.border),
                                onPressed: () => _pickProduct(p),
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      TextFormField(
                        controller: _productCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Produit *',
                          prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Champ requis'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _priceCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Total (DT) *',
                                prefixIcon: Icon(Icons.payments_outlined, size: 20),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty)
                                  ? 'Requis'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            height: 52,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: XfyColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: XfyColors.border),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  onPressed: _quantity > 1
                                      ? () => setState(() => _quantity--)
                                      : null,
                                  icon: const Icon(Icons.remove_rounded, size: 18),
                                ),
                                Text(
                                  '$_quantity',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => setState(() => _quantity++),
                                  icon: const Icon(Icons.add_rounded, size: 18),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _gouvernorat,
                        decoration: const InputDecoration(
                          labelText: 'Gouvernorat',
                          prefixIcon: Icon(Icons.map_outlined, size: 20),
                        ),
                        items: _gouvernorats
                            .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _gouvernorat = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _villeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ville / Délégation',
                          prefixIcon: Icon(Icons.location_city_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Adresse complète',
                          prefixIcon: Icon(Icons.home_outlined, size: 20),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _commentCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Commentaire (optionnel)',
                          prefixIcon: Icon(Icons.notes_rounded, size: 20),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.3,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Créer la commande'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
