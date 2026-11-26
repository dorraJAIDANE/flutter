import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../state/app_state.dart';

class _DraftVariantRow {
  _DraftVariantRow({
    required this.value,
    required double defaultPrice,
    int defaultStock = 10,
  })  : priceCtrl = TextEditingController(
          text: defaultPrice > 0 ? defaultPrice.toStringAsFixed(0) : '',
        ),
        stockCtrl = TextEditingController(text: '$defaultStock');

  final String value;
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;

  void dispose() {
    priceCtrl.dispose();
    stockCtrl.dispose();
  }
}

/// Feuille d'ajout de produit complète (Android & iPhone), alignée sur
/// `AddProduitComponent` Web (`POST /api/produits` multipart `produit` + `images`).
class AddProductSheet extends StatefulWidget {
  const AddProductSheet({super.key, required this.state});

  final AppState state;

  @override
  State<AddProductSheet> createState() => _AddProductSheetState();
}

class _AddProductSheetState extends State<AddProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  final _nameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _comparePriceCtrl = TextEditingController();
  final _costPriceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '20');

  // Variantes simples (1 type, ex: Taille / Couleur)
  final _variantTypeCtrl = TextEditingController(text: 'Taille');
  final _variantValueInputCtrl = TextEditingController();
  final List<_DraftVariantRow> _variantRows = [];
  bool _hasVariants = false;

  bool _slugEditedManually = false;
  String _inventory = 'IN_STOCK'; // IN_STOCK | LIMITED | OUT_OF_STOCK
  bool _freeShipping = false;

  // Photos sélectionnées
  final List<XFile> _pickedImages = [];

  // Catégories & sous-catégories
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _subcategories = [];
  int? _selectedCategoryId;
  final Set<int> _selectedSubcategoryIds = {};
  bool _loadingCategories = false;
  bool _loadingSubcategories = false;

  bool _submitting = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onNameChanged);
    _loadCategories();
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    _skuCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _comparePriceCtrl.dispose();
    _costPriceCtrl.dispose();
    _stockCtrl.dispose();
    _variantTypeCtrl.dispose();
    _variantValueInputCtrl.dispose();
    for (final r in _variantRows) {
      r.dispose();
    }
    super.dispose();
  }

  String _normalizeSlug(String input) {
    final stripped = XfyFormatters.stripAccents(input.trim());
    return stripped
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), '')
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
  }

  void _onNameChanged() {
    if (_slugEditedManually) return;
    final generated = _normalizeSlug(_nameCtrl.text);
    if (_slugCtrl.text != generated) {
      _slugCtrl.text = generated;
    }
  }

  Future<void> _loadCategories() async {
    final storeId = widget.state.selectedStore?.id;
    if (storeId == null) return;
    setState(() => _loadingCategories = true);
    final cats = await widget.state.api.getCategoriesByStore(storeId);
    if (!mounted) return;
    setState(() {
      _categories = cats;
      _loadingCategories = false;
    });
  }

  Future<void> _onSelectCategory(int? categoryId) async {
    final storeId = widget.state.selectedStore?.id;
    setState(() {
      _selectedCategoryId = categoryId;
      _subcategories = [];
      _selectedSubcategoryIds.clear();
    });
    if (categoryId == null || storeId == null) return;
    setState(() => _loadingSubcategories = true);
    final subs = await widget.state.api
        .getSubcategoriesByCategory(categoryId, storeId);
    if (!mounted) return;
    setState(() {
      _subcategories = subs;
      _loadingSubcategories = false;
    });
  }

  Future<void> _pickFromGallery() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 85);
      if (files.isEmpty || !mounted) return;
      setState(() => _pickedImages.addAll(files));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = 'Impossible d\'ouvrir la galerie : $e');
    }
  }

  Future<void> _pickFromCamera() async {
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _pickedImages.add(file));
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMsg = 'Impossible d\'ouvrir la caméra : $e');
    }
  }

  void _addVariantValue() {
    final val = _variantValueInputCtrl.text.trim();
    if (val.isEmpty) return;
    if (_variantRows.any((r) => r.value.toLowerCase() == val.toLowerCase())) {
      _variantValueInputCtrl.clear();
      return;
    }
    final defaultPrice =
        double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    setState(() {
      _variantRows.add(
        _DraftVariantRow(value: val, defaultPrice: defaultPrice),
      );
      _variantValueInputCtrl.clear();
    });
  }

  void _removeVariantRow(int idx) {
    setState(() {
      _variantRows[idx].dispose();
      _variantRows.removeAt(idx);
    });
  }

  Future<void> _submit() async {
    setState(() => _errorMsg = null);
    if (!_formKey.currentState!.validate()) return;

    final storeId = widget.state.selectedStore?.id;
    if (storeId == null) {
      setState(() => _errorMsg = 'Aucune boutique sélectionnée.');
      return;
    }

    final nom = _nameCtrl.text.trim();
    final slug = _slugCtrl.text.trim().isNotEmpty
        ? _slugCtrl.text.trim()
        : _normalizeSlug(nom);
    if (slug.isEmpty || !RegExp(r'^[a-z0-9-]+$').hasMatch(slug)) {
      setState(() {
        _errorMsg =
            'Le slug doit contenir uniquement des lettres minuscules, chiffres et tirets.';
      });
      return;
    }

    double? parseOpt(String raw) {
      final t = raw.trim().replaceAll(',', '.');
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    final generalPrice = parseOpt(_priceCtrl.text) ?? 0;
    final compareAt = parseOpt(_comparePriceCtrl.text);
    final costPrice = parseOpt(_costPriceCtrl.text);

    if (!_hasVariants && generalPrice <= 0) {
      setState(() => _errorMsg = 'Le prix doit être strictement supérieur à 0.');
      return;
    }
    if (compareAt != null && generalPrice > 0 && compareAt <= generalPrice) {
      setState(() {
        _errorMsg = 'Le prix barré doit être supérieur au prix de vente.';
      });
      return;
    }

    final variantTypesPayload = <Map<String, dynamic>>[];
    final variantsPayload = <Map<String, dynamic>>[];
    double effectiveBasePrice = generalPrice;

    if (_hasVariants) {
      final typeName = _variantTypeCtrl.text.trim();
      if (typeName.isEmpty || _variantRows.isEmpty) {
        setState(() {
          _errorMsg =
              'Ajoutez au moins une valeur de variante (ex: S, M, L) ou désactivez les variantes.';
        });
        return;
      }
      variantTypesPayload.add({
        'nom': typeName,
        'valeurs': _variantRows.map((r) => {'valeur': r.value}).toList(),
      });
      for (final row in _variantRows) {
        final vp = parseOpt(row.priceCtrl.text) ?? generalPrice;
        if (vp <= 0) {
          setState(() {
            _errorMsg = 'Veuillez saisir un prix > 0 pour la variante "${row.value}".';
          });
          return;
        }
        if (effectiveBasePrice <= 0) effectiveBasePrice = vp;
        final vs = int.tryParse(row.stockCtrl.text.trim()) ?? 0;
        variantsPayload.add({
          'option1': row.value,
          'option2': null,
          'option3': null,
          'price': vp,
          'stock': vs < 0 ? 0 : vs,
          'visible': true,
          'imageUrl': null,
        });
      }
    }

    final simpleStock = !_hasVariants
        ? (int.tryParse(_stockCtrl.text.trim()) ?? 0).clamp(0, 999999)
        : null;

    final productData = <String, dynamic>{
      'nom': nom,
      'sku': _skuCtrl.text.trim(),
      'slug': slug,
      'description': _descCtrl.text.trim(),
      'price': effectiveBasePrice,
      'compareAtPrice': compareAt,
      'costPrice': costPrice,
      'inventory': _inventory,
      'sousCategories': _selectedSubcategoryIds.map((id) => {'id': id}).toList(),
      'store': {'id': storeId},
      'produitsSuggeres': const [],
      'livraisonGratuite': _freeShipping,
      'variantTypes': variantTypesPayload,
      'variants': variantsPayload,
      'bundlesEnabled': false,
      'bundles': const [],
      'marketingImages': const [],
    };

    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      await widget.state.createProduct(
        productData: productData,
        imagePaths: _pickedImages.map((f) => f.path).toList(),
        initialSimpleStock: simpleStock,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: XfyColors.emerald,
          content: Text('Produit "$nom" ajouté avec succès !'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMsg = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.65,
      maxChildSize: 0.96,
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
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: XfyColors.brandGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.add_box_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Ajouter un produit',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: XfyColors.ink,
                            ),
                          ),
                          Text(
                            'Synchronisé immédiatement avec votre boutique XFY',
                            style: TextStyle(
                              fontSize: 12,
                              color: XfyColors.inkSecondary,
                            ),
                          ),
                        ],
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
                      // 1. Photos du produit
                      const Text(
                        'Photos du produit',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: XfyColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                              ),
                              onPressed: _pickFromGallery,
                              icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 19,
                              ),
                              label: const Text('Galerie'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                              ),
                              onPressed: _pickFromCamera,
                              icon: const Icon(
                                Icons.photo_camera_outlined,
                                size: 19,
                              ),
                              label: const Text('Caméra'),
                            ),
                          ),
                        ],
                      ),
                      if (_pickedImages.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 88,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _pickedImages.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, idx) {
                              final img = _pickedImages[idx];
                              return Stack(
                                children: [
                                  Container(
                                    width: 84,
                                    height: 84,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: idx == 0
                                            ? XfyColors.primaryVibrant
                                            : XfyColors.border,
                                        width: idx == 0 ? 2 : 1,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: Image.file(
                                      File(img.path),
                                      fit: BoxFit.cover,
                                      cacheWidth: 200,
                                      cacheHeight: 200,
                                    ),
                                  ),
                                  Positioned(
                                    top: 3,
                                    right: 3,
                                    child: GestureDetector(
                                      onTap: () => setState(
                                        () => _pickedImages.removeAt(idx),
                                      ),
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: const BoxDecoration(
                                          color: Colors.black87,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (idx == 0)
                                    Positioned(
                                      left: 4,
                                      bottom: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: XfyColors.primaryVibrant,
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                        child: const Text(
                                          'Principale',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      // 2. Informations générales
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Nom du produit *',
                          hintText: 'Ex: Robe d\'été coton',
                          prefixIcon: Icon(Icons.shopping_bag_outlined, size: 20),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().length < 3) {
                            return 'Minimum 3 caractères requis';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _slugCtrl,
                              onChanged: (_) => _slugEditedManually = true,
                              decoration: InputDecoration(
                                labelText: 'Slug URL *',
                                hintText: 'robe-dete-coton',
                                prefixIcon:
                                    const Icon(Icons.link_rounded, size: 20),
                                suffixIcon: _slugEditedManually
                                    ? IconButton(
                                        tooltip: 'Régénérer',
                                        icon: const Icon(
                                          Icons.refresh_rounded,
                                          size: 18,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _slugEditedManually = false;
                                            _slugCtrl.text =
                                                _normalizeSlug(_nameCtrl.text);
                                          });
                                        },
                                      )
                                    : null,
                              ),
                              validator: (v) {
                                final s = (v ?? '').trim();
                                if (s.isEmpty) return 'Slug requis';
                                if (!RegExp(r'^[a-z0-9-]+$').hasMatch(s)) {
                                  return 'Minuscules, chiffres et -';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 118,
                            child: TextFormField(
                              controller: _skuCtrl,
                              decoration: const InputDecoration(
                                labelText: 'SKU',
                                hintText: 'Optionnel',
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),
                      // 3. Tarification
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _priceCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Prix (DT) *',
                                prefixIcon:
                                    Icon(Icons.payments_outlined, size: 20),
                              ),
                              validator: (v) {
                                if (_hasVariants) return null;
                                final val = double.tryParse(
                                  (v ?? '').trim().replaceAll(',', '.'),
                                );
                                if (val == null || val <= 0) {
                                  return 'Prix > 0 requis';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _comparePriceCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Prix barré (DT)',
                                hintText: 'Optionnel',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _costPriceCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Prix d\'achat (DT)',
                                hintText: 'Optionnel',
                                prefixIcon:
                                    Icon(Icons.sell_outlined, size: 19),
                              ),
                            ),
                          ),
                          if (!_hasVariants) ...[
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 120,
                              child: TextFormField(
                                controller: _stockCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Stock',
                                  prefixIcon:
                                      Icon(Icons.inventory_outlined, size: 19),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: _inventory,
                        decoration: const InputDecoration(
                          labelText: 'Disponibilité',
                          prefixIcon:
                              Icon(Icons.check_circle_outline_rounded, size: 20),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'IN_STOCK',
                            child: Text('En stock'),
                          ),
                          DropdownMenuItem(
                            value: 'LIMITED',
                            child: Text('Stock limité'),
                          ),
                          DropdownMenuItem(
                            value: 'OUT_OF_STOCK',
                            child: Text('Rupture de stock'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _inventory = v);
                        },
                      ),

                      // 4. Catégorie & Sous-catégories
                      if (_categories.isNotEmpty || _loadingCategories) ...[
                        const SizedBox(height: 14),
                        DropdownButtonFormField<int?>(
                          initialValue: _selectedCategoryId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Catégorie (optionnel)',
                            prefixIcon: const Icon(
                              Icons.category_outlined,
                              size: 20,
                            ),
                            suffixIcon: _loadingCategories
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : null,
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Aucune catégorie'),
                            ),
                            ..._categories.map((cat) {
                              final id = cat['id'] is num
                                  ? (cat['id'] as num).toInt()
                                  : int.tryParse('${cat['id']}');
                              final name =
                                  (cat['nom'] ?? cat['name'] ?? 'Catégorie')
                                      .toString();
                              return DropdownMenuItem<int?>(
                                value: id,
                                child: Text(
                                  name,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                          ],
                          onChanged: _onSelectCategory,
                        ),
                        if (_loadingSubcategories)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: LinearProgressIndicator(minHeight: 2),
                          )
                        else if (_subcategories.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Sous-catégories',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: XfyColors.inkSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: _subcategories.map((sc) {
                              final id = sc['id'] is num
                                  ? (sc['id'] as num).toInt()
                                  : int.tryParse('${sc['id']}') ?? 0;
                              final name =
                                  (sc['nom'] ?? sc['name'] ?? 'Sous-catégorie')
                                      .toString();
                              final selected =
                                  _selectedSubcategoryIds.contains(id);
                              return FilterChip(
                                label: Text(name),
                                selected: selected,
                                onSelected: (sel) {
                                  setState(() {
                                    if (sel) {
                                      _selectedSubcategoryIds.add(id);
                                    } else {
                                      _selectedSubcategoryIds.remove(id);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ],

                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _descCtrl,
                        maxLines: 3,
                        minLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          hintText:
                              'Décrivez les caractéristiques du produit...',
                          alignLabelWithHint: true,
                        ),
                      ),

                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Livraison gratuite',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Offrir les frais de livraison sur ce produit',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _freeShipping,
                        onChanged: (v) => setState(() => _freeShipping = v),
                      ),

                      // 5. Variantes optionnelles
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Produit avec variantes',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Tailles (S, M, L), couleurs, pointures...',
                          style: TextStyle(fontSize: 12),
                        ),
                        value: _hasVariants,
                        onChanged: (v) => setState(() => _hasVariants = v),
                      ),
                      if (_hasVariants) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: XfyColors.canvas,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: XfyColors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: _variantTypeCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Nom option (ex: Taille, Couleur)',
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _variantValueInputCtrl,
                                      decoration: const InputDecoration(
                                        hintText: 'Valeur (ex: M, Noir, 40)...',
                                      ),
                                      onSubmitted: (_) => _addVariantValue(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 48),
                                    ),
                                    onPressed: _addVariantValue,
                                    child: const Text('Ajouter'),
                                  ),
                                ],
                              ),
                              if (_variantRows.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                ...List.generate(_variantRows.length, (i) {
                                  final row = _variantRows[i];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: XfyColors.primarySoft,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            row.value,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: XfyColors.primaryDark,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: row.priceCtrl,
                                            keyboardType: const TextInputType
                                                .numberWithOptions(
                                              decimal: true,
                                            ),
                                            decoration: const InputDecoration(
                                              labelText: 'Prix',
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 72,
                                          child: TextField(
                                            controller: row.stockCtrl,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: 'Stock',
                                              isDense: true,
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () => _removeVariantRow(i),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 19,
                                            color: XfyColors.rose,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      ],

                      if (_errorMsg != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: XfyColors.roseSoft,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: XfyColors.rose.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                color: XfyColors.rose,
                                size: 19,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMsg!,
                                  style: const TextStyle(
                                    color: XfyColors.rose,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: XfyColors.primaryVibrant,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                        ),
                        onPressed: _submitting ? null : _submit,
                        icon: _submitting
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.3,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 20),
                        label: Text(
                          _submitting
                              ? 'Publication en cours...'
                              : 'Publier le produit',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
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
