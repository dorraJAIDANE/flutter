import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/order_model.dart';
import '../../state/app_state.dart';

/// Feuille complète pour compléter les champs manquants d'une commande
/// (Nom, Téléphone, Gouvernorat/Ville/Zone officiels XFY, Adresse, Produit, Total, Échange)
/// puis enregistrer et expédier directement à la société de livraison choisie.
class SendToDeliverySheet extends StatefulWidget {
  const SendToDeliverySheet({
    super.key,
    required this.state,
    required this.order,
    this.dispatchMode = true,
    this.initialCarrier,
  });

  final AppState state;
  final OrderModel order;
  final bool dispatchMode;
  final String? initialCarrier;

  @override
  State<SendToDeliverySheet> createState() => _SendToDeliverySheetState();
}

class _SendToDeliverySheetState extends State<SendToDeliverySheet> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _phone2Ctrl;
  late final TextEditingController _productCtrl;
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _totalCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _villeTextCtrl;
  late final TextEditingController _zoneTextCtrl;
  late final TextEditingController _commentCtrl;

  List<String> _divisions = [];
  List<String> _cities = [];
  List<String> _zones = [];

  String? _selectedGov;
  String? _selectedVille;
  String? _selectedZone;
  bool _loadingDivisions = true;
  bool _loadingCities = false;
  bool _loadingZones = false;

  late bool _isExchange;
  String? _selectedCarrier;
  bool _submitting = false;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    final o = widget.order;
    _nameCtrl = TextEditingController(
      text: _cleanInitial(o.nom),
    );
    _phoneCtrl = TextEditingController(text: _cleanInitial(o.phoneNumber));
    _phone2Ctrl = TextEditingController(text: _cleanInitial(o.phone2));
    _productCtrl = TextEditingController(text: _cleanInitial(o.produit));
    _qtyCtrl = TextEditingController(
      text: _cleanInitial(o.quantite).isEmpty ? '1' : _cleanInitial(o.quantite),
    );
    _totalCtrl = TextEditingController(
      text: o.effectiveTotal > 0 ? o.effectiveTotal.toStringAsFixed(2) : '',
    );
    _addressCtrl = TextEditingController(text: _cleanInitial(o.adresse));
    _villeTextCtrl = TextEditingController(text: _cleanInitial(o.ville));
    _zoneTextCtrl = TextEditingController(text: _cleanInitial(o.zone));
    _commentCtrl = TextEditingController(text: _cleanInitial(o.commentaire));
    _isExchange = o.exchange;

    _selectedGov = _cleanInitial(o.gouvernorat).isEmpty
        ? null
        : _cleanInitial(o.gouvernorat);
    _selectedVille =
        _cleanInitial(o.ville).isEmpty ? null : _cleanInitial(o.ville);
    _selectedZone =
        _cleanInitial(o.zone).isEmpty ? null : _cleanInitial(o.zone);

    final carriers = widget.state.deliveryCompanies;
    if (widget.initialCarrier != null &&
        carriers.contains(widget.initialCarrier)) {
      _selectedCarrier = widget.initialCarrier;
    } else if (o.deliveryCompany != null &&
        carriers.any((c) =>
            c.toLowerCase() == o.deliveryCompany!.toLowerCase().trim())) {
      _selectedCarrier = carriers.firstWhere(
        (c) => c.toLowerCase() == o.deliveryCompany!.toLowerCase().trim(),
      );
    } else if (carriers.isNotEmpty) {
      _selectedCarrier = carriers.first;
    }

    _loadInitialGeography();
  }

  String _cleanInitial(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty ||
        s.toLowerCase() == 'null' ||
        s.toLowerCase() == 'non spécifié' ||
        s.toLowerCase() == 'non specifie') {
      return '';
    }
    return s;
  }

  String? _matchInList(List<String> list, String? target) {
    if (target == null || target.trim().isEmpty) return null;
    final norm = XfyFormatters.stripAccents(target.trim());
    for (final item in list) {
      if (XfyFormatters.stripAccents(item.trim()) == norm) {
        return item;
      }
    }
    return null;
  }

  Future<void> _loadInitialGeography() async {
    setState(() => _loadingDivisions = true);
    final divs = await widget.state.api.getDivisions();
    if (!mounted) return;

    final matchedGov = _matchInList(divs, _selectedGov);
    final finalDivs = [...divs];
    if (_selectedGov != null && matchedGov == null) {
      finalDivs.insert(0, _selectedGov!);
    }

    setState(() {
      _divisions = finalDivs;
      _selectedGov = matchedGov ?? _selectedGov;
      _loadingDivisions = false;
    });

    if (_selectedGov != null && _selectedGov!.isNotEmpty) {
      await _loadCitiesFor(_selectedGov!, keepCurrentSelection: true);
    }
  }

  Future<void> _loadCitiesFor(
    String gov, {
    bool keepCurrentSelection = false,
  }) async {
    setState(() {
      _loadingCities = true;
      if (!keepCurrentSelection) {
        _cities = [];
        _zones = [];
        _selectedVille = null;
        _selectedZone = null;
        _villeTextCtrl.clear();
        _zoneTextCtrl.clear();
      }
    });

    final fetched = await widget.state.api.getCities(gov);
    if (!mounted) return;

    final list = [...fetched];
    String? matchedVille;
    if (keepCurrentSelection && _selectedVille != null) {
      matchedVille = _matchInList(list, _selectedVille);
      if (matchedVille == null && list.isNotEmpty) {
        list.insert(0, _selectedVille!);
        matchedVille = _selectedVille;
      }
    }

    setState(() {
      _cities = list;
      _selectedVille = matchedVille ?? (keepCurrentSelection ? _selectedVille : null);
      if (_selectedVille != null) {
        _villeTextCtrl.text = _selectedVille!;
      }
      _loadingCities = false;
    });

    if (_selectedVille != null && _selectedVille!.isNotEmpty) {
      await _loadZonesFor(
        gov,
        _selectedVille!,
        keepCurrentSelection: keepCurrentSelection,
      );
    }
  }

  Future<void> _loadZonesFor(
    String gov,
    String ville, {
    bool keepCurrentSelection = false,
  }) async {
    setState(() {
      _loadingZones = true;
      if (!keepCurrentSelection) {
        _zones = [];
        _selectedZone = null;
        _zoneTextCtrl.clear();
      }
    });

    final fetched = await widget.state.api.getLocalities(gov, ville);
    if (!mounted) return;

    final list = [...fetched];
    String? matchedZone;
    if (keepCurrentSelection && _selectedZone != null) {
      matchedZone = _matchInList(list, _selectedZone);
      if (matchedZone == null && list.isNotEmpty) {
        list.insert(0, _selectedZone!);
        matchedZone = _selectedZone;
      }
    }

    setState(() {
      _zones = list;
      _selectedZone = matchedZone ?? (keepCurrentSelection ? _selectedZone : null);
      if (_selectedZone != null) {
        _zoneTextCtrl.text = _selectedZone!;
      }
      _loadingZones = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _phone2Ctrl.dispose();
    _productCtrl.dispose();
    _qtyCtrl.dispose();
    _totalCtrl.dispose();
    _addressCtrl.dispose();
    _villeTextCtrl.dispose();
    _zoneTextCtrl.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

  OrderModel _buildEditedOrder() {
    final total =
        double.tryParse(_totalCtrl.text.trim().replaceAll(',', '.')) ??
            widget.order.effectiveTotal;
    final villeVal =
        _cities.isNotEmpty ? (_selectedVille ?? '') : _villeTextCtrl.text.trim();
    final zoneVal =
        _zones.isNotEmpty ? (_selectedZone ?? '') : _zoneTextCtrl.text.trim();

    return widget.order.copyWith(
      nom: _nameCtrl.text.trim(),
      phoneNumber: _phoneCtrl.text.trim(),
      phone2: _phone2Ctrl.text.trim().isEmpty ? null : _phone2Ctrl.text.trim(),
      produit: _productCtrl.text.trim(),
      quantite: _qtyCtrl.text.trim().isEmpty ? '1' : _qtyCtrl.text.trim(),
      total: total,
      gouvernorat: (_selectedGov ?? '').trim(),
      ville: villeVal,
      zone: zoneVal,
      adresse: _addressCtrl.text.trim(),
      commentaire: _commentCtrl.text.trim(),
      exchange: _isExchange,
    );
  }

  List<String> _liveMissingFields() => _buildEditedOrder().missingDeliveryFields;

  Future<void> _submit({required bool andDispatch}) async {
    setState(() => _errorMsg = null);
    if (!_formKey.currentState!.validate()) return;

    final edited = _buildEditedOrder();
    if (andDispatch) {
      if (_selectedCarrier == null || _selectedCarrier!.isEmpty) {
        setState(() {
          _errorMsg =
              'Aucune société de livraison configurée pour cette boutique.';
        });
        return;
      }
      if (!_isExchange && _zones.isNotEmpty && (edited.zone ?? '').trim().isEmpty) {
        final key = _selectedCarrier!.toLowerCase();
        if (key.contains('navex') || key.contains('jax')) {
          setState(() {
            _errorMsg =
                'Veuillez sélectionner la Zone / Localité requise pour ${OrderModel.formatCarrierLabel(_selectedCarrier!)}.';
          });
          return;
        }
      }
    }

    HapticFeedback.mediumImpact();
    setState(() => _submitting = true);
    try {
      if (andDispatch) {
        final res = await widget.state.saveAndSendOrderToCarrier(
          edited,
          _selectedCarrier!,
        );
        if (!mounted) return;
        Navigator.pop<({OrderModel order, String message})>(
          context,
          (order: res.order, message: res.message),
        );
      } else {
        final saved = await widget.state.updateOrderDetails(edited);
        if (!mounted) return;
        Navigator.pop<({OrderModel order, String message})>(
          context,
          (order: saved, message: 'Commande #${saved.id} enregistrée'),
        );
      }
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
    final carriers = widget.state.deliveryCompanies;
    final missing = _liveMissingFields();

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
                        gradient: XfyColors.statsGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        widget.dispatchMode
                            ? Icons.local_shipping_rounded
                            : Icons.edit_note_rounded,
                        color: Colors.white,
                        size: 21,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.dispatchMode
                                ? 'Expédier la commande #${widget.order.id}'
                                : 'Modifier la commande #${widget.order.id}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: XfyColors.ink,
                            ),
                          ),
                          Text(
                            widget.dispatchMode
                                ? 'Complétez les champs manquants puis envoyez au transporteur'
                                : 'Mettez à jour les coordonnées et détails',
                            style: const TextStyle(
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
                  onChanged: () => setState(() {}),
                  child: ListView(
                    controller: scrollCtrl,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      14,
                      20,
                      MediaQuery.of(context).viewInsets.bottom + 24,
                    ),
                    children: [
                      // Indicateur dynamique champs manquants / prêt
                      if (widget.dispatchMode)
                        Container(
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: missing.isEmpty
                                ? XfyColors.emeraldSoft
                                : XfyColors.amberSoft,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: (missing.isEmpty
                                      ? XfyColors.emerald
                                      : XfyColors.amber)
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                missing.isEmpty
                                    ? Icons.check_circle_rounded
                                    : Icons.warning_amber_rounded,
                                size: 19,
                                color: missing.isEmpty
                                    ? XfyColors.emerald
                                    : XfyColors.amber,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  missing.isEmpty
                                      ? 'Tous les champs obligatoires sont complets. Prêt pour l\'envoi !'
                                      : 'Champs à compléter : ${missing.join(', ')}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: missing.isEmpty
                                        ? XfyColors.emerald
                                        : const Color(0xFF92400E),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Choix de la société de livraison
                      if (widget.dispatchMode) ...[
                        const Text(
                          'Société de livraison',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: XfyColors.ink,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (carriers.isEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: XfyColors.roseSoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Aucune société de livraison configurée sur votre boutique. Connectez votre transporteur (First, Navex, Intigo, JAX...) depuis le panel Web XFY.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: XfyColors.rose,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: carriers.map((carrier) {
                              final selected = _selectedCarrier == carrier;
                              return ChoiceChip(
                                selected: selected,
                                showCheckmark: true,
                                checkmarkColor: Colors.white,
                                avatar: Icon(
                                  Icons.local_shipping_rounded,
                                  size: 16,
                                  color: selected
                                      ? Colors.white
                                      : XfyColors.primaryVibrant,
                                ),
                                label: Text(
                                  OrderModel.formatCarrierLabel(carrier),
                                ),
                                selectedColor: XfyColors.primaryVibrant,
                                backgroundColor: XfyColors.primarySoft,
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: selected
                                      ? Colors.white
                                      : XfyColors.primaryDark,
                                ),
                                onSelected: (_) =>
                                    setState(() => _selectedCarrier = carrier),
                              );
                            }).toList(),
                          ),
                        const SizedBox(height: 16),
                      ],

                      // Informations client
                      const Text(
                        'Client',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: XfyColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _nameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Nom complet du client *',
                          prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Nom requis'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Téléphone *',
                                hintText: '8 chiffres',
                                prefixIcon: Icon(Icons.phone_outlined, size: 20),
                              ),
                              validator: (v) {
                                final digits =
                                    (v ?? '').replaceAll(RegExp(r'\D'), '');
                                if (digits.length < 8) {
                                  return '8 chiffres requis';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: _phone2Ctrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'Tél. 2 (optionnel)',
                                prefixIcon:
                                    Icon(Icons.phone_forwarded_outlined, size: 19),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      const Text(
                        'Adresse de livraison',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: XfyColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Gouvernorat (officiel /commande/divisions)
                      DropdownButtonFormField<String>(
                        initialValue: _divisions.contains(_selectedGov)
                            ? _selectedGov
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Gouvernorat *',
                          prefixIcon: const Icon(Icons.map_outlined, size: 20),
                          suffixIcon: _loadingDivisions
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : null,
                        ),
                        items: _divisions
                            .map((g) => DropdownMenuItem(
                                  value: g,
                                  child: Text(g, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v == null || v == _selectedGov) return;
                          setState(() => _selectedGov = v);
                          _loadCitiesFor(v);
                        },
                        validator: (v) =>
                            (!_isExchange && (v == null || v.trim().isEmpty))
                                ? 'Gouvernorat requis'
                                : null,
                      ),
                      const SizedBox(height: 10),

                      // Ville / Délégation (/commande/subdivisions/{gov})
                      if (_cities.isNotEmpty)
                        DropdownButtonFormField<String>(
                          key: ValueKey('city_$_selectedGov'),
                          initialValue: _cities.contains(_selectedVille)
                              ? _selectedVille
                              : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Ville / Délégation *',
                            prefixIcon: const Icon(
                              Icons.location_city_outlined,
                              size: 20,
                            ),
                            suffixIcon: _loadingCities
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : null,
                          ),
                          items: _cities
                              .map((c) => DropdownMenuItem(
                                    value: c,
                                    child:
                                        Text(c, overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v == null || v == _selectedVille) return;
                            setState(() {
                              _selectedVille = v;
                              _villeTextCtrl.text = v;
                            });
                            if (_selectedGov != null) {
                              _loadZonesFor(_selectedGov!, v);
                            }
                          },
                          validator: (v) =>
                              (!_isExchange && (v == null || v.trim().isEmpty))
                                  ? 'Ville requise'
                                  : null,
                        )
                      else
                        TextFormField(
                          controller: _villeTextCtrl,
                          decoration: InputDecoration(
                            labelText: 'Ville / Délégation *',
                            prefixIcon: const Icon(
                              Icons.location_city_outlined,
                              size: 20,
                            ),
                            suffixIcon: _loadingCities
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : null,
                          ),
                          validator: (v) =>
                              (!_isExchange && (v == null || v.trim().isEmpty))
                                  ? 'Ville requise'
                                  : null,
                        ),
                      const SizedBox(height: 10),

                      // Zone / Localité (/commande/zones/{gov}/{ville})
                      if (_zones.isNotEmpty)
                        DropdownButtonFormField<String>(
                          key: ValueKey('zone_${_selectedGov}_$_selectedVille'),
                          initialValue: _zones.contains(_selectedZone)
                              ? _selectedZone
                              : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: 'Zone / Localité',
                            prefixIcon:
                                const Icon(Icons.explore_outlined, size: 20),
                            suffixIcon: _loadingZones
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  )
                                : null,
                          ),
                          items: _zones
                              .map((z) => DropdownMenuItem(
                                    value: z,
                                    child:
                                        Text(z, overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedZone = v;
                              _zoneTextCtrl.text = v ?? '';
                            });
                          },
                        )
                      else
                        TextFormField(
                          controller: _zoneTextCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Zone / Localité (optionnel)',
                            prefixIcon: Icon(Icons.explore_outlined, size: 20),
                          ),
                        ),
                      const SizedBox(height: 10),

                      TextFormField(
                        controller: _addressCtrl,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'Adresse complète *',
                          hintText: 'Rue, immeuble, repère...',
                          prefixIcon: Icon(Icons.home_outlined, size: 20),
                        ),
                        validator: (v) =>
                            (!_isExchange && (v == null || v.trim().isEmpty))
                                ? 'Adresse requise'
                                : null,
                      ),

                      const SizedBox(height: 16),
                      const Text(
                        'Colis & Montant',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: XfyColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _productCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Produit(s) *',
                          prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Produit requis'
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _totalCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Total COD (DT) *',
                                prefixIcon:
                                    Icon(Icons.payments_outlined, size: 20),
                              ),
                              validator: (v) {
                                final val = double.tryParse(
                                  (v ?? '').trim().replaceAll(',', '.'),
                                );
                                if (val == null || val <= 0) {
                                  return 'Montant > 0 requis';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 112,
                            child: TextFormField(
                              controller: _qtyCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Quantité',
                                prefixIcon: Icon(Icons.numbers_rounded, size: 19),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: _commentCtrl,
                        maxLines: 2,
                        minLines: 1,
                        decoration: const InputDecoration(
                          labelText: 'Commentaire livreur (optionnel)',
                          prefixIcon: Icon(Icons.notes_rounded, size: 20),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Colis échange',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text(
                          'Cocher s\'il s\'agit d\'un échange avec un ancien colis',
                          style: TextStyle(fontSize: 11.5),
                        ),
                        value: _isExchange,
                        onChanged: (v) => setState(() => _isExchange = v),
                      ),

                      if (_errorMsg != null) ...[
                        const SizedBox(height: 10),
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
                      if (widget.dispatchMode && carriers.isNotEmpty) ...[
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: XfyColors.primaryVibrant,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          onPressed: _submitting
                              ? null
                              : () => _submit(andDispatch: true),
                          icon: _submitting
                              ? const SizedBox(
                                  width: 19,
                                  height: 19,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.3,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.local_shipping_rounded,
                                  size: 20,
                                ),
                          label: Text(
                            _submitting
                                ? 'Envoi en cours...'
                                : 'Enregistrer & Envoyer à ${OrderModel.formatCarrierLabel(_selectedCarrier ?? carriers.first)}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                          onPressed: _submitting
                              ? null
                              : () => _submit(andDispatch: false),
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Enregistrer les champs seulement'),
                        ),
                      ] else
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: XfyColors.primaryVibrant,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(50),
                          ),
                          onPressed: _submitting
                              ? null
                              : () => _submit(andDispatch: false),
                          icon: _submitting
                              ? const SizedBox(
                                  width: 19,
                                  height: 19,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.3,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined, size: 20),
                          label: Text(
                            _submitting
                                ? 'Enregistrement...'
                                : 'Enregistrer les modifications',
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
