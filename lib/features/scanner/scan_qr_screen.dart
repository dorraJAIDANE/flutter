import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/order_model.dart';
import '../../data/services/native_order_monitor_bridge.dart';
import '../../state/app_state.dart';
import '../orders/order_detail_sheet.dart';
import '../widgets/status_badge.dart';

/// Parseur dédié aux QR codes et codes-barres XFY :
/// • `https://xfy.tn/scan-commande/12345`
/// • `https://xfy.tn/scan-commande/CMD-2026-001`
/// • Numéro de commande direct (`12345`, `#12345`, `CMD-...`)
/// • Numéro de bordereau transporteur (Intigo, Navex, First, Jax, XDelivery, Cosmos, Colissimo, Qwikpak)
class XfyQrParser {
  XfyQrParser._();

  static String extractCode(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';

    final scanRoute = RegExp(
      r'scan-commande/([^/?#\s]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (scanRoute != null) {
      return Uri.decodeComponent(scanRoute.group(1)!).trim();
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme && uri.pathSegments.isNotEmpty) {
      final nonEmpty =
          uri.pathSegments.where((s) => s.trim().isNotEmpty).toList();
      if (nonEmpty.isNotEmpty) {
        return Uri.decodeComponent(nonEmpty.last).trim();
      }
    }

    if (trimmed.startsWith('#')) {
      return trimmed.substring(1).trim();
    }

    return trimmed;
  }

  static bool isXfyScanUrl(String raw) {
    return raw.toLowerCase().contains('scan-commande/');
  }
}

/// Page Scanner QR Code XFY — remplace l'onglet Clients.
/// Lance un scanner caméra Android 100 % natif (`QrScannerActivity` avec CameraX `PreviewView`
/// + Google ML Kit) pour un flux caméra continu, fluide et sans coupure.
class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({
    super.key,
    required this.state,
    required this.isActive,
  });

  final AppState state;
  final bool isActive;

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  bool _isLaunchingCamera = false;
  bool _isProcessing = false;
  String? _lastScannedRaw;
  String? _errorMessage;
  OrderModel? _scannedOrder;
  final List<OrderModel> _scanHistory = [];

  Future<void> _launchNativeScanner() async {
    if (_isLaunchingCamera || _isProcessing) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isLaunchingCamera = true;
      _errorMessage = null;
    });

    try {
      final result = await NativeOrderMonitorBridge.instance.openNativeQrScanner();
      if (!mounted) return;
      setState(() => _isLaunchingCamera = false);

      if (result == null) return;
      if (result['manual'] == true) {
        await _openManualCodeDialog();
        return;
      }
      final raw = result['code']?.toString() ?? '';
      if (raw.trim().isNotEmpty) {
        await _handleRawCode(raw);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLaunchingCamera = false;
        _errorMessage = 'Impossible d\'ouvrir la caméra : $e';
      });
    }
  }

  Future<void> _handleRawCode(String raw) async {
    if (_isProcessing) return;
    final code = XfyQrParser.extractCode(raw);
    if (code.isEmpty) return;

    HapticFeedback.heavyImpact();
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _lastScannedRaw = raw;
    });

    try {
      final order = await widget.state.lookupScannedOrder(code);
      if (!mounted) return;

      setState(() {
        _scannedOrder = order;
        _isProcessing = false;
        _scanHistory.removeWhere((o) => o.id == order.id);
        _scanHistory.insert(0, order);
        if (_scanHistory.length > 10) {
          _scanHistory.removeLast();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _scannedOrder = null;
        _errorMessage = e.toString();
        _isProcessing = false;
      });
    }
  }

  Future<void> _openManualCodeDialog() async {
    final ctrl = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppL10n.t('scanner_manual_title')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: AppL10n.t('scanner_manual_hint'),
            prefixIcon: const Icon(Icons.qr_code_rounded),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppL10n.t('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(AppL10n.t('search')),
          ),
        ],
      ),
    );
    if (submitted != null && submitted.isNotEmpty) {
      await _handleRawCode(submitted);
    }
  }

  Future<void> _quickChangeStatus(OrderModel order, String newStatus) async {
    HapticFeedback.mediumImpact();
    setState(() => _isProcessing = true);
    try {
      final updated = await widget.state.updateOrderStatus(order, newStatus);
      if (!mounted) return;
      setState(() {
        _scannedOrder = updated;
        _isProcessing = false;
        final idx = _scanHistory.indexWhere((o) => o.id == updated.id);
        if (idx >= 0) _scanHistory[idx] = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Commande #${updated.id} → ${XfyFormatters.statusMeta(newStatus).label}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    }
  }

  Future<void> _quickMarkRetour(OrderModel order) async {
    HapticFeedback.mediumImpact();
    setState(() => _isProcessing = true);
    try {
      final updated = await widget.state.markScannedRetour(order);
      if (!mounted) return;
      setState(() {
        _scannedOrder = updated;
        _isProcessing = false;
        final idx = _scanHistory.indexWhere((o) => o.id == updated.id);
        if (idx >= 0) _scanHistory[idx] = updated;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Retour enregistré pour la commande #${updated.id}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: XfyColors.rose, content: Text('Erreur : $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: XfyColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Header lumineux Web XFY
            Padding(
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
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: XfyColors.statsGradient,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: [
                          BoxShadow(
                            color: XfyColors.primaryVibrant.withValues(alpha: 0.28),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppL10n.t('scanner_title'),
                            style: const TextStyle(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w900,
                              color: XfyColors.ink,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            AppL10n.t('scanner_sub'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: XfyColors.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: AppL10n.t('scanner_manual_tooltip'),
                      style: IconButton.styleFrom(
                        backgroundColor: XfyColors.primarySoft,
                        foregroundColor: XfyColors.primaryVibrant,
                      ),
                      onPressed: _openManualCodeDialog,
                      icon: const Icon(Icons.keyboard_rounded, size: 20),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Contenu principal : Chargement / Commande scannée / Erreur / Accueil Scanner
            Expanded(
              child: _isProcessing
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            color: XfyColors.primaryVibrant,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            AppL10n.t('scanner_searching'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: XfyColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _scannedOrder != null
                      ? _buildScannedOrderView(_scannedOrder!)
                      : _errorMessage != null
                          ? _buildErrorView(_errorMessage!)
                          : _buildScannerHomeView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerHomeView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        // Carte héroïque lumineuse pour lancer le scanner caméra natif plein écran
        InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: _launchNativeScanner,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
            decoration: BoxDecoration(
              gradient: XfyColors.statsGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: XfyColors.primaryVibrant.withValues(alpha: 0.32),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                    size: 46,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  AppL10n.t('scanner_hero_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppL10n.t('scanner_hero_sub'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.camera_alt_rounded,
                        color: XfyColors.primaryVibrant,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isLaunchingCamera
                            ? AppL10n.t('scanner_opening')
                            : AppL10n.t('scanner_open_camera'),
                        style: const TextStyle(
                          color: XfyColors.primaryVibrant,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Bouton saisie manuelle rapide
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            backgroundColor: XfyColors.surface,
            foregroundColor: XfyColors.primaryVibrant,
            side: const BorderSide(color: XfyColors.border),
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _openManualCodeDialog,
          icon: const Icon(Icons.edit_outlined, size: 18),
          label: Text(
            AppL10n.t('scanner_manual_btn'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),

        const SizedBox(height: 16),

        // Carte explicative des formats supportés
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: XfyColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: XfyColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.verified_outlined,
                color: XfyColors.emerald,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  AppL10n.t('scanner_help'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: XfyColors.inkSecondary,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Historique des derniers scans de la session
        if (_scanHistory.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(
            AppL10n.t('scanner_recent'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: XfyColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          ..._scanHistory.map(
            (o) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  setState(() {
                    _scannedOrder = o;
                    _errorMessage = null;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: XfyColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: XfyColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: XfyColors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.qr_code_2_rounded,
                          color: XfyColors.primaryVibrant,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '#${o.id} • ${o.nom}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: XfyColors.ink,
                              ),
                            ),
                            Text(
                              '${XfyFormatters.formatTnd(o.effectiveTotal)} • ${o.locationLabel}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: XfyColors.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      StatusBadge(
                        status: o.normalizedStatus == 'pas_de_reponse'
                            ? 'pas_de_reponse'
                            : o.unifiedStatus,
                        compact: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildErrorView(String message) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: XfyColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: XfyColors.border),
            boxShadow: XfyColors.cardShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: XfyColors.roseSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: XfyColors.rose,
                  size: 28,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'QR code non reconnu ou commande introuvable',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: XfyColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: XfyColors.inkSecondary,
                ),
              ),
              if (_lastScannedRaw != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: XfyColors.canvas,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _lastScannedRaw!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: XfyColors.inkMuted,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => setState(() => _errorMessage = null),
                      child: const Text('Retour'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: _launchNativeScanner,
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: const Text('Rescanner'),
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

  Widget _buildScannedOrderView(OrderModel order) {
    final items = order.parsedLineItems;
    final productsDisplay = items.isNotEmpty
        ? items.map((e) => '${e.quantity}× ${e.name}').join('\n')
        : (order.produit ?? 'Aucun produit');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Container(
          decoration: BoxDecoration(
            color: XfyColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: XfyColors.border),
            boxShadow: XfyColors.cardShadow,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: XfyColors.statsGradient,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.verified_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Commande #${order.id}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            order.nom,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(
                      status: order.normalizedStatus == 'pas_de_reponse'
                          ? 'pas_de_reponse'
                          : order.unifiedStatus,
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoBox(
                      label: 'Produit(s)',
                      value: productsDisplay,
                      icon: Icons.shopping_bag_outlined,
                    ),
                    const SizedBox(height: 10),
                    _InfoBox(
                      label: 'Adresse de livraison',
                      value: [
                        if (order.adresse != null &&
                            order.adresse!.trim().isNotEmpty)
                          order.adresse!.trim(),
                        order.locationLabel,
                      ].join(' • '),
                      icon: Icons.location_on_outlined,
                    ),
                    if (order.hasBordereau) ...[
                      const SizedBox(height: 10),
                      _InfoBox(
                        label: 'Bordereau / Transporteur',
                        value:
                            '${order.numeroBordereau}${order.deliveryCompany != null ? ' (${order.deliveryCompany})' : ''}${order.statutIntigo != null && order.statutIntigo != 'N/A' ? ' • ${order.statutIntigo}' : ''}',
                        icon: Icons.local_shipping_outlined,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: XfyColors.emeraldSoft,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'TOTAL À ENCAISSER',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: XfyColors.emerald,
                            ),
                          ),
                          Text(
                            XfyFormatters.formatTnd(order.effectiveTotal),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: XfyColors.emerald,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: XfyColors.primaryBlue,
                              minimumSize: const Size(0, 44),
                            ),
                            onPressed: order.phoneNumber.isEmpty
                                ? null
                                : () => XfyFormatters.launchPhoneCall(
                                      order.phoneNumber,
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
                            onPressed: order.phoneNumber.isEmpty
                                ? null
                                : () => XfyFormatters.launchWhatsApp(
                                      order.phoneNumber,
                                      message:
                                          'Bonjour ${order.nom}, concernant votre commande #${order.id}.',
                                    ),
                            icon: const Icon(Icons.chat_rounded, size: 18),
                            label: const Text('WhatsApp'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Text(
                      'Actions rapides',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: XfyColors.ink,
                      ),
                    ),
                    const SizedBox(height: 10),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _QuickActionChip(
                          label: 'Confirmée',
                          icon: Icons.check_circle_outline_rounded,
                          color: XfyColors.indigo,
                          bg: XfyColors.indigoSoft,
                          disabled: _isProcessing,
                          onTap: () => _quickChangeStatus(order, 'confirmee'),
                        ),
                        _QuickActionChip(
                          label: 'En livraison',
                          icon: Icons.local_shipping_outlined,
                          color: XfyColors.violet,
                          bg: XfyColors.violetSoft,
                          disabled: _isProcessing,
                          onTap: () => _quickChangeStatus(order, 'traitee'),
                        ),
                        _QuickActionChip(
                          label: 'Livrée / Encaissée',
                          icon: Icons.verified_rounded,
                          color: XfyColors.emerald,
                          bg: XfyColors.emeraldSoft,
                          disabled: _isProcessing,
                          onTap: () => _quickChangeStatus(order, 'encaissee'),
                        ),
                        _QuickActionChip(
                          label: 'Marquer Retour',
                          icon: Icons.assignment_return_outlined,
                          color: XfyColors.rose,
                          bg: XfyColors.roseSoft,
                          disabled: _isProcessing,
                          onTap: () => _quickMarkRetour(order),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              side: const BorderSide(color: XfyColors.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => OrderDetailSheet(
                                  state: widget.state,
                                  order: order,
                                ),
                              );
                            },
                            icon: const Icon(
                              Icons.open_in_full_rounded,
                              size: 17,
                            ),
                            label: const Text('Fiche complète'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                            ),
                            onPressed: () {
                              setState(() => _scannedOrder = null);
                              _launchNativeScanner();
                            },
                            icon: const Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 18,
                            ),
                            label: const Text('Nouveau scan'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: XfyColors.canvas,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: XfyColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: XfyColors.primaryVibrant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: XfyColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: XfyColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatelessWidget {
  const _QuickActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.bg,
    required this.disabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color bg;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
