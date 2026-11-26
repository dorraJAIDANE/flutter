import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/product_model.dart';
import '../../state/app_state.dart';
import '../widgets/xfy_image.dart';

// Palette exacte de `add-produit.component.scss` Web XFY
const Color _kWebNavy = Color(0xFF1E2A78);
const Color _kWebOrange = Color(0xFFF07D2A);
const Color _kWebBorder = Color(0xFFDDE1EF);
const Color _kWebInputBg = Color(0xFFFAFBFF);

class _DraftVariantType {
  _DraftVariantType({String name = '', List<String>? initialValues})
      : nameCtrl = TextEditingController(text: name),
        valueCtrls = (initialValues ?? [''])
            .map((v) => TextEditingController(text: v))
            .toList();

  final TextEditingController nameCtrl;
  final List<TextEditingController> valueCtrls;
  bool isEditing = true;

  List<String> get nonEmptyValues => valueCtrls
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  void dispose() {
    nameCtrl.dispose();
    for (final c in valueCtrls) {
      c.dispose();
    }
  }
}

class _DraftVariantCombo {
  _DraftVariantCombo({
    required this.key,
    required this.options,
    required double defaultPrice,
    int defaultStock = 0,
  })  : priceCtrl = TextEditingController(
          text: defaultPrice > 0 ? defaultPrice.toStringAsFixed(2) : '',
        ),
        stockCtrl = TextEditingController(text: '$defaultStock');

  final String key;
  final List<String?> options; // length up to 3
  final TextEditingController priceCtrl;
  final TextEditingController stockCtrl;
  bool selected = true;
  XFile? imageFile;

  String get displayLabel =>
      options.where((e) => e != null && e.isNotEmpty).join(' / ');

  void dispose() {
    priceCtrl.dispose();
    stockCtrl.dispose();
  }
}

class _DraftBundleOffer {
  _DraftBundleOffer({
    required this.id,
    required String title,
    required String subtitle,
    required int quantity,
    required this.offerType,
    double discountValue = 10,
    int freeQuantity = 1,
    String giftName = '',
    this.freeShipping = false,
    String badgeText = '',
    this.badgeColor = '#f07d2a',
    this.isDefault = false,
  })  : titleCtrl = TextEditingController(text: title),
        subtitleCtrl = TextEditingController(text: subtitle),
        quantityCtrl = TextEditingController(text: '$quantity'),
        discountCtrl = TextEditingController(
          text: discountValue > 0 ? _fmtNum(discountValue) : '',
        ),
        freeQtyCtrl = TextEditingController(text: '$freeQuantity'),
        giftNameCtrl = TextEditingController(text: giftName),
        badgeTextCtrl = TextEditingController(text: badgeText);

  static String _fmtNum(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toString();

  final String id;
  final TextEditingController titleCtrl;
  final TextEditingController subtitleCtrl;
  final TextEditingController quantityCtrl;
  String offerType;
  final TextEditingController discountCtrl;
  final TextEditingController freeQtyCtrl;
  int? giftProductId;
  final TextEditingController giftNameCtrl;
  String? giftImageUrl;
  bool freeShipping;
  final TextEditingController badgeTextCtrl;
  String badgeColor;
  bool isDefault;

  int get quantity =>
      (int.tryParse(quantityCtrl.text.trim()) ?? 1).clamp(1, 999);
  double get discountValue =>
      double.tryParse(discountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
  int get freeQuantity =>
      (int.tryParse(freeQtyCtrl.text.trim()) ?? 1).clamp(1, 99);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': titleCtrl.text.trim(),
        'subtitle': subtitleCtrl.text.trim(),
        'quantity': quantity,
        'offerType': offerType,
        'discountValue': discountValue,
        'freeQuantity': freeQuantity,
        'giftProductId': giftProductId,
        'giftName': giftNameCtrl.text.trim(),
        'giftImageUrl': giftImageUrl,
        'freeShipping': freeShipping,
        'badgeText': badgeTextCtrl.text.trim(),
        'badgeColor': badgeColor,
        'isDefault': isDefault,
      };

  void dispose() {
    titleCtrl.dispose();
    subtitleCtrl.dispose();
    quantityCtrl.dispose();
    discountCtrl.dispose();
    freeQtyCtrl.dispose();
    giftNameCtrl.dispose();
    badgeTextCtrl.dispose();
  }
}

class _DraftMarketingItem {
  _DraftMarketingItem({
    required this.id,
    this.imageUrl,
    this.localPath,
    this.headline,
    this.prompt,
  });

  final String id;
  String? imageUrl;
  String? localPath;
  String? headline;
  String? prompt;
}

/// Page plein écran **Boutique → Ajouter un Produit**, 100 % calquée sur
/// `AddProduitComponent` Web (`add-produit.component.html` + `.scss` + `.ts`)
/// et compatible Android & iPhone.
class AddProductScreen extends StatefulWidget {
  const AddProductScreen({super.key, required this.state});

  final AppState state;

  @override
  State<AddProductScreen> createState() => _AddProductScreenState();
}

class _AddProductScreenState extends State<AddProductScreen> {
  static const List<({String label, String color})> _badgePresets = [
    (label: '🔥 Populaire', color: '#f07d2a'),
    (label: '⭐ Meilleure Offre', color: '#10b981'),
    (label: '🎁 Cadeau Offert', color: '#8b5cf6'),
    (label: '🚚 Livraison Gratuite', color: '#0ea5e9'),
    (label: '⚡ Offre Limitée', color: '#ef4444'),
    (label: '💎 Pack Économique', color: '#1e2a78'),
  ];

  static const List<String> _badgeColorChoices = [
    '#f07d2a',
    '#10b981',
    '#8b5cf6',
    '#0ea5e9',
    '#ef4444',
    '#1e2a78',
    '#eab308',
    '#ec4899',
  ];

  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  // 1. Détails du produit
  final _nameCtrl = TextEditingController();
  final _slugCtrl = TextEditingController();
  final _skuCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _slugManuallyEdited = false;

  // 2. Tarification / Promotion / Inventaire / Livraison gratuite
  final _priceCtrl = TextEditingController();
  final _comparePriceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '20');
  DateTime? _promotionStart;
  String _inventory = 'IN_STOCK';
  bool _livraisonGratuite = false;

  // 3. Images globales du produit
  final List<XFile> _globalFiles = [];
  String? _imageError;

  // 4. Images de description marketing (Upload + IA XFY)
  final List<_DraftMarketingItem> _marketingItems = [];
  bool _isUploadingMarketing = false;
  bool _isGeneratingAiMarketing = false;
  int _aiProgress = 0;
  String _aiStepLabel = '';

  // 5. Catégories & Sous-catégories
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _subcategories = [];
  int? _selectedCategoryId;
  final Set<int> _selectedSubcategoryIds = {};
  bool _loadingCategories = false;
  bool _loadingSubcategories = false;

  // 6. Variantes (jusqu'à 3 types, simple & groupé exactement comme Web)
  bool _showVariants = false;
  final List<_DraftVariantType> _variantTypes = [];
  final Map<String, _DraftVariantCombo> _comboMap = {};
  List<_DraftVariantCombo> _combos = [];
  String _groupBy = '';
  final Map<String, XFile> _groupImages = {};
  final Map<String, bool> _groupExpanded = {};

  // 7. Produits suggérés
  final Set<int> _suggestedProductIds = {};

  // 8. Offres & Packs (Bundles)
  bool _bundlesEnabled = false;
  final List<_DraftBundleOffer> _bundles = [];
  int _selectedPreviewBundleIdx = 0;

  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onNameChanged);
    _priceCtrl.addListener(_refreshPreview);
    _loadCategories();
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _priceCtrl.removeListener(_refreshPreview);
    _nameCtrl.dispose();
    _slugCtrl.dispose();
    _skuCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _comparePriceCtrl.dispose();
    _stockCtrl.dispose();
    for (final vt in _variantTypes) {
      vt.dispose();
    }
    for (final c in _comboMap.values) {
      c.dispose();
    }
    for (final b in _bundles) {
      b.dispose();
    }
    super.dispose();
  }

  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  String _getSlugPrefix() {
    final store = widget.state.selectedStore;
    final raw = (store?.customDomain?.trim().isNotEmpty == true)
        ? store!.customDomain!.trim()
        : (store?.subdomain?.trim().isNotEmpty == true)
            ? '${store!.subdomain!.trim()}.xfy.tn'
            : 'xfy.tn';
    final clean = raw.replaceFirst(RegExp(r'^https?://'), '');
    return '$clean/products/';
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
    if (_slugManuallyEdited) return;
    final next = _normalizeSlug(_nameCtrl.text);
    if (_slugCtrl.text != next) {
      _slugCtrl.text = next;
    }
  }

  void _resetSlugManualEdit() {
    HapticFeedback.selectionClick();
    setState(() {
      _slugManuallyEdited = false;
      _slugCtrl.text = _normalizeSlug(_nameCtrl.text);
    });
  }

  // ---- Rich text description toolbar helpers ----
  void _wrapDescriptionTag(String openTag, String closeTag, {String sample = 'texte'}) {
    HapticFeedback.selectionClick();
    final sel = _descCtrl.selection;
    final text = _descCtrl.text;
    if (sel.isValid && sel.start >= 0 && sel.end > sel.start) {
      final selected = text.substring(sel.start, sel.end);
      final updated =
          '${text.substring(0, sel.start)}$openTag$selected$closeTag${text.substring(sel.end)}';
      _descCtrl.value = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(
          offset: sel.start + openTag.length + selected.length + closeTag.length,
        ),
      );
    } else {
      final pos = sel.isValid && sel.start >= 0 ? sel.start : text.length;
      final inserted = '$openTag$sample$closeTag';
      final updated = '${text.substring(0, pos)}$inserted${text.substring(pos)}';
      _descCtrl.value = TextEditingValue(
        text: updated,
        selection: TextSelection(
          baseOffset: pos + openTag.length,
          extentOffset: pos + openTag.length + sample.length,
        ),
      );
    }
  }

  Future<void> _insertDescriptionLink() async {
    final urlCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Insérer un lien'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: labelCtrl,
              decoration: const InputDecoration(labelText: 'Texte du lien'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'URL (https://...)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _kWebNavy),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Insérer'),
          ),
        ],
      ),
    );
    if (ok == true && urlCtrl.text.trim().isNotEmpty) {
      final u = urlCtrl.text.trim();
      final l = labelCtrl.text.trim().isEmpty ? u : labelCtrl.text.trim();
      _wrapDescriptionTag('<a href="$u">', '</a>', sample: l);
    }
    urlCtrl.dispose();
    labelCtrl.dispose();
  }

  void _stripDescriptionHtml() {
    HapticFeedback.selectionClick();
    final cleaned = _descCtrl.text.replaceAll(RegExp(r'<[^>]*>'), '');
    _descCtrl.text = cleaned;
  }

  // ---- Categories ----
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

  Future<void> _onCategorySelected(int? categoryId) async {
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

  // ---- Global Product Images ----
  Future<void> _pickGlobalImages({required bool camera}) async {
    setState(() => _imageError = null);
    try {
      if (camera) {
        final f = await _picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        if (f != null && mounted) setState(() => _globalFiles.add(f));
      } else {
        final files = await _picker.pickMultiImage(imageQuality: 85);
        if (files.isNotEmpty && mounted) setState(() => _globalFiles.addAll(files));
      }
    } catch (e) {
      if (mounted) setState(() => _imageError = 'Erreur sélection image : $e');
    }
  }

  // ---- Marketing Images (Upload + AI Generation) ----
  Future<void> _pickMarketingImages() async {
    try {
      final files = await _picker.pickMultiImage(imageQuality: 88);
      if (files.isEmpty || !mounted) return;
      setState(() => _isUploadingMarketing = true);
      final urls = await widget.state.api
          .uploadMarketingImages(files.map((e) => e.path).toList());
      if (!mounted) return;
      setState(() {
        for (int i = 0; i < urls.length; i++) {
          _marketingItems.add(
            _DraftMarketingItem(
              id: 'mkt-${DateTime.now().millisecondsSinceEpoch}-$i',
              imageUrl: urls[i],
              localPath: i < files.length ? files[i].path : null,
            ),
          );
        }
        _isUploadingMarketing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploadingMarketing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    }
  }

  Future<void> _openAiMarketingDialog() async {
    if (_nameCtrl.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Entrez d\'abord le nom du produit pour générer par IA.'),
        ),
      );
      return;
    }

    String aiLang = 'tn';
    String aiStyle = 'AUTO';
    int aiCount = 4;
    final instructionsCtrl = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  const SizedBox(height: 14),
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: _kWebOrange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Générer des images marketing par IA',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w800,
                            color: _kWebNavy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Langue du texte sur les visuels',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final opt in const [
                        ('tn', 'Arabe tunisien (تونسي)'),
                        ('ar', 'Arabe classique'),
                        ('fr', 'Français'),
                      ])
                        ChoiceChip(
                          label: Text(opt.$2),
                          selected: aiLang == opt.$1,
                          onSelected: (_) => setModal(() => aiLang = opt.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Style visuel',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      for (final opt in const [
                        ('AUTO', '✨ Varié (IA)'),
                        ('MODERN', '🤍 Moderne'),
                        ('PREMIUM', '👑 Premium'),
                        ('DYNAMIC', '⚡ Dynamique'),
                        ('EDITORIAL', '📰 Éditorial'),
                      ])
                        ChoiceChip(
                          label: Text(opt.$2),
                          selected: aiStyle == opt.$1,
                          onSelected: (_) => setModal(() => aiStyle = opt.$1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Nombre d\'images',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [2, 4, 6, 8]
                        .map((n) => ChoiceChip(
                              label: Text('$n images'),
                              selected: aiCount == n,
                              onSelected: (_) => setModal(() => aiCount = n),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: instructionsCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Instructions supplémentaires (optionnel)',
                      hintText: 'Ex: Insister sur la qualité coton 100%...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _kWebNavy,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 19),
                    label: const Text('Lancer la génération IA'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final customInstr = instructionsCtrl.text.trim();
    instructionsCtrl.dispose();
    if (confirmed != true || !mounted) return;

    setState(() {
      _isGeneratingAiMarketing = true;
      _aiProgress = 5;
      _aiStepLabel = 'Démarrage de la génération IA...';
    });

    try {
      final config = <String, dynamic>{
        'productName': _nameCtrl.text.trim(),
        'price': double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.')),
        'compareAtPrice': double.tryParse(
          _comparePriceCtrl.text.trim().replaceAll(',', '.'),
        ),
        'description': _descCtrl.text.trim(),
        'language': aiLang,
        'style': aiStyle,
        'objectives': ['AUTO'],
        'imageCount': aiCount,
        'targetAudience': 'AUTO',
        'fontFamily': 'AUTO',
        'textColor': 'AUTO',
        'accentColor': 'AUTO',
        'fontSizeScale': 'AUTO',
        'textAlign': 'AUTO',
        'textTransform': 'AUTO',
        'backdropStyle': 'AUTO',
        'customInstructions': customInstr,
      };
      final job = await widget.state.api.startMarketingImagesJob(
        config: config,
        productPhotoPaths: _globalFiles.map((e) => e.path).toList(),
      );
      final jobId = job['jobId']?.toString();
      if (jobId == null || jobId.isEmpty) {
        throw Exception('Identifiant de génération IA introuvable.');
      }

      for (int attempt = 0; attempt < 90; attempt++) {
        await Future.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final st = await widget.state.api.getMarketingGenerationJobStatus(jobId);
        final status = (st['status'] ?? '').toString().toUpperCase();
        final completed = (st['completedCount'] is num)
            ? (st['completedCount'] as num).toInt()
            : 0;
        final total = (st['totalCount'] is num && (st['totalCount'] as num) > 0)
            ? (st['totalCount'] as num).toInt()
            : aiCount;
        setState(() {
          _aiProgress = ((completed / total) * 100).round().clamp(10, 95);
          _aiStepLabel =
              (st['stepLabel']?.toString().trim().isNotEmpty == true)
                  ? st['stepLabel'].toString()
                  : 'Génération IA ($completed/$total)...';
        });

        if (status == 'COMPLETED' || status == 'DONE') {
          final rawImages = (st['images'] ?? st['results']);
          if (rawImages is List) {
            setState(() {
              for (int i = 0; i < rawImages.length; i++) {
                final item = rawImages[i];
                if (item is Map) {
                  final url = (item['imageUrl'] ?? item['url'])?.toString();
                  if (url != null && url.trim().isNotEmpty) {
                    _marketingItems.add(
                      _DraftMarketingItem(
                        id: (item['id'] ?? 'ai-$i').toString(),
                        imageUrl: url.trim(),
                        headline: item['headline']?.toString(),
                        prompt: item['prompt']?.toString(),
                      ),
                    );
                  }
                }
              }
            });
          }
          break;
        }
        if (status == 'FAILED' || status == 'ERROR') {
          throw Exception(st['error']?.toString() ?? 'Échec génération IA');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: XfyColors.rose, content: Text('IA : $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGeneratingAiMarketing = false;
          _aiProgress = 0;
        });
      }
    }
  }

  // ---- Variants Engine (Simple & Grouped, up to 3 types, exactly like Web) ----
  void _toggleVariants(bool enabled) {
    HapticFeedback.selectionClick();
    setState(() {
      _showVariants = enabled;
      if (enabled && _variantTypes.isEmpty) {
        _variantTypes.add(_DraftVariantType(name: '', initialValues: ['']));
      }
      if (!enabled) {
        for (final vt in _variantTypes) {
          vt.dispose();
        }
        _variantTypes.clear();
        _combos = [];
        _groupBy = '';
      } else {
        _regenerateCombinations();
      }
    });
  }

  void _addVariantType() {
    if (_variantTypes.length >= 3) return;
    HapticFeedback.selectionClick();
    setState(() {
      _variantTypes.add(_DraftVariantType(name: '', initialValues: ['']));
      _regenerateCombinations();
    });
  }

  void _removeVariantType(int idx) {
    setState(() {
      _variantTypes[idx].dispose();
      _variantTypes.removeAt(idx);
      _regenerateCombinations();
    });
  }

  void _regenerateCombinations() {
    final validTypes = _variantTypes
        .where((t) => t.nameCtrl.text.trim().isNotEmpty && t.nonEmptyValues.isNotEmpty)
        .toList();

    if (validTypes.isEmpty) {
      _combos = [];
      _groupBy = '';
      return;
    }

    final typeNames = validTypes.map((t) => t.nameCtrl.text.trim()).toList();
    if (_groupBy.isEmpty || !typeNames.contains(_groupBy)) {
      _groupBy = typeNames.first;
    }

    // Produit cartésien des valeurs
    List<List<String>> acc = [[]];
    for (final vt in validTypes) {
      final vals = vt.nonEmptyValues;
      final next = <List<String>>[];
      for (final prefix in acc) {
        for (final v in vals) {
          next.add([...prefix, v]);
        }
      }
      acc = next;
    }

    final defaultPrice =
        double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.')) ?? 0;

    final built = <_DraftVariantCombo>[];
    for (final tuple in acc) {
      final key = tuple.join(' | ');
      final existing = _comboMap[key];
      if (existing != null) {
        built.add(existing);
      } else {
        final combo = _DraftVariantCombo(
          key: key,
          options: [
            tuple.isNotEmpty ? tuple[0] : null,
            tuple.length > 1 ? tuple[1] : null,
            tuple.length > 2 ? tuple[2] : null,
          ],
          defaultPrice: defaultPrice,
        );
        _comboMap[key] = combo;
        built.add(combo);
      }
    }
    _combos = built;
  }

  bool get _isGroupedVariantsView {
    final validCount = _variantTypes
        .where((t) => t.nameCtrl.text.trim().isNotEmpty && t.nonEmptyValues.isNotEmpty)
        .length;
    return validCount > 1 && _combos.isNotEmpty;
  }

  Map<String, List<_DraftVariantCombo>> _buildGroupedCombos() {
    final validTypes = _variantTypes
        .where((t) => t.nameCtrl.text.trim().isNotEmpty && t.nonEmptyValues.isNotEmpty)
        .toList();
    int groupIdx = validTypes
        .indexWhere((t) => t.nameCtrl.text.trim() == _groupBy);
    if (groupIdx < 0) groupIdx = 0;

    final map = <String, List<_DraftVariantCombo>>{};
    for (final c in _combos) {
      final gVal = (groupIdx < c.options.length ? c.options[groupIdx] : null) ??
          'Groupe';
      map.putIfAbsent(gVal, () => []).add(c);
    }
    return map;
  }

  Future<void> _pickComboImage(_DraftVariantCombo combo) async {
    try {
      final f = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (f != null && mounted) {
        setState(() => combo.imageFile = f);
      }
    } catch (_) {}
  }

  Future<void> _pickGroupImage(String groupName, List<_DraftVariantCombo> subs) async {
    try {
      final f = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (f != null && mounted) {
        setState(() {
          _groupImages[groupName] = f;
          for (final sub in subs) {
            sub.imageFile ??= f;
          }
        });
      }
    } catch (_) {}
  }

  // ---- Bundles Engine (100 % identical to Web `add-produit.component.ts`) ----
  void _onBundlesToggle(bool enabled) {
    HapticFeedback.selectionClick();
    setState(() {
      _bundlesEnabled = enabled;
      if (enabled && _bundles.isEmpty) {
        _addBundleOffer(
          title: 'Achetez 2 pièces (-10%)',
          subtitle: 'Économisez 10% sur votre commande',
          quantity: 2,
          offerType: 'PERCENTAGE_DISCOUNT',
          discountValue: 10,
          badgeText: '🔥 Populaire',
          badgeColor: '#f07d2a',
        );
      }
    });
  }

  void _addBundleOffer({
    String? title,
    String? subtitle,
    int? quantity,
    String offerType = 'PERCENTAGE_DISCOUNT',
    double? discountValue,
    int freeQuantity = 1,
    String giftName = '',
    bool freeShipping = false,
    String badgeText = '',
    String badgeColor = '#f07d2a',
    bool isDefault = false,
  }) {
    final nextQty = quantity ?? (_bundles.isEmpty ? 2 : _bundles.length + 1);
    final offer = _DraftBundleOffer(
      id: 'bundle-${DateTime.now().millisecondsSinceEpoch}-${_bundles.length}',
      title: title ?? 'Pack $nextQty pièces',
      subtitle: subtitle ?? 'Économisez en achetant en pack',
      quantity: nextQty,
      offerType: offerType,
      discountValue: discountValue ?? (offerType == 'PERCENTAGE_DISCOUNT' ? 10 : 0),
      freeQuantity: freeQuantity,
      giftName: giftName,
      freeShipping: freeShipping,
      badgeText: badgeText,
      badgeColor: badgeColor,
      isDefault: isDefault,
    );
    _bundles.add(offer);
    _selectedPreviewBundleIdx = _bundles.length - 1;
  }

  void _applyBundlePreset(String type) {
    HapticFeedback.selectionClick();
    setState(() {
      for (final b in _bundles) {
        b.dispose();
      }
      _bundles.clear();
      _bundlesEnabled = true;

      if (type == 'pack_1_2_3') {
        _addBundleOffer(
          title: '1 Pièce — Prix standard',
          subtitle: 'Tarif normal à l\'unité',
          quantity: 1,
          offerType: 'NO_DISCOUNT',
          discountValue: 0,
          isDefault: true,
        );
        _addBundleOffer(
          title: '2 Pièces (-10%)',
          subtitle: 'Économisez 10% sur les 2 pièces',
          quantity: 2,
          offerType: 'PERCENTAGE_DISCOUNT',
          discountValue: 10,
          badgeText: '🔥 Populaire',
          badgeColor: '#f07d2a',
        );
        _addBundleOffer(
          title: '3 Pièces (-20%) + Livraison Gratuite',
          subtitle: 'Notre meilleure offre économique',
          quantity: 3,
          offerType: 'PERCENTAGE_DISCOUNT',
          discountValue: 20,
          freeShipping: true,
          badgeText: '⭐ Meilleure Offre',
          badgeColor: '#10b981',
        );
      } else if (type == 'buy2_get1') {
        _addBundleOffer(
          title: '1 Pièce — Prix standard',
          subtitle: 'Tarif normal à l\'unité',
          quantity: 1,
          offerType: 'NO_DISCOUNT',
          discountValue: 0,
          isDefault: true,
        );
        _addBundleOffer(
          title: '2 Achetés = +1 Offert (3 Pièces)',
          subtitle: 'Payez 2 pièces et recevez la 3ème gratuitement !',
          quantity: 2,
          offerType: 'FREE_UNITS',
          freeQuantity: 1,
          badgeText: '🎁 +1 Gratuit',
          badgeColor: '#ef4444',
        );
      } else if (type == 'buy2_gift') {
        _addBundleOffer(
          title: '1 Pièce — Prix standard',
          subtitle: 'Tarif normal à l\'unité',
          quantity: 1,
          offerType: 'NO_DISCOUNT',
          discountValue: 0,
          isDefault: true,
        );
        _addBundleOffer(
          title: '2 Pièces (-10%) + Cadeau Offert',
          subtitle: 'Remise immédiate + un cadeau offert dans votre colis',
          quantity: 2,
          offerType: 'FREE_GIFT',
          discountValue: 10,
          giftName: 'Cadeau surprise offert',
          badgeText: '🎁 Cadeau Offert',
          badgeColor: '#8b5cf6',
        );
      }
      _selectedPreviewBundleIdx = 0;
    });
  }

  double _getPreviewBasePrice() {
    final p = double.tryParse(_priceCtrl.text.trim().replaceAll(',', '.'));
    if (p != null && p > 0) return p;
    if (_combos.isNotEmpty) {
      final vp = double.tryParse(
        _combos.first.priceCtrl.text.trim().replaceAll(',', '.'),
      );
      if (vp != null && vp > 0) return vp;
    }
    return 50;
  }

  double _calcBundleOriginal(_DraftBundleOffer b) {
    final base = _getPreviewBasePrice();
    if (b.offerType == 'FREE_UNITS') {
      return double.parse((base * (b.quantity + b.freeQuantity)).toStringAsFixed(2));
    }
    return double.parse((base * b.quantity).toStringAsFixed(2));
  }

  double _calcBundleFinal(_DraftBundleOffer b) {
    final base = _getPreviewBasePrice();
    final standardTotal = base * b.quantity;
    final val = b.discountValue;
    switch (b.offerType) {
      case 'PERCENTAGE_DISCOUNT':
        final clamped = val.clamp(0, 100);
        return double.parse(
          (standardTotal * (1 - clamped / 100)).clamp(0, double.infinity).toStringAsFixed(2),
        );
      case 'FIXED_DISCOUNT':
        return double.parse(
          (standardTotal - val.clamp(0, double.infinity))
              .clamp(0, double.infinity)
              .toStringAsFixed(2),
        );
      case 'FIXED_PRICE':
        return double.parse((val > 0 ? val : standardTotal).toStringAsFixed(2));
      case 'FREE_GIFT':
        if (val > 0) {
          return double.parse(
            (standardTotal * (1 - val.clamp(0, 100) / 100))
                .clamp(0, double.infinity)
                .toStringAsFixed(2),
          );
        }
        return double.parse(standardTotal.toStringAsFixed(2));
      case 'FREE_UNITS':
      case 'NO_DISCOUNT':
      default:
        return double.parse(standardTotal.toStringAsFixed(2));
    }
  }

  double _calcBundleSavings(_DraftBundleOffer b) {
    final diff = _calcBundleOriginal(b) - _calcBundleFinal(b);
    return diff > 0 ? double.parse(diff.toStringAsFixed(2)) : 0;
  }

  Color _parseHexColor(String hex, {Color fallback = _kWebOrange}) {
    final clean = hex.replaceFirst('#', '').trim();
    if (clean.length == 6) {
      final v = int.tryParse('FF$clean', radix: 16);
      if (v != null) return Color(v);
    }
    return fallback;
  }

  Future<void> _pickPromotionStart() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      initialDate: _promotionStart ?? now,
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: _promotionStart != null
          ? TimeOfDay.fromDateTime(_promotionStart!)
          : TimeOfDay.now(),
    );
    if (!mounted) return;
    setState(() {
      _promotionStart = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime?.hour ?? 0,
        pickedTime?.minute ?? 0,
      );
    });
  }

  String? _formatPromotionStartIso() {
    final d = _promotionStart;
    if (d == null) return null;
    String p2(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${p2(d.month)}-${p2(d.day)}T${p2(d.hour)}:${p2(d.minute)}:00';
  }

  // ---- Submit (100 % identical payload to `AddProduitComponent.onSubmit()`) ----
  Future<void> _onSubmit() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _errorMessage =
            'Veuillez remplir tous les champs obligatoires du produit.';
      });
      return;
    }

    final storeId = widget.state.selectedStore?.id;
    if (storeId == null) {
      setState(() => _errorMessage = 'Aucune boutique sélectionnée.');
      return;
    }

    double? parseOpt(String raw) {
      final t = raw.trim().replaceAll(',', '.');
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }

    double generalPrice = parseOpt(_priceCtrl.text) ?? 0;
    final compareAt = parseOpt(_comparePriceCtrl.text);

    if (!_showVariants && generalPrice <= 0) {
      setState(() {
        _errorMessage =
            'Le prix est requis et doit être strictement supérieur à 0.';
      });
      return;
    }
    if (compareAt != null) {
      if (compareAt <= 0) {
        setState(() {
          _errorMessage = 'Le prix barré doit être strictement supérieur à 0.';
        });
        return;
      }
      if (generalPrice > 0 && compareAt <= generalPrice) {
        setState(() {
          _errorMessage = 'Le prix barré doit être strictement supérieur au prix.';
        });
        return;
      }
    }

    final variantTypesClean = <Map<String, dynamic>>[];
    final variantsClean = <Map<String, dynamic>>[];
    final variantCombImgPaths = <String>[];
    final variantValImgPaths = <String>[];
    final variantValImgKeys = <String?>[];

    if (_showVariants) {
      _regenerateCombinations();
      final validTypes = _variantTypes
          .where((t) =>
              t.nameCtrl.text.trim().isNotEmpty && t.nonEmptyValues.isNotEmpty)
          .toList();
      if (validTypes.isEmpty || _combos.isEmpty) {
        setState(() {
          _errorMessage =
              'Veuillez définir au moins un type de variante et une valeur (ou désactiver les variantes).';
        });
        return;
      }

      for (final vt in validTypes) {
        variantTypesClean.add({
          'nom': vt.nameCtrl.text.trim(),
          'valeurs': vt.nonEmptyValues.map((v) => {'valeur': v}).toList(),
        });
      }

      for (final combo in _combos) {
        final rawP = parseOpt(combo.priceCtrl.text) ?? 0;
        final finalP = rawP > 0 ? rawP : generalPrice;
        if (finalP <= 0) {
          setState(() {
            _errorMessage =
                'Veuillez saisir un prix > 0 pour la variante "${combo.displayLabel}".';
          });
          return;
        }
        if (generalPrice <= 0) generalPrice = finalP;
        final stockVal = int.tryParse(combo.stockCtrl.text.trim()) ?? 0;
        final file = combo.imageFile;
        if (file != null) {
          variantCombImgPaths.add(file.path);
        }
        variantsClean.add({
          'option1': combo.options.isNotEmpty ? combo.options[0] : null,
          'option2': combo.options.length > 1 ? combo.options[1] : null,
          'option3': combo.options.length > 2 ? combo.options[2] : null,
          'price': finalP,
          'stock': stockVal < 0 ? 0 : stockVal,
          'visible': combo.selected,
          'imageUrl': file != null ? '/Uploads/${file.name}' : null,
        });
      }

      // Aligner variantValueImages dans l'ordre aplati des valeurs (comme Web)
      for (int tIdx = 0; tIdx < validTypes.length; tIdx++) {
        for (final val in validTypes[tIdx].nonEmptyValues) {
          XFile? matched = _groupImages[val];
          if (matched == null) {
            for (final c in _combos) {
              if (c.imageFile != null && c.options.contains(val)) {
                matched = c.imageFile;
                break;
              }
            }
          }
          if (matched != null) {
            variantValImgPaths.add(matched.path);
            variantValImgKeys.add('$tIdx:$val');
          } else {
            variantValImgKeys.add(null);
          }
        }
      }
    }

    final productData = <String, dynamic>{
      'nom': _nameCtrl.text.trim(),
      'sku': _skuCtrl.text.trim(),
      'slug': _slugCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'price': generalPrice,
      'compareAtPrice': compareAt,
      'inventory': _inventory,
      'promotionStart': _formatPromotionStartIso(),
      'sousCategories': _selectedSubcategoryIds.map((id) => {'id': id}).toList(),
      'store': {'id': storeId},
      'produitsSuggeres': _suggestedProductIds.map((id) => {'id': id}).toList(),
      'livraisonGratuite': _livraisonGratuite,
      'variantTypes': variantTypesClean,
      'variants': variantsClean,
      'bundlesEnabled': _bundlesEnabled,
      'bundles': _bundlesEnabled ? _bundles.map((b) => b.toJson()).toList() : [],
      'marketingImages': _marketingItems
          .where((m) => m.imageUrl != null && m.imageUrl!.isNotEmpty)
          .map((m) => {
                'id': m.id,
                'imageUrl': m.imageUrl,
                if (m.headline != null) 'headline': m.headline,
                if (m.prompt != null) 'prompt': m.prompt,
              })
          .toList(),
    };

    final simpleStock = !_showVariants
        ? (int.tryParse(_stockCtrl.text.trim()) ?? 0).clamp(0, 999999)
        : null;

    HapticFeedback.mediumImpact();
    setState(() => _isSubmitting = true);
    try {
      await widget.state.createProduct(
        productData: productData,
        imagePaths: _globalFiles.map((f) => f.path).toList(),
        variantCombinationImagePaths: variantCombImgPaths,
        variantValueImagePaths: variantValImgPaths,
        variantValueImageKeysDebug: variantValImgKeys,
        initialSimpleStock: simpleStock,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: XfyColors.emerald,
          content: Text('Produit ajouté avec succès !'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString();
      });
    }
  }

  // ---- UI Builders (exact Web cards & palette) ----
  Widget _webCard({
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EAF0)),
        boxShadow: [
          BoxShadow(
            color: _kWebNavy.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: 5),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: _kWebOrange, width: 2),
                  ),
                ),
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    color: _kWebNavy,
                  ),
                ),
              ),
              const Spacer(),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  InputDecoration _webInputDeco({
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: _kWebInputBg,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kWebBorder, width: 1.4),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kWebBorder, width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kWebNavy, width: 1.6),
      ),
    );
  }

  Widget _fieldLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final storeProducts = widget.state.products;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: _kWebNavy),
        ),
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Boutique',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _kWebOrange,
              ),
            ),
            Text(
              'Ajouter un Produit',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _kWebNavy,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE8EAF0)),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE8EAF0))),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    side: const BorderSide(color: _kWebBorder, width: 1.5),
                    foregroundColor: const Color(0xFF475569),
                  ),
                  onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                  child: const Text(
                    'Annuler',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _kWebNavy,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 46),
                  ),
                  onPressed: _isSubmitting ? null : _onSubmit,
                  child: _isSubmitting
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 10),
                            Text(
                              'Ajout en cours...',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ],
                        )
                      : const Text(
                          'Enregistrer',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            // 1. DÉTAILS DU PRODUIT
            _webCard(
              title: 'Détails du produit',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('Nom'),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: _webInputDeco(
                      hint: 'Entrez le nom du produit',
                    ),
                    validator: (v) => (v == null || v.trim().length < 3)
                        ? 'Le nom est requis et doit contenir au moins 3 caractères.'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel('Slug'),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: _kWebInputBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kWebBorder, width: 1.4),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFEEF0FA),
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(6),
                                  ),
                                ),
                                child: Text(
                                  _getSlugPrefix(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: _kWebNavy,
                                  ),
                                ),
                              ),
                              TextFormField(
                                controller: _slugCtrl,
                                onChanged: (_) => _slugManuallyEdited = true,
                                decoration: const InputDecoration(
                                  hintText: 'Entrez le slug',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  fillColor: Colors.transparent,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 9,
                                  ),
                                ),
                                validator: (v) {
                                  final s = (v ?? '').trim();
                                  if (s.isEmpty) return 'Le slug est requis.';
                                  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(s)) {
                                    return 'Lettres minuscules, chiffres et tirets uniquement.';
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Réinitialiser à la suggestion automatique',
                        style: IconButton.styleFrom(
                          backgroundColor: _kWebNavy,
                          foregroundColor: Colors.white,
                          fixedSize: const Size(44, 44),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _resetSlugManualEdit,
                        icon: const Icon(Icons.sync_rounded, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel('SKU'),
                  TextFormField(
                    controller: _skuCtrl,
                    decoration: _webInputDeco(hint: 'Entrez le SKU'),
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel('Description'),
                  Container(
                    decoration: BoxDecoration(
                      color: _kWebInputBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _kWebBorder, width: 1.4),
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF3F5FC),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(7),
                            ),
                            border: Border(
                              bottom: BorderSide(color: _kWebBorder),
                            ),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _EditorToolBtn(
                                  icon: Icons.format_bold_rounded,
                                  tooltip: 'Gras',
                                  onTap: () => _wrapDescriptionTag('<b>', '</b>'),
                                ),
                                _EditorToolBtn(
                                  icon: Icons.format_italic_rounded,
                                  tooltip: 'Italique',
                                  onTap: () => _wrapDescriptionTag('<i>', '</i>'),
                                ),
                                _EditorToolBtn(
                                  icon: Icons.format_underlined_rounded,
                                  tooltip: 'Souligné',
                                  onTap: () => _wrapDescriptionTag('<u>', '</u>'),
                                ),
                                _EditorToolBtn(
                                  icon: Icons.format_list_bulleted_rounded,
                                  tooltip: 'Liste à puces',
                                  onTap: () => _wrapDescriptionTag(
                                    '<ul><li>',
                                    '</li></ul>',
                                    sample: 'Point clé',
                                  ),
                                ),
                                _EditorToolBtn(
                                  icon: Icons.format_list_numbered_rounded,
                                  tooltip: 'Liste numérotée',
                                  onTap: () => _wrapDescriptionTag(
                                    '<ol><li>',
                                    '</li></ol>',
                                    sample: 'Étape 1',
                                  ),
                                ),
                                _EditorToolBtn(
                                  icon: Icons.link_rounded,
                                  tooltip: 'Insérer un lien',
                                  onTap: _insertDescriptionLink,
                                ),
                                _EditorToolBtn(
                                  icon: Icons.format_clear_rounded,
                                  tooltip: 'Supprimer le formatage',
                                  onTap: _stripDescriptionHtml,
                                ),
                              ],
                            ),
                          ),
                        ),
                        TextFormField(
                          controller: _descCtrl,
                          maxLines: 5,
                          minLines: 4,
                          decoration: const InputDecoration(
                            hintText: 'Décrivez votre produit en détail...',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            fillColor: Colors.transparent,
                            contentPadding: EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. IMAGES DE DESCRIPTION MARKETING (Infographies / IA XFY)
            _webCard(
              title: 'Images de description marketing',
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E8),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Text(
                  '✨ IA',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: _kWebOrange,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ajoutez des visuels marketing / infographies pour enrichir la page produit, ou générez-les avec l\'IA XFY.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _kWebOrange,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 42),
                          ),
                          onPressed: _isGeneratingAiMarketing
                              ? null
                              : _openAiMarketingDialog,
                          icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                          label: const Text(
                            'Générer IA',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 42),
                            side: const BorderSide(color: _kWebNavy),
                            foregroundColor: _kWebNavy,
                          ),
                          onPressed:
                              _isUploadingMarketing ? null : _pickMarketingImages,
                          icon: _isUploadingMarketing
                              ? const SizedBox(
                                  width: 15,
                                  height: 15,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.upload_rounded, size: 18),
                          label: const Text(
                            'Importer',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isGeneratingAiMarketing) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(
                      value: _aiProgress / 100,
                      color: _kWebOrange,
                      backgroundColor: const Color(0xFFFFEDE0),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '$_aiStepLabel ($_aiProgress%)',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: _kWebNavy,
                      ),
                    ),
                  ],
                  if (_marketingItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _marketingItems.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, idx) {
                          final m = _marketingItems[idx];
                          return Stack(
                            children: [
                              GestureDetector(
                                onTap: m.imageUrl != null
                                    ? () => showXfyImageLightbox(
                                          context,
                                          source: m.imageUrl!,
                                          title: 'Visuel marketing #${idx + 1}',
                                        )
                                    : null,
                                child: Container(
                                  width: 92,
                                  height: 110,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: _kWebBorder),
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: m.localPath != null
                                      ? Image.file(
                                          File(m.localPath!),
                                          fit: BoxFit.cover,
                                          cacheWidth: 220,
                                        )
                                      : XfySmartImage(
                                          source: m.imageUrl,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                              ),
                              Positioned(
                                top: 3,
                                right: 3,
                                child: GestureDetector(
                                  onTap: () => setState(
                                    () => _marketingItems.removeAt(idx),
                                  ),
                                  child: Container(
                                    width: 22,
                                    height: 22,
                                    decoration: const BoxDecoration(
                                      color: XfyColors.rose,
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
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 3. TARIFICATION (Prix + Prix barré)
            _webCard(
              title: 'Tarification',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Prix (TND)'),
                        TextFormField(
                          controller: _priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _webInputDeco(hint: 'Entrez le prix'),
                          validator: (v) {
                            if (_showVariants) return null;
                            final val = double.tryParse(
                              (v ?? '').trim().replaceAll(',', '.'),
                            );
                            if (val == null || val <= 0) {
                              return 'Prix > 0 requis';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Prix barré'),
                        TextFormField(
                          controller: _comparePriceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _webInputDeco(hint: 'Ex: 29.99'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 4. IMAGES DU PRODUIT (800x800 + Télécharger des images + Caméra)
            _webCard(
              title: 'Images',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Note : Pour une meilleure apparence visuelle, utilisez une image de produit de taille 800x800.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: _kWebNavy,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 44),
                          ),
                          onPressed: () => _pickGlobalImages(camera: false),
                          icon: const Icon(Icons.upload_rounded, size: 18),
                          label: const Text(
                            'Télécharger des images',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          side: const BorderSide(color: _kWebBorder, width: 1.4),
                          foregroundColor: _kWebNavy,
                        ),
                        onPressed: () => _pickGlobalImages(camera: true),
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: const Text('Photo'),
                      ),
                    ],
                  ),
                  if (_imageError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _imageError!,
                      style: const TextStyle(color: XfyColors.rose, fontSize: 12),
                    ),
                  ],
                  if (_globalFiles.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: List.generate(_globalFiles.length, (i) {
                        final f = _globalFiles[i];
                        return Stack(
                          children: [
                            Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: i == 0 ? _kWebOrange : _kWebBorder,
                                  width: i == 0 ? 2 : 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.file(
                                File(f.path),
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
                                  () => _globalFiles.removeAt(i),
                                ),
                                child: Container(
                                  width: 22,
                                  height: 22,
                                  decoration: const BoxDecoration(
                                    color: XfyColors.rose,
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
                            if (i == 0)
                              Positioned(
                                left: 4,
                                bottom: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _kWebNavy,
                                    borderRadius: BorderRadius.circular(5),
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
                      }),
                    ),
                  ],
                ],
              ),
            ),

            // 5. INVENTAIRE (3 pills Web) + LIVRAISON GRATUITE + PROMOTION
            _webCard(
              title: 'Inventaire',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _InventoryPill(
                        label: 'En stock',
                        selected: _inventory == 'IN_STOCK',
                        activeBg: const Color(0xFFF0FDF4),
                        activeBorder: const Color(0xFF4ADE80),
                        activeFg: const Color(0xFF166534),
                        onTap: () => setState(() => _inventory = 'IN_STOCK'),
                      ),
                      const SizedBox(width: 8),
                      _InventoryPill(
                        label: 'Limité',
                        selected: _inventory == 'LIMITED',
                        activeBg: const Color(0xFFFFFBEB),
                        activeBorder: const Color(0xFFFBBF24),
                        activeFg: const Color(0xFF92400E),
                        onTap: () => setState(() => _inventory = 'LIMITED'),
                      ),
                      const SizedBox(width: 8),
                      _InventoryPill(
                        label: 'Rupture',
                        selected: _inventory == 'OUT_OF_STOCK',
                        activeBg: const Color(0xFFFEF2F2),
                        activeBorder: const Color(0xFFFCA5A5),
                        activeFg: const Color(0xFF991B1B),
                        onTap: () =>
                            setState(() => _inventory = 'OUT_OF_STOCK'),
                      ),
                    ],
                  ),
                  if (!_showVariants) ...[
                    const SizedBox(height: 12),
                    _fieldLabel('Quantité en stock'),
                    TextFormField(
                      controller: _stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: _webInputDeco(hint: 'Ex: 20'),
                    ),
                  ],
                ],
              ),
            ),

            // 6. LIVRAISON GRATUITE
            _webCard(
              title: 'Livraison gratuite',
              trailing: Switch(
                value: _livraisonGratuite,
                activeTrackColor: _kWebNavy,
                onChanged: (v) => setState(() => _livraisonGratuite = v),
              ),
              child: const Text(
                'Activez cette option pour offrir la livraison gratuite sur ce produit.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
            ),

            // 7. PROMOTION (Date et heure de début)
            _webCard(
              title: 'Promotion',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('Date et heure de début de promotion'),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _pickPromotionStart,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _kWebInputBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _kWebBorder, width: 1.4),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.event_rounded,
                            size: 19,
                            color: _kWebNavy,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _promotionStart != null
                                  ? '${_promotionStart!.day.toString().padLeft(2, '0')}/${_promotionStart!.month.toString().padLeft(2, '0')}/${_promotionStart!.year} • ${_promotionStart!.hour.toString().padLeft(2, '0')}:${_promotionStart!.minute.toString().padLeft(2, '0')}'
                                  : 'Choisir une date et heure (optionnel)',
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: _promotionStart != null
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: _promotionStart != null
                                    ? XfyColors.ink
                                    : const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                          if (_promotionStart != null)
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _promotionStart = null),
                              child: const Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: XfyColors.inkMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 8. CATÉGORIES & SOUS-CATÉGORIES
            _webCard(
              title: 'Catégories',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _fieldLabel('Catégorie'),
                  DropdownButtonFormField<int?>(
                    initialValue: _selectedCategoryId,
                    isExpanded: true,
                    decoration: _webInputDeco(
                      suffixIcon: _loadingCategories
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('Sélectionnez une catégorie'),
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
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: _onCategorySelected,
                  ),
                  const SizedBox(height: 12),
                  _fieldLabel('Sous-catégories'),
                  if (_loadingSubcategories)
                    const LinearProgressIndicator(minHeight: 2)
                  else if (_subcategories.isEmpty)
                    Text(
                      _selectedCategoryId != null
                          ? 'Cette catégorie ne contient aucune sous-catégorie (optionnel).'
                          : 'Sélectionnez d\'abord une catégorie.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    )
                  else
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
                        final sel = _selectedSubcategoryIds.contains(id);
                        return FilterChip(
                          label: Text(name),
                          selected: sel,
                          selectedColor: const Color(0xFFE0E7FF),
                          checkmarkColor: _kWebNavy,
                          onSelected: (v) {
                            setState(() {
                              if (v) {
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
              ),
            ),

            // 9. VARIANTES (Simple & Groupé jusqu'à 3 types, avec image par variante/groupe)
            _webCard(
              title: 'Variantes',
              trailing: Switch(
                value: _showVariants,
                activeTrackColor: _kWebNavy,
                onChanged: _toggleVariants,
              ),
              child: !_showVariants
                  ? const Text(
                      'Activez si ce produit existe en plusieurs tailles, couleurs ou matières (jusqu\'à 3 options).',
                      style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                    )
                  : _buildVariantsEditor(),
            ),

            // 10. PRODUITS SUGGÉRÉS
            if (storeProducts.isNotEmpty)
              _webCard(
                title: 'Produits suggérés',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _suggestedProductIds.isEmpty
                          ? 'Sélectionnez les produits complémentaires à suggérer sur la fiche produit :'
                          : '${_suggestedProductIds.length} produit(s) suggéré(s) sélectionné(s)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: storeProducts.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, idx) {
                          final p = storeProducts[idx];
                          final sel = _suggestedProductIds.contains(p.id);
                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                if (sel) {
                                  _suggestedProductIds.remove(p.id);
                                } else {
                                  _suggestedProductIds.add(p.id);
                                }
                              });
                            },
                            child: Container(
                              width: 148,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: sel
                                    ? const Color(0xFFEEF0FA)
                                    : _kWebInputBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: sel ? _kWebNavy : _kWebBorder,
                                  width: sel ? 1.6 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.white,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: XfySmartImage(
                                      source: p.imageUrl,
                                      width: 44,
                                      height: 44,
                                      cacheWidth: 120,
                                      cacheHeight: 120,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.nom,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w700,
                                            color: XfyColors.ink,
                                          ),
                                        ),
                                        Text(
                                          XfyFormatters.formatTnd(p.price),
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: _kWebNavy,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

            // 11. 🎁 CONFIGURATION DES OFFRES & PACKS (BUNDLES) — BOOST CONVERSION
            _buildBundlesSection(storeProducts),

            if (_errorMessage != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: XfyColors.roseSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: XfyColors.rose.withValues(alpha: 0.4),
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
                        _errorMessage!,
                        style: const TextStyle(
                          color: XfyColors.rose,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVariantsEditor() {
    final grouped = _isGroupedVariantsView ? _buildGroupedCombos() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...List.generate(_variantTypes.length, (tIdx) {
          final vt = _variantTypes[tIdx];
          if (!vt.isEditing &&
              vt.nameCtrl.text.trim().isNotEmpty &&
              vt.nonEmptyValues.isNotEmpty) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kWebBorder),
              ),
              child: InkWell(
                onTap: () => setState(() => vt.isEditing = true),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          vt.nameCtrl.text.trim(),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: _kWebNavy,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          'Modifier',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _kWebOrange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: vt.nonEmptyValues
                          .map((v) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0E7FF),
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                child: Text(
                                  v,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _kWebNavy,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            );
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFAFBFF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _kWebBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: vt.nameCtrl,
                        onChanged: (_) =>
                            setState(() => _regenerateCombinations()),
                        decoration: _webInputDeco(
                          hint: 'Nom du type (ex: Couleur, Taille, Matière)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      onPressed: () => _removeVariantType(tIdx),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: XfyColors.rose,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(vt.valueCtrls.length, (vIdx) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: vt.valueCtrls[vIdx],
                            onChanged: (_) =>
                                setState(() => _regenerateCombinations()),
                            decoration: _webInputDeco(
                              hint: vt.nameCtrl.text.trim().toLowerCase() ==
                                      'couleur'
                                  ? 'Couleur (ex. Rouge, Bleu)'
                                  : 'Valeur (ex. S, M, L)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        IconButton(
                          onPressed: vt.valueCtrls.length <= 1
                              ? null
                              : () {
                                  setState(() {
                                    vt.valueCtrls[vIdx].dispose();
                                    vt.valueCtrls.removeAt(vIdx);
                                    _regenerateCombinations();
                                  });
                                },
                          icon: const Icon(
                            Icons.remove_circle_outline_rounded,
                            color: XfyColors.rose,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          vt.valueCtrls.add(TextEditingController());
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('Ajouter une valeur'),
                    ),
                    const Spacer(),
                    if (vt.nameCtrl.text.trim().isNotEmpty &&
                        vt.nonEmptyValues.isNotEmpty)
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(
                          backgroundColor: _kWebNavy,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(0, 36),
                        ),
                        onPressed: () {
                          setState(() {
                            vt.isEditing = false;
                            _regenerateCombinations();
                          });
                        },
                        icon: const Icon(Icons.check_rounded, size: 16),
                        label: const Text('Terminer'),
                      ),
                  ],
                ),
              ],
            ),
          );
        }),

        if (_variantTypes.length < 3)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: _kWebOrange),
            onPressed: _addVariantType,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
            label: const Text(
              'Ajouter un type de variante',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),

        // Mode Simple (1 seul type)
        if (!_isGroupedVariantsView && _combos.isNotEmpty) ...[
          const Divider(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              'Affichage simple des variantes — chaque valeur peut avoir sa propre image, son prix et son stock.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF1E3A8A)),
            ),
          ),
          const SizedBox(height: 10),
          ..._combos.map(_buildComboRow),
        ],

        // Mode Groupé (2 ou 3 types)
        if (grouped != null && grouped.isNotEmpty) ...[
          const Divider(height: 20),
          Row(
            children: [
              const Text(
                'Grouper par : ',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: _groupBy,
                items: _variantTypes
                    .where((t) =>
                        t.nameCtrl.text.trim().isNotEmpty &&
                        t.nonEmptyValues.isNotEmpty)
                    .map((t) {
                  final n = t.nameCtrl.text.trim();
                  return DropdownMenuItem(value: n, child: Text(n));
                }).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _groupBy = v);
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...grouped.entries.map((entry) {
            final gName = entry.key;
            final subs = entry.value;
            final expanded = _groupExpanded[gName] ?? true;
            final gImg = _groupImages[gName];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kWebBorder),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => _pickGroupImage(gName, subs),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _kWebBorder),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: gImg != null
                              ? Image.file(File(gImg.path), fit: BoxFit.cover)
                              : const Icon(
                                  Icons.add_photo_alternate_outlined,
                                  size: 20,
                                  color: _kWebNavy,
                                ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(
                            () => _groupExpanded[gName] = !expanded,
                          ),
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '$gName (${subs.length} variantes)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: _kWebNavy,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                expanded
                                    ? Icons.expand_less_rounded
                                    : Icons.expand_more_rounded,
                                color: _kWebNavy,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _webInputDeco(hint: 'Prix groupe (TND)'),
                          onChanged: (val) {
                            if (val.trim().isEmpty) return;
                            setState(() {
                              for (final s in subs) {
                                s.priceCtrl.text = val.trim();
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: _webInputDeco(hint: 'Stock groupe'),
                          onChanged: (val) {
                            if (val.trim().isEmpty) return;
                            setState(() {
                              for (final s in subs) {
                                s.stockCtrl.text = val.trim();
                              }
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (expanded) ...[
                    const SizedBox(height: 8),
                    ...subs.map(_buildComboRow),
                  ],
                ],
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _buildComboRow(_DraftVariantCombo combo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _kWebBorder),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _pickComboImage(combo),
            child: Stack(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _kWebInputBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _kWebBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: combo.imageFile != null
                      ? Image.file(
                          File(combo.imageFile!.path),
                          fit: BoxFit.cover,
                          cacheWidth: 100,
                        )
                      : const Icon(
                          Icons.image_outlined,
                          size: 19,
                          color: Color(0xFF94A3B8),
                        ),
                ),
                if (combo.imageFile != null)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () => setState(() => combo.imageFile = null),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: XfyColors.rose,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(
              combo.displayLabel,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: XfyColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextField(
              controller: combo.priceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Prix',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 62,
            child: TextField(
              controller: combo.stockCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Qté',
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBundlesSection(List<ProductModel> storeProducts) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _bundlesEnabled ? _kWebOrange : const Color(0xFFE8EAF0),
          width: _bundlesEnabled ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _kWebNavy.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🎁', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          'Offres & Packs (Bundles)',
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: _kWebNavy,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF08A),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'BOOST CONVERSION',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF713F12),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Ex: 2 pièces = -10%, 2 achetés = +1 offert, cadeau gratuit...',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _bundlesEnabled,
                activeTrackColor: _kWebOrange,
                onChanged: _onBundlesToggle,
              ),
            ],
          ),

          if (_bundlesEnabled) ...[
            const Divider(height: 20),
            // Barre modèles rapides
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kWebBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '⚡ MODÈLES RAPIDES',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _kWebNavy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        label: const Text(
                          '📊 Pack 1 / 2 (-10%) / 3 (-20%)',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        onPressed: () => _applyBundlePreset('pack_1_2_3'),
                      ),
                      ActionChip(
                        label: const Text(
                          '🎁 2 Achetés = +1 Offert',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        onPressed: () => _applyBundlePreset('buy2_get1'),
                      ),
                      ActionChip(
                        label: const Text(
                          '🎀 2 Pièces + Cadeau Offert',
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                        ),
                        onPressed: () => _applyBundlePreset('buy2_gift'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Liste des cartes d'offres éditables
            ...List.generate(_bundles.length, (bIdx) {
              final b = _bundles[bIdx];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFBFF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _selectedPreviewBundleIdx == bIdx
                        ? _kWebNavy
                        : _kWebBorder,
                    width: _selectedPreviewBundleIdx == bIdx ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _kWebNavy,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'Offre #${bIdx + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            b.titleCtrl.text.trim().isNotEmpty
                                ? b.titleCtrl.text.trim()
                                : 'Pack ${b.quantity} pièces',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () {
                            setState(() {
                              _bundles[bIdx].dispose();
                              _bundles.removeAt(bIdx);
                              if (_selectedPreviewBundleIdx >= _bundles.length) {
                                _selectedPreviewBundleIdx =
                                    (_bundles.length - 1).clamp(0, 99);
                              }
                            });
                          },
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            color: XfyColors.rose,
                            size: 19,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        SizedBox(
                          width: 92,
                          child: TextField(
                            controller: b.quantityCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (_) => setState(() {}),
                            decoration: _webInputDeco(hint: 'Qté'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: b.offerType,
                            isExpanded: true,
                            decoration: _webInputDeco(),
                            items: const [
                              DropdownMenuItem(
                                value: 'PERCENTAGE_DISCOUNT',
                                child: Text('🏷️ Remise (%)', overflow: TextOverflow.ellipsis),
                              ),
                              DropdownMenuItem(
                                value: 'FIXED_DISCOUNT',
                                child: Text('💵 Remise fixe (TND)', overflow: TextOverflow.ellipsis),
                              ),
                              DropdownMenuItem(
                                value: 'FIXED_PRICE',
                                child: Text('💰 Prix fixe pack', overflow: TextOverflow.ellipsis),
                              ),
                              DropdownMenuItem(
                                value: 'FREE_UNITS',
                                child: Text('🎁 Pièce(s) gratuite(s)', overflow: TextOverflow.ellipsis),
                              ),
                              DropdownMenuItem(
                                value: 'FREE_GIFT',
                                child: Text('🎀 Cadeau offert', overflow: TextOverflow.ellipsis),
                              ),
                              DropdownMenuItem(
                                value: 'NO_DISCOUNT',
                                child: Text('📦 Prix standard', overflow: TextOverflow.ellipsis),
                              ),
                            ],
                            onChanged: (v) {
                              if (v == null) return;
                              setState(() {
                                b.offerType = v;
                                if (v == 'PERCENTAGE_DISCOUNT' &&
                                    b.discountValue <= 0) {
                                  b.discountCtrl.text = '10';
                                } else if (v == 'FIXED_DISCOUNT' &&
                                    b.discountValue <= 0) {
                                  b.discountCtrl.text = '15';
                                } else if (v == 'FIXED_PRICE' &&
                                    b.discountValue <= 0) {
                                  b.discountCtrl.text =
                                      (_getPreviewBasePrice() * b.quantity * 0.85)
                                          .round()
                                          .toString();
                                } else if (v == 'FREE_GIFT' &&
                                    b.giftNameCtrl.text.isEmpty) {
                                  b.giftNameCtrl.text = 'Cadeau surprise offert';
                                }
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (b.offerType == 'PERCENTAGE_DISCOUNT' ||
                        b.offerType == 'FIXED_DISCOUNT' ||
                        b.offerType == 'FIXED_PRICE')
                      TextField(
                        controller: b.discountCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) => setState(() {}),
                        decoration: _webInputDeco(
                          hint: b.offerType == 'PERCENTAGE_DISCOUNT'
                              ? 'Remise en % (ex: 10)'
                              : b.offerType == 'FIXED_DISCOUNT'
                                  ? 'Montant remise en TND (ex: 15)'
                                  : 'Prix total du pack en TND (ex: 49)',
                        ),
                      ),
                    if (b.offerType == 'FREE_UNITS')
                      TextField(
                        controller: b.freeQtyCtrl,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: _webInputDeco(
                          hint: 'Nombre de pièces gratuites en plus (ex: 1)',
                        ),
                      ),
                    if (b.offerType == 'FREE_GIFT') ...[
                      if (storeProducts.isNotEmpty) ...[
                        DropdownButtonFormField<int?>(
                          initialValue: b.giftProductId,
                          isExpanded: true,
                          decoration: _webInputDeco(
                            hint: 'Produit cadeau de la boutique (optionnel)',
                          ),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('✨ Cadeau libre / personnalisé'),
                            ),
                            ...storeProducts.map((p) => DropdownMenuItem<int?>(
                                  value: p.id,
                                  child: Text(
                                    '🎁 ${p.nom} (${p.price} TND)',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )),
                          ],
                          onChanged: (pid) {
                            setState(() {
                              b.giftProductId = pid;
                              if (pid != null) {
                                final found = storeProducts
                                    .where((p) => p.id == pid)
                                    .firstOrNull;
                                if (found != null) {
                                  b.giftNameCtrl.text = found.nom;
                                  b.giftImageUrl = found.resolvedImageUrl;
                                }
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                      TextField(
                        controller: b.giftNameCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: _webInputDeco(
                          hint: 'Nom du cadeau affiché (ex: Pochette offerte)',
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    TextField(
                      controller: b.titleCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: _webInputDeco(hint: 'Titre de l\'offre'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: b.subtitleCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: _webInputDeco(hint: 'Sous-titre d\'accroche'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _badgePresets.map((bp) {
                        final sel = b.badgeTextCtrl.text == bp.label;
                        final col = _parseHexColor(bp.color);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (sel) {
                                b.badgeTextCtrl.clear();
                              } else {
                                b.badgeTextCtrl.text = bp.label;
                                b.badgeColor = bp.color;
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: sel
                                  ? col.withValues(alpha: 0.14)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(99),
                              border: Border.all(
                                color: sel ? col : _kWebBorder,
                              ),
                            ),
                            child: Text(
                              bp.label,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: b.badgeTextCtrl,
                            onChanged: (_) => setState(() {}),
                            decoration: _webInputDeco(
                              hint: 'Badge personnalisé (optionnel)',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            final idx = _badgeColorChoices.indexOf(b.badgeColor);
                            setState(() {
                              b.badgeColor = _badgeColorChoices[
                                  (idx + 1) % _badgeColorChoices.length];
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: _parseHexColor(b.badgeColor),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.palette_outlined,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        '🚚 Livraison gratuite incluse sur cette offre',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      value: b.freeShipping,
                      onChanged: (v) => setState(() => b.freeShipping = v ?? false),
                    ),
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text(
                        '⭐ Pré-sélectionner cette offre par défaut',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      value: b.isDefault,
                      onChanged: (v) {
                        setState(() {
                          for (int k = 0; k < _bundles.length; k++) {
                            _bundles[k].isDefault = (k == bIdx) && (v ?? false);
                          }
                          _selectedPreviewBundleIdx = bIdx;
                        });
                      },
                    ),
                  ],
                ),
              );
            }),

            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(42),
                side: const BorderSide(color: _kWebNavy, width: 1.5),
                foregroundColor: _kWebNavy,
              ),
              onPressed: () => setState(() => _addBundleOffer()),
              icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: const Text(
                'Ajouter une autre offre / palier',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),

            // 👁️ APERÇU CLIENT EN DIRECT (exactement comme colonne droite Web)
            if (_bundles.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    '👁️ APERÇU CLIENT EN DIRECT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Réf : ${_getPreviewBasePrice()} TND',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kWebNavy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FD),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kWebBorder),
                ),
                child: Column(
                  children: [
                    const Text(
                      '🔥 CHOISISSEZ VOTRE OFFRE',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: _kWebNavy,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(_bundles.length, (pIdx) {
                      final b = _bundles[pIdx];
                      final selected = _selectedPreviewBundleIdx == pIdx;
                      final orig = _calcBundleOriginal(b);
                      final fin = _calcBundleFinal(b);
                      final savings = _calcBundleSavings(b);
                      final badge = b.badgeTextCtrl.text.trim();
                      final badgeCol = _parseHexColor(b.badgeColor);
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedPreviewBundleIdx = pIdx),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFFEEF2FF)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? _kWebNavy : _kWebBorder,
                              width: selected ? 1.8 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (badge.isNotEmpty)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: badgeCol,
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    badge,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              Row(
                                children: [
                                  Icon(
                                    selected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    size: 19,
                                    color: selected
                                        ? _kWebNavy
                                        : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          b.titleCtrl.text.trim().isNotEmpty
                                              ? b.titleCtrl.text.trim()
                                              : 'Pack ${b.quantity} pièces',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                            color: XfyColors.ink,
                                          ),
                                        ),
                                        if (b.subtitleCtrl.text
                                            .trim()
                                            .isNotEmpty)
                                          Text(
                                            b.subtitleCtrl.text.trim(),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                        if (savings > 0)
                                          Container(
                                            margin:
                                                const EdgeInsets.only(top: 4),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDCFCE7),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'Économisez $savings TND',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF166534),
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '$fin TND',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 14.5,
                                          color: _kWebNavy,
                                        ),
                                      ),
                                      if (savings > 0)
                                        Text(
                                          '$orig TND',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF94A3B8),
                                            decoration:
                                                TextDecoration.lineThrough,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _EditorToolBtn extends StatelessWidget {
  const _EditorToolBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(icon, size: 19, color: _kWebNavy),
    );
  }
}

class _InventoryPill extends StatelessWidget {
  const _InventoryPill({
    required this.label,
    required this.selected,
    required this.activeBg,
    required this.activeBorder,
    required this.activeFg,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color activeBg;
  final Color activeBorder;
  final Color activeFg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? activeBg : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? activeBorder : _kWebBorder,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? activeFg : const Color(0xFF475569),
            ),
          ),
        ),
      ),
    );
  }
}
