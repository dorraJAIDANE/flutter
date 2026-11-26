import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_l10n.dart';
import '../theme/app_theme.dart';

class OrderStatusMeta {
  const OrderStatusMeta({
    required this.key,
    required this.label,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  final String key;
  final String label;
  final Color color;
  final Color bgColor;
  final IconData icon;
}

class XfyFormatters {
  XfyFormatters._();

  static List<OrderStatusMeta> get statuses => [
        OrderStatusMeta(
          key: 'en_cours',
          label: AppL10n.t('status_en_cours'),
          color: XfyColors.amber,
          bgColor: XfyColors.amberSoft,
          icon: Icons.schedule_rounded,
        ),
        OrderStatusMeta(
          key: 'confirmee',
          label: AppL10n.t('status_confirmee'),
          color: XfyColors.indigo,
          bgColor: XfyColors.indigoSoft,
          icon: Icons.check_circle_outline_rounded,
        ),
        OrderStatusMeta(
          key: 'pas_de_reponse',
          label: AppL10n.t('status_pas_de_reponse'),
          color: const Color(0xFFD97706),
          bgColor: const Color(0xFFFEF3C7),
          icon: Icons.phone_missed_rounded,
        ),
        OrderStatusMeta(
          key: 'traitee',
          label: AppL10n.t('status_traitee'),
          color: XfyColors.violet,
          bgColor: XfyColors.violetSoft,
          icon: Icons.local_shipping_outlined,
        ),
        OrderStatusMeta(
          key: 'encaissee',
          label: AppL10n.t('status_encaissee'),
          color: XfyColors.emerald,
          bgColor: XfyColors.emeraldSoft,
          icon: Icons.verified_rounded,
        ),
        OrderStatusMeta(
          key: 'retournee',
          label: AppL10n.t('status_retournee'),
          color: XfyColors.rose,
          bgColor: XfyColors.roseSoft,
          icon: Icons.assignment_return_outlined,
        ),
        OrderStatusMeta(
          key: 'annulee',
          label: AppL10n.t('status_annulee'),
          color: const Color(0xFF64748B),
          bgColor: const Color(0xFFF1F5F9),
          icon: Icons.cancel_outlined,
        ),
      ];

  /// Supprime les accents français/latins pour reproduire `.normalize('NFD').replace(/[\u0300-\u036f]/g, '')` du Web.
  static String stripAccents(String input) {
    const map = <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'ç': 'c',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'ñ': 'n',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'ý': 'y',
      'ÿ': 'y',
    };
    final lower = input.toLowerCase();
    final sb = StringBuffer();
    for (int i = 0; i < lower.length; i++) {
      final ch = lower[i];
      sb.write(map[ch] ?? ch);
    }
    return sb.toString();
  }

  /// Résolution unifiée multi-transporteurs 100 % IDENTIQUE à `getUnifiedStatus()`
  /// de `analytics.component.ts` et `statistics.component.ts` sur le Web XFY.
  static String computeUnifiedStatus({
    String? status,
    String? statutIntigo,
  }) {
    final s = stripAccents((status ?? '').trim());
    final si = stripAccents((statutIntigo ?? '').trim());
    final combined = '$s $si';

    // Statut XFY explicitement "encaissee" -> toujours comptabilisé comme livré dans les statistiques
    if (s.contains('encaiss')) {
      return 'encaissee';
    }
    if (combined.contains('annul') ||
        combined.contains('cancel') ||
        combined.contains('refus') ||
        combined.contains('rejete')) {
      return 'annulee';
    }
    if (combined.contains('retourn') ||
        combined.contains('retour') ||
        combined.contains('rnp') ||
        combined.contains('echec') ||
        combined.contains('non livre')) {
      return 'retournee';
    }
    // Important : tester "en cours de livraison" AVANT "livre" !
    if (combined.contains('en cours de livraison') ||
        combined.contains('transfert livraison') ||
        combined.contains('livraison en cours') ||
        combined.contains('en livraison') ||
        combined.contains('en cours de route')) {
      return 'traitee';
    }
    if (combined.contains('livre') ||
        combined.contains('encaiss') ||
        combined.contains('paye') ||
        combined.contains('regle') ||
        combined.contains('solde') ||
        combined.contains('recouvr')) {
      return 'encaissee';
    }
    if (combined.contains('trait') ||
        combined.contains('exped') ||
        combined.contains('transit') ||
        combined.contains('remis') ||
        combined.contains('ramass') ||
        combined.contains('dispatch')) {
      return 'traitee';
    }
    if (combined.contains('confirm') ||
        combined.contains('valide') ||
        combined.contains('accept') ||
        combined.contains('nouveau') ||
        combined.contains('nouvelle')) {
      return 'confirmee';
    }
    return 'en_cours';
  }

  static String normalizeStatus(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'en_cours';
    final s = stripAccents(raw.trim()).replaceAll(RegExp(r'[\s-]+'), '_');

    switch (s) {
      case 'en_cours':
      case 'encours':
      case 'en_attente':
        return 'en_cours';
      case 'pas_de_reponse':
      case 'pas_de_reponses':
      case 'injoignable':
        return 'pas_de_reponse';
      case 'confirmee':
      case 'confirme':
      case 'confirmed':
        return 'confirmee';
      case 'traitee':
      case 'traite':
        return 'traitee';
      case 'encaissee':
      case 'encaisse':
      case 'livree':
      case 'livre':
        return 'encaissee';
      case 'annulee':
      case 'annule':
      case 'cancelled':
      case 'canceled':
        return 'annulee';
      case 'retournee':
      case 'retourne':
      case 'retour':
        return 'retournee';
      default:
        return 'en_cours';
    }
  }

  static OrderStatusMeta statusMeta(String? raw) {
    final key = normalizeStatus(raw);
    return statuses.firstWhere(
      (m) => m.key == key,
      orElse: () => statuses.first,
    );
  }

  static String formatTnd(num? value) {
    final v = (value ?? 0).toDouble();
    final isWhole = v == v.truncateToDouble();
    return '${v.toStringAsFixed(isWhole ? 0 : 2)} DT';
  }

  static String formatTndRounded(num? value) {
    final v = (value ?? 0).toDouble().round();
    return '$v DT';
  }

  static final RegExp _priceCleanRe = RegExp(r'[^\d.-]');
  static final RegExp _wsRe = RegExp(r'\s+');
  static final RegExp _pureYmdRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
  static final RegExp _prefixYmdRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

  static double parsePrice(dynamic raw) {
    if (raw == null) return 0;
    if (raw is num) return raw.toDouble();
    final cleaned = raw
        .toString()
        .replaceAll(',', '.')
        .replaceAll(_priceCleanRe, '');
    return double.tryParse(cleaned) ?? 0;
  }

  static String toYmd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Parse robuste 100 % aligné sur `parseDateRobust()` du Web :
  /// gère `DD/MM/YYYY`, `DD/MM/YYYY HH:mm`, `YYYY-MM-DD`, `YYYY-MM-DD HH:mm:ss`,
  /// ISO-8601 et tableaux `[YYYY, M, D]`.
  static DateTime? parseDateRobust(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;

    if (raw is List && raw.length >= 3) {
      final y = int.tryParse(raw[0].toString());
      final m = int.tryParse(raw[1].toString());
      final d = int.tryParse(raw[2].toString());
      if (y != null && m != null && d != null) {
        final h = raw.length >= 4 ? (int.tryParse(raw[3].toString()) ?? 0) : 0;
        final min = raw.length >= 5 ? (int.tryParse(raw[4].toString()) ?? 0) : 0;
        return DateTime(y, m, d, h, min);
      }
    }

    var s = raw.toString().trim();
    if (s.isEmpty ||
        s == 'Non spécifié' ||
        s == 'Non specifie' ||
        s == 'null' ||
        s == 'undefined' ||
        s == 'N/A') {
      return null;
    }

    // 1. Format français DD/MM/YYYY ou DD/MM/YYYY HH:mm(:ss)
    if (s.contains('/')) {
      final spaceParts = s.split(_wsRe);
      if (spaceParts.isNotEmpty && spaceParts[0].contains('/')) {
        final dateParts = spaceParts[0].split('/');
        if (dateParts.length == 3) {
          final day = int.tryParse(dateParts[0]);
          final month = int.tryParse(dateParts[1]);
          final year = int.tryParse(dateParts[2]);
          if (day != null &&
              month != null &&
              year != null &&
              year >= 2000 &&
              month >= 1 &&
              month <= 12 &&
              day >= 1 &&
              day <= 31) {
            int hours = 0;
            int minutes = 0;
            if (spaceParts.length >= 2) {
              final timeParts = spaceParts[1].split(':');
              if (timeParts.length >= 2) {
                hours = int.tryParse(timeParts[0]) ?? 0;
                minutes = int.tryParse(timeParts[1]) ?? 0;
              }
            }
            return DateTime(year, month, day, hours, minutes);
          }
        }
      }
    }

    // 2. Date pure YYYY-MM-DD (locale, sans décalage UTC)
    if (s.length == 10) {
      final pureDate = _pureYmdRe.firstMatch(s);
      if (pureDate != null) {
        return DateTime(
          int.parse(pureDate.group(1)!),
          int.parse(pureDate.group(2)!),
          int.parse(pureDate.group(3)!),
        );
      }
    }

    // 3. Remplacer l'espace entre date et heure par 'T'
    if (s.contains(' ') && !s.contains('T')) {
      s = s.replaceFirst(' ', 'T');
    }

    final parsed = DateTime.tryParse(s);
    if (parsed != null) {
      return parsed.isUtc ? parsed.toLocal() : parsed;
    }

    // 4. Fallback : extraire préfixe YYYY-MM-DD
    final prefix = _prefixYmdRe.firstMatch(s);
    if (prefix != null) {
      return DateTime(
        int.parse(prefix.group(1)!),
        int.parse(prefix.group(2)!),
        int.parse(prefix.group(3)!),
      );
    }

    return null;
  }

  static String formatShortDate(String? rawIso, {String? dayMonth, String? monthYear}) {
    final parsed = parseDateRobust(rawIso);
    if (parsed != null) {
      final now = DateTime.now();
      final hh = parsed.hour.toString().padLeft(2, '0');
      final mm = parsed.minute.toString().padLeft(2, '0');
      if (parsed.year == now.year &&
          parsed.month == now.month &&
          parsed.day == now.day) {
        return "Aujourd'hui • $hh:$mm";
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (parsed.year == yesterday.year &&
          parsed.month == yesterday.month &&
          parsed.day == yesterday.day) {
        return 'Hier • $hh:$mm';
      }
      final dd = parsed.day.toString().padLeft(2, '0');
      final mo = parsed.month.toString().padLeft(2, '0');
      return '$dd/$mo • $hh:$mm';
    }
    if (dayMonth != null && dayMonth.isNotEmpty) {
      return dayMonth;
    }
    return monthYear ?? '';
  }

  static String currentFrenchMonthYear([DateTime? date]) {
    final d = date ?? DateTime.now();
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }

  static String currentDayMonth([DateTime? date]) {
    final d = date ?? DateTime.now();
    return '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}';
  }

  /// Parse la date réelle d'une commande (`timestamp` robuste ou `dayMonth` + `monthYear`).
  static DateTime? parseOrderDate({
    String? timestamp,
    String? dayMonth,
    String? monthYear,
  }) {
    final robust = parseDateRobust(timestamp);
    if (robust != null) return robust;

    const monthMap = <String, int>{
      'janvier': 1,
      'fevrier': 2,
      'février': 2,
      'mars': 3,
      'avril': 4,
      'mai': 5,
      'juin': 6,
      'juillet': 7,
      'aout': 8,
      'août': 8,
      'septembre': 9,
      'octobre': 10,
      'novembre': 11,
      'decembre': 12,
      'décembre': 12,
    };

    int? year;
    int? month;
    if (monthYear != null && monthYear.trim().isNotEmpty) {
      final parts = monthYear.trim().toLowerCase().split(RegExp(r'[\s-]+'));
      for (final p in parts) {
        if (monthMap.containsKey(p)) {
          month = monthMap[p];
        } else if (p.length == 4 && int.tryParse(p) != null) {
          year = int.parse(p);
        }
      }
    }

    int day = 1;
    if (dayMonth != null && dayMonth.trim().isNotEmpty) {
      final dm = dayMonth.trim().split(RegExp(r'[-/]'));
      if (dm.isNotEmpty) {
        day = int.tryParse(dm[0]) ?? 1;
      }
      if (dm.length >= 2 && month == null) {
        month = int.tryParse(dm[1]);
      }
    }

    if (year != null && month != null && month >= 1 && month <= 12) {
      final lastDayOfMonth = DateTime(year, month + 1, 0).day;
      final clampedDay = day.clamp(1, lastDayOfMonth);
      return DateTime(year, month, clampedDay);
    }
    return null;
  }

  static String formatDayMonthShort(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  static String cleanPhone(String? raw) {
    if (raw == null) return '';
    return raw.replaceAll(RegExp(r'[^\d+]'), '');
  }

  static String tunisianWhatsAppNumber(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('216')) return digits;
    if (digits.startsWith('00216')) return digits.substring(2);
    if (digits.length == 8) return '216$digits';
    return digits;
  }

  static Future<bool> launchPhoneCall(String? phone) async {
    final cleaned = cleanPhone(phone);
    if (cleaned.isEmpty) return false;
    final uri = Uri(scheme: 'tel', path: cleaned);
    return launchUrl(uri);
  }

  static Future<bool> launchWhatsApp(String? phone, {String? message}) async {
    final number = tunisianWhatsAppNumber(phone);
    if (number.isEmpty) return false;
    final encoded = message != null ? Uri.encodeComponent(message) : null;
    final url = encoded != null
        ? 'https://wa.me/$number?text=$encoded'
        : 'https://wa.me/$number';
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  static Future<bool> launchExternalWeb(String url) async {
    final normalized =
        url.startsWith('http://') || url.startsWith('https://') ? url : 'https://$url';
    return launchUrl(Uri.parse(normalized), mode: LaunchMode.externalApplication);
  }
}
