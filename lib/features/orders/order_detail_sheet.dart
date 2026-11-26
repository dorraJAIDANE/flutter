import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/order_model.dart';
import '../../state/app_state.dart';
import '../widgets/status_badge.dart';
import '../widgets/xfy_image.dart';
import 'send_to_delivery_sheet.dart';

class OrderDetailSheet extends StatefulWidget {
  const OrderDetailSheet({
    super.key,
    required this.state,
    required this.order,
  });

  final AppState state;
  final OrderModel order;

  @override
  State<OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends State<OrderDetailSheet> {
  late OrderModel _order;
  late TextEditingController _commentCtrl;
  bool _isSaving = false;
  bool _isRefreshingCarrier = false;

  /// Images résolues par nom de produit (catalogue local + fallback API `/produits/nom`).
  final Map<String, String> _productImages = {};

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _commentCtrl = TextEditingController(text: _order.commentaire ?? '');
    _resolveProductImages();
    if (_order.hasBordereau) {
      _refreshCarrierStatus(silent: true);
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _resolveProductImages() async {
    final items = _order.parsedLineItems;
    final storeId = _order.storeId ?? widget.state.selectedStore?.id ?? 0;

    for (final item in items) {
      final catalogImg = widget.state.resolveCatalogProductImage(item.name);
      if (catalogImg != null) {
        _productImages[item.name] = catalogImg;
      } else if (storeId > 0) {
        final fetched = await widget.state.api
            .getProductImageByName(item.name, storeId);
        if (fetched != null && mounted) {
          setState(() => _productImages[item.name] = fetched);
        }
      }
    }
    if (mounted && _productImages.isNotEmpty) {
      setState(() {});
    }
  }

  Future<void> _refreshCarrierStatus({bool silent = false}) async {
    if (_isRefreshingCarrier || !_order.hasBordereau) return;
    if (!silent) {
      HapticFeedback.selectionClick();
    }
    setState(() => _isRefreshingCarrier = true);
    try {
      final updated = await widget.state.refreshOrderCarrierStatus(_order);
      if (!mounted) return;
      setState(() => _order = updated);
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              updated.hasCarrierStatus
                  ? 'Suivi livraison : ${updated.carrierStatusLabel}'
                  : 'Statut transporteur vérifié',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _isRefreshingCarrier = false);
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    if (_isSaving || newStatus == _order.normalizedStatus) return;
    HapticFeedback.selectionClick();
    setState(() => _isSaving = true);
    try {
      final updated = await widget.state.updateOrderStatus(
        _order,
        newStatus,
        newComment: _commentCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _order = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Statut mis à jour : ${XfyFormatters.statusMeta(newStatus).label}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveComment() async {
    setState(() => _isSaving = true);
    try {
      final updated = await widget.state.updateOrderStatus(
        _order,
        _order.normalizedStatus,
        newComment: _commentCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() => _order = updated);
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note enregistrée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openDeliveryOrEditSheet({
    required bool dispatchMode,
    String? initialCarrier,
  }) async {
    HapticFeedback.selectionClick();
    final result =
        await showModalBottomSheet<({OrderModel order, String message})>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SendToDeliverySheet(
        state: widget.state,
        order: _order,
        dispatchMode: dispatchMode,
        initialCarrier: initialCarrier,
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _order = result.order;
        _commentCtrl.text = _order.commentaire ?? '';
      });
      _resolveProductImages();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: XfyColors.emerald,
          content: Text(result.message),
        ),
      );
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la commande ?'),
        content: Text(
          'Voulez-vous vraiment supprimer la commande #${_order.id} de ${_order.nom} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: XfyColors.rose,
              minimumSize: const Size(0, 42),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.state.deleteOrder(_order);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Commande #${_order.id} supprimée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final carriers = widget.state.deliveryCompanies;
    final missingFields = _order.missingDeliveryFields;
    final lineItems = _order.parsedLineItems;
    final hasAnyMedia = _order.hasCapture || _productImages.isNotEmpty;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.55,
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Commande #${_order.reference?.isNotEmpty == true ? _order.reference : _order.id}',
                            style: const TextStyle(
                              fontSize: 18.5,
                              fontWeight: FontWeight.w800,
                              color: XfyColors.ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            XfyFormatters.formatShortDate(
                              _order.timestamp,
                              dayMonth: _order.dayMonth,
                              monthYear: _order.monthYear,
                            ),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: XfyColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      status: _order.normalizedStatus == 'pas_de_reponse'
                          ? 'pas_de_reponse'
                          : _order.unifiedStatus,
                    ),
                    IconButton(
                      tooltip: 'Modifier',
                      onPressed: () =>
                          _openDeliveryOrEditSheet(dispatchMode: false),
                      icon: const Icon(
                        Icons.edit_outlined,
                        size: 21,
                        color: XfyColors.primaryVibrant,
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
                child: ListView(
                  controller: scrollCtrl,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    16,
                    20,
                    MediaQuery.of(context).viewInsets.bottom + 24,
                  ),
                  children: [
                    // 1. Suivi Société de Livraison (statut transporteur + bordereau + refresh live)
                    if (_order.hasBordereau || _order.hasCarrierStatus) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: XfyColors.primarySoft.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: XfyColors.primaryVibrant
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.local_shipping_rounded,
                                  size: 18,
                                  color: XfyColors.primaryVibrant,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Suivi société de livraison${_order.formattedCarrierName != null ? ' (${_order.formattedCarrierName})' : ''}',
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: XfyColors.primaryDark,
                                    ),
                                  ),
                                ),
                                if (_order.hasBordereau)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      foregroundColor: XfyColors.primaryVibrant,
                                    ),
                                    onPressed: _isRefreshingCarrier
                                        ? null
                                        : () => _refreshCarrierStatus(),
                                    icon: _isRefreshingCarrier
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.sync_rounded,
                                            size: 17,
                                          ),
                                    label: const Text(
                                      'Actualiser',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (_order.hasCarrierStatus)
                                  CarrierStatusPill(
                                    carrierStatus: _order.carrierStatusLabel!,
                                    carrierName: _order.formattedCarrierName,
                                  )
                                else
                                  const CarrierStatusPill(
                                    carrierStatus: 'En attente de synchronisation',
                                  ),
                                if (_order.hasBordereau)
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: _order.numeroBordereau!,
                                        ),
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text('N° Bordereau copié'),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: XfyColors.surface,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: XfyColors.border,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.qr_code_2_rounded,
                                            size: 14,
                                            color: XfyColors.indigo,
                                          ),
                                          const SizedBox(width: 5),
                                          Text(
                                            _order.numeroBordereau!,
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: XfyColors.indigo,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 2. Capture d'écran & Images des produits (zoom plein écran au tap)
                    if (hasAnyMedia) ...[
                      const Text(
                        'Capture & Photos des produits',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: XfyColors.ink,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 118,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            if (_order.hasCapture)
                              _MediaPreviewTile(
                                source: _order.captureSource!,
                                label: 'Capture commande',
                                badge: 'Capture',
                                badgeColor: const Color(0xFFFF6600),
                                onTap: () => showXfyImageLightbox(
                                  context,
                                  source: _order.captureSource!,
                                  title: 'Capture • Commande #${_order.id}',
                                  subtitle: _order.nom,
                                ),
                              ),
                            ...lineItems
                                .where((item) =>
                                    _productImages.containsKey(item.name))
                                .map((item) {
                              final src = _productImages[item.name]!;
                              return _MediaPreviewTile(
                                source: src,
                                label: item.name,
                                badge: '×${item.quantity}',
                                badgeColor: XfyColors.primaryVibrant,
                                onTap: () => showXfyImageLightbox(
                                  context,
                                  source: src,
                                  title: item.name,
                                  subtitle:
                                      'Qté : ${item.quantity}${item.unitPrice > 0 ? ' • ${XfyFormatters.formatTnd(item.unitPrice)}' : ''}',
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 3. Client & Call / WhatsApp
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: XfyColors.canvas,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: XfyColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: XfyColors.primarySoft,
                                foregroundColor: XfyColors.primary,
                                child: Text(
                                  _order.nom.isNotEmpty
                                      ? _order.nom[0].toUpperCase()
                                      : 'C',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _order.nom,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: XfyColors.ink,
                                      ),
                                    ),
                                    if (_order.phoneNumber.isNotEmpty)
                                      GestureDetector(
                                        onTap: () {
                                          Clipboard.setData(
                                            ClipboardData(
                                                text: _order.phoneNumber),
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                              content: Text('Numéro copié'),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          _order.phone2 != null &&
                                                  _order.phone2!.isNotEmpty
                                              ? '${_order.phoneNumber} • ${_order.phone2}'
                                              : _order.phoneNumber,
                                          style: const TextStyle(
                                            fontSize: 13.5,
                                            color: XfyColors.inkSecondary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: XfyColors.primaryBlue,
                                    minimumSize: const Size(0, 44),
                                  ),
                                  onPressed: _order.phoneNumber.isEmpty
                                      ? null
                                      : () => XfyFormatters.launchPhoneCall(
                                            _order.phoneNumber,
                                          ),
                                  icon: const Icon(Icons.call_rounded, size: 18),
                                  label: const Text('Appeler'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF16A34A),
                                    minimumSize: const Size(0, 44),
                                  ),
                                  onPressed: _order.phoneNumber.isEmpty
                                      ? null
                                      : () => XfyFormatters.launchWhatsApp(
                                            _order.phoneNumber,
                                            message:
                                                'Bonjour ${_order.nom}, nous vous contactons au sujet de votre commande #${_order.id}.',
                                          ),
                                  icon: const Icon(Icons.chat_rounded, size: 18),
                                  label: const Text('WhatsApp'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 4. Expédier à la société de livraison (avec détection champs manquants)
                    if (_order.canDispatchToCarrier) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: missingFields.isNotEmpty
                              ? XfyColors.amberSoft.withValues(alpha: 0.7)
                              : XfyColors.indigoSoft.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: (missingFields.isNotEmpty
                                    ? XfyColors.amber
                                    : XfyColors.indigo)
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  missingFields.isNotEmpty
                                      ? Icons.edit_location_alt_rounded
                                      : Icons.local_shipping_rounded,
                                  size: 20,
                                  color: missingFields.isNotEmpty
                                      ? XfyColors.amber
                                      : XfyColors.indigo,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    missingFields.isNotEmpty
                                        ? 'Champs manquants avant expédition'
                                        : 'Prêt à envoyer à la société de livraison',
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                      color: missingFields.isNotEmpty
                                          ? const Color(0xFF92400E)
                                          : XfyColors.indigo,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (missingFields.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                'À compléter : ${missingFields.join(' • ')}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF92400E),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: XfyColors.primaryVibrant,
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size.fromHeight(46),
                                ),
                                onPressed: () => _openDeliveryOrEditSheet(
                                  dispatchMode: true,
                                ),
                                icon: const Icon(
                                  Icons.send_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  missingFields.isNotEmpty
                                      ? 'Compléter & Envoyer au transporteur'
                                      : (carriers.length == 1
                                          ? 'Vérifier & Envoyer à ${OrderModel.formatCarrierLabel(carriers.first)}'
                                          : 'Envoyer à la société de livraison'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 5. Details Card
                    _DetailSection(
                      title: 'Détails & Livraison',
                      onEdit: () =>
                          _openDeliveryOrEditSheet(dispatchMode: false),
                      children: [
                        _DetailRow(
                          label: 'Produit(s)',
                          value: _order.produit ?? 'Non renseigné',
                        ),
                        if (_order.quantite != null &&
                            _order.quantite!.isNotEmpty)
                          _DetailRow(label: 'Quantité', value: _order.quantite!),
                        _DetailRow(
                          label: 'Total',
                          value: XfyFormatters.formatTnd(_order.effectiveTotal),
                          bold: true,
                        ),
                        if (_order.fraisLivraison != null &&
                            _order.fraisLivraison! > 0)
                          _DetailRow(
                            label: 'Frais de livraison',
                            value:
                                XfyFormatters.formatTnd(_order.fraisLivraison),
                          ),
                        _DetailRow(
                          label: 'Localisation',
                          value: _order.locationLabel,
                        ),
                        if (_order.adresse != null &&
                            _order.adresse!.trim().isNotEmpty)
                          _DetailRow(label: 'Adresse', value: _order.adresse!),
                        if (_order.exchange)
                          const _DetailRow(
                            label: 'Type colis',
                            value: 'Échange',
                          ),
                        if (_order.hasBordereau)
                          _DetailRow(
                            label: 'N° Bordereau',
                            value: _order.numeroBordereau!,
                            copyable: true,
                          ),
                        if (_order.formattedCarrierName != null)
                          _DetailRow(
                            label: 'Transporteur',
                            value: _order.formattedCarrierName!,
                          ),
                        if (_order.hasCarrierStatus)
                          _DetailRow(
                            label: 'Statut livraison',
                            value: _order.carrierStatusLabel!,
                          ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // 6. Change Status Pills
                    const Text(
                      'Changer le statut XFY',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: XfyColors.ink,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: XfyFormatters.statuses.map((meta) {
                        final active = _order.normalizedStatus == meta.key;
                        return ChoiceChip(
                          selected: active,
                          showCheckmark: false,
                          avatar: Icon(
                            meta.icon,
                            size: 16,
                            color: active ? Colors.white : meta.color,
                          ),
                          label: Text(meta.label),
                          selectedColor: meta.color,
                          backgroundColor: meta.bgColor,
                          side: BorderSide(
                            color: active ? meta.color : Colors.transparent,
                          ),
                          labelStyle: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white : meta.color,
                          ),
                          onSelected:
                              _isSaving ? null : (_) => _updateStatus(meta.key),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // 7. Comment / Note
                    const Text(
                      'Note interne / Commentaire',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: XfyColors.ink,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentCtrl,
                            maxLines: 2,
                            minLines: 1,
                            decoration: const InputDecoration(
                              hintText:
                                  'Ajouter une note (ex: rappeler à 14h)...',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: XfyColors.primary,
                            foregroundColor: Colors.white,
                            fixedSize: const Size(48, 48),
                          ),
                          onPressed: _isSaving ? null : _saveComment,
                          icon: const Icon(Icons.check_rounded),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),
                    TextButton.icon(
                      style:
                          TextButton.styleFrom(foregroundColor: XfyColors.rose),
                      onPressed: _confirmDelete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 19),
                      label: const Text(
                        'Supprimer cette commande',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaPreviewTile extends StatelessWidget {
  const _MediaPreviewTile({
    required this.source,
    required this.label,
    required this.badge,
    required this.badgeColor,
    required this.onTap,
  });

  final String source;
  final String label;
  final String badge;
  final Color badgeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 104,
          decoration: BoxDecoration(
            color: XfyColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: XfyColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    XfySmartImage(
                      source: source,
                      fit: BoxFit.cover,
                      cacheWidth: 240,
                      cacheHeight: 240,
                    ),
                    Positioned(
                      top: 5,
                      left: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.zoom_in_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: XfyColors.ink,
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

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.children,
    this.onEdit,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: XfyColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: XfyColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: XfyColors.inkSecondary,
                  ),
                ),
              ),
              if (onEdit != null)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: XfyColors.primaryVibrant,
                  ),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text(
                    'Modifier',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.copyable = false,
  });

  final String label;
  final String value;
  final bool bold;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style:
                  const TextStyle(fontSize: 13, color: XfyColors.inkSecondary),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: copyable
                  ? () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Copié dans le presse-papiers'),
                        ),
                      );
                    }
                  : null,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: bold ? 15 : 13.5,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: copyable ? XfyColors.indigo : XfyColors.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
