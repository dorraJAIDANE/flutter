import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/order_model.dart';
import '../../state/app_state.dart';
import '../widgets/status_badge.dart';

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
  bool _isSendingCarrier = false;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _commentCtrl = TextEditingController(text: _order.commentaire ?? '');
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
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

  Future<void> _sendToCarrier(String carrier) async {
    setState(() => _isSendingCarrier = true);
    HapticFeedback.mediumImpact();
    try {
      final msg = await widget.state.sendOrderToCarrier(_order, carrier);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _isSendingCarrier = false);
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

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.84,
      minChildSize: 0.55,
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Commande #${_order.id}',
                            style: const TextStyle(
                              fontSize: 19,
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
                    // Client & Call / WhatsApp
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
                                  style: const TextStyle(fontWeight: FontWeight.w800),
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
                                            ClipboardData(text: _order.phoneNumber),
                                          );
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Numéro copié'),
                                            ),
                                          );
                                        },
                                        child: Text(
                                          _order.phoneNumber,
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

                    // Details Card
                    _DetailSection(
                      title: 'Détails & Livraison',
                      children: [
                        _DetailRow(
                          label: 'Produit(s)',
                          value: _order.produit ?? 'Non renseigné',
                        ),
                        if (_order.quantite != null && _order.quantite!.isNotEmpty)
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
                            value: XfyFormatters.formatTnd(_order.fraisLivraison),
                          ),
                        _DetailRow(
                          label: 'Localisation',
                          value: _order.locationLabel,
                        ),
                        if (_order.adresse != null &&
                            _order.adresse!.trim().isNotEmpty)
                          _DetailRow(label: 'Adresse', value: _order.adresse!),
                        if (_order.hasBordereau)
                          _DetailRow(
                            label: 'N° Bordereau',
                            value: _order.numeroBordereau!,
                            copyable: true,
                          ),
                        if (_order.deliveryCompany != null &&
                            _order.deliveryCompany!.isNotEmpty)
                          _DetailRow(
                            label: 'Transporteur',
                            value: _order.deliveryCompany!,
                          ),
                        if (_order.statutIntigo != null &&
                            _order.statutIntigo!.trim().isNotEmpty &&
                            _order.statutIntigo!.trim().toUpperCase() != 'N/A')
                          _DetailRow(
                            label: 'Statut colis',
                            value: _order.statutIntigo!.trim(),
                          ),
                      ],
                    ),

                    const SizedBox(height: 18),

                    // Change Status Pills
                    const Text(
                      'Changer le statut',
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
                          onSelected: _isSaving ? null : (_) => _updateStatus(meta.key),
                        );
                      }).toList(),
                    ),

                    // Carrier Dispatch (if configured and not yet shipped)
                    if (carriers.isNotEmpty && !_order.hasBordereau) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'Expédier via votre transporteur',
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
                        children: carriers.map((carrier) {
                          return FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              backgroundColor: XfyColors.indigoSoft,
                              foregroundColor: XfyColors.indigo,
                              minimumSize: const Size(0, 44),
                            ),
                            onPressed: _isSendingCarrier
                                ? null
                                : () => _sendToCarrier(carrier),
                            icon: const Icon(Icons.local_shipping_rounded, size: 18),
                            label: Text('Envoyer à $carrier'),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // Comment / Note
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
                              hintText: 'Ajouter une note (ex: rappeler à 14h)...',
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
                      style: TextButton.styleFrom(foregroundColor: XfyColors.rose),
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

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

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
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: XfyColors.inkSecondary,
            ),
          ),
          const SizedBox(height: 10),
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
              style: const TextStyle(fontSize: 13, color: XfyColors.inkSecondary),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: copyable
                  ? () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copié dans le presse-papiers')),
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
