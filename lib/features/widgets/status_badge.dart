import 'package:material_ui/material_ui.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.compact = false,
  });

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final meta = XfyFormatters.statusMeta(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: meta.bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(meta.icon, size: compact ? 13 : 14, color: meta.color),
          const SizedBox(width: 5),
          Text(
            meta.label,
            style: TextStyle(
              color: meta.color,
              fontSize: compact ? 11.5 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille dédiée au statut retourné par la société de livraison (`statutIntigo` + nom transporteur).
class CarrierStatusPill extends StatelessWidget {
  const CarrierStatusPill({
    super.key,
    required this.carrierStatus,
    this.carrierName,
    this.compact = false,
  });

  final String carrierStatus;
  final String? carrierName;
  final bool compact;

  ({Color fg, Color bg, IconData icon}) _styleFor(String raw) {
    final s = XfyFormatters.stripAccents(raw.toLowerCase().trim());
    if (s.contains('erreur') ||
        s.contains('annul') ||
        s.contains('supprim') ||
        s.contains('refus') ||
        s.contains('rejet')) {
      return (
        fg: XfyColors.rose,
        bg: XfyColors.roseSoft,
        icon: Icons.error_outline_rounded,
      );
    }
    if (s.contains('retour') ||
        s.contains('rnp') ||
        s.contains('echec') ||
        s.contains('non livre')) {
      return (
        fg: XfyColors.rose,
        bg: XfyColors.roseSoft,
        icon: Icons.assignment_return_rounded,
      );
    }
    if (s.contains('en cours de livraison') ||
        s.contains('livraison en cours') ||
        s.contains('en livraison') ||
        s.contains('transfert') ||
        s.contains('route')) {
      return (
        fg: XfyColors.violet,
        bg: XfyColors.violetSoft,
        icon: Icons.local_shipping_rounded,
      );
    }
    if (s.contains('livre') ||
        s.contains('encaiss') ||
        s.contains('paye') ||
        s.contains('delivered')) {
      return (
        fg: XfyColors.emerald,
        bg: XfyColors.emeraldSoft,
        icon: Icons.verified_rounded,
      );
    }
    return (
      fg: XfyColors.primaryBlue,
      bg: XfyColors.primarySoft,
      icon: Icons.local_shipping_outlined,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(carrierStatus);
    final text = (carrierName != null && carrierName!.trim().isNotEmpty)
        ? '${carrierName!.trim()} • $carrierStatus'
        : carrierStatus;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3.5 : 5,
      ),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: style.fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: compact ? 12.5 : 14, color: style.fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: style.fg,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
