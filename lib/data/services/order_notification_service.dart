import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/utils/formatters.dart';
import '../models/order_model.dart';

/// Définition d'une sonnerie de commande supportée nativement sur Android (res/raw + canal dédié)
/// et iOS (bundle Xcode + `UNNotificationSound`) ainsi qu'en aperçu in-app (`assets/sounds/`).
class OrderRingtoneOption {
  const OrderRingtoneOption({
    required this.id,
    required this.rawResource,
    required this.fileName,
    required this.androidChannelId,
    required this.androidChannelName,
    required this.titleKey,
    required this.subtitleKey,
    this.isDefault = false,
  });

  final String id;
  final String rawResource;
  final String fileName;
  final String androidChannelId;
  final String androidChannelName;
  final String titleKey;
  final String subtitleKey;
  final bool isDefault;
}

/// Gère les notifications Android/iOS haute priorité + 4 sonneries au choix :
/// 1. Cha-Ching Shopify / Converty (par défaut)
/// 2. Pièces d'or (Cash Drop)
/// 3. Carillon Crystal
/// 4. Succès Vente (Pop)
class OrderNotificationService {
  OrderNotificationService._();
  static final OrderNotificationService instance = OrderNotificationService._();

  static const String defaultRingtoneId = 'shopify_chaching';

  static const List<OrderRingtoneOption> ringtones = [
    OrderRingtoneOption(
      id: 'shopify_chaching',
      rawResource: 'shopify_chaching',
      fileName: 'shopify_chaching.wav',
      androidChannelId: 'xfy_orders_shopify_chaching_v5',
      androidChannelName: 'Commandes XFY • Cha-Ching (Shopify)',
      titleKey: 'ringtone_shopify_title',
      subtitleKey: 'ringtone_shopify_sub',
      isDefault: true,
    ),
    OrderRingtoneOption(
      id: 'gold_coins',
      rawResource: 'gold_coins',
      fileName: 'gold_coins.wav',
      androidChannelId: 'xfy_orders_gold_coins_v4',
      androidChannelName: "Commandes XFY • Pièces d'or",
      titleKey: 'ringtone_coins_title',
      subtitleKey: 'ringtone_coins_sub',
    ),
    OrderRingtoneOption(
      id: 'crystal_bell',
      rawResource: 'crystal_bell',
      fileName: 'crystal_bell.wav',
      androidChannelId: 'xfy_orders_crystal_bell_v4',
      androidChannelName: 'Commandes XFY • Carillon Crystal',
      titleKey: 'ringtone_crystal_title',
      subtitleKey: 'ringtone_crystal_sub',
    ),
    OrderRingtoneOption(
      id: 'sale_pop',
      rawResource: 'sale_pop',
      fileName: 'sale_pop.wav',
      androidChannelId: 'xfy_orders_sale_pop_v4',
      androidChannelName: 'Commandes XFY • Succès Pop',
      titleKey: 'ringtone_pop_title',
      subtitleKey: 'ringtone_pop_sub',
    ),
  ];

  static OrderRingtoneOption resolveRingtone(String? id) {
    for (final r in ringtones) {
      if (r.id == id) return r;
    }
    return ringtones.first;
  }

  static const _channelSoundDesc =
      'Alertes sonores instantanées à chaque nouvelle commande reçue';
  static const _channelSilentId = 'xfy_orders_silent_v4';
  static const _channelSilentName = 'Nouvelles commandes XFY (Silencieux)';
  static const _channelSilentDesc = 'Alertes visuelles sans sonnerie';

  static const _prefNotifEnabled = 'xfy_notif_enabled';
  static const _prefSoundEnabled = 'xfy_notif_sound_enabled';
  static const _prefSoundKey = 'xfy_notif_sound_key';
  static const _prefBgMonitorEnabled = 'xfy_bg_monitor_enabled';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _initialized = false;
  bool notificationsEnabled = true;
  bool soundEnabled = true;
  String selectedRingtoneId = defaultRingtoneId;
  bool backgroundMonitorEnabled = true;
  bool systemPermissionGranted = true;

  OrderRingtoneOption get currentRingtone =>
      resolveRingtone(selectedRingtoneId);

  VoidCallback? onNotificationTapped;

  Future<void> init({VoidCallback? onTap}) async {
    onNotificationTapped = onTap;
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    notificationsEnabled = prefs.getBool(_prefNotifEnabled) ?? true;
    soundEnabled = prefs.getBool(_prefSoundEnabled) ?? true;
    selectedRingtoneId =
        resolveRingtone(prefs.getString(_prefSoundKey)).id;
    backgroundMonitorEnabled = prefs.getBool(_prefBgMonitorEnabled) ?? true;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    try {
      await _plugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (_) {
          onNotificationTapped?.call();
        },
      );
    } catch (e) {
      debugPrint('[OrderNotificationService] init error: $e');
    }

    try {
      await _audioPlayer.setAudioContext(
        AudioContext(
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
    } catch (_) {
      // Optionnel selon la plateforme
    }

    await _setupAndroidChannelsAndPermissions();
  }

  Future<void> _setupAndroidChannelsAndPermissions() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    try {
      final granted = await androidPlugin.requestNotificationsPermission();
      if (granted != null) {
        systemPermissionGranted = granted;
      } else {
        final enabled = await androidPlugin.areNotificationsEnabled();
        if (enabled != null) systemPermissionGranted = enabled;
      }
    } catch (e) {
      debugPrint('[OrderNotificationService] permission check error: $e');
    }

    // Supprimer les anciens canaux v2/v3/v4 pour adopter proprement la nouvelle sonnerie Cha-Ching v5
    for (final oldId in const [
      'xfy_new_orders_sound_v2',
      'xfy_new_orders_silent_v2',
      'xfy_new_orders_money_v3',
      'xfy_new_orders_silent_v3',
      'xfy_orders_shopify_chaching_v4',
    ]) {
      try {
        await androidPlugin.deleteNotificationChannel(oldId);
      } catch (_) {}
    }

    // Créer les 4 canaux dédiés (1 par sonnerie)
    for (final r in ringtones) {
      try {
        await androidPlugin.createNotificationChannel(
          AndroidNotificationChannel(
            r.androidChannelId,
            r.androidChannelName,
            description: _channelSoundDesc,
            importance: Importance.max,
            playSound: true,
            sound: RawResourceAndroidNotificationSound(r.rawResource),
            enableVibration: true,
          ),
        );
      } catch (e) {
        debugPrint('[OrderNotificationService] channel ${r.id} fallback: $e');
        try {
          await androidPlugin.createNotificationChannel(
            AndroidNotificationChannel(
              r.androidChannelId,
              r.androidChannelName,
              description: _channelSoundDesc,
              importance: Importance.max,
              playSound: true,
              enableVibration: true,
            ),
          );
        } catch (_) {}
      }
    }

    // Canal silencieux (quand l'utilisateur désactive la sonnerie)
    try {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelSilentId,
          _channelSilentName,
          description: _channelSilentDesc,
          importance: Importance.max,
          playSound: false,
          enableVibration: true,
        ),
      );
    } catch (_) {}
  }

  Future<bool> refreshPermissionStatus() async {
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    try {
      final enabled = await androidPlugin.areNotificationsEnabled();
      if (enabled != null) {
        systemPermissionGranted = enabled;
      }
    } catch (_) {}
    return systemPermissionGranted;
  }

  Future<bool> requestPermission() async {
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosPlugin != null) {
      try {
        final granted = await iosPlugin.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
        if (granted != null) {
          systemPermissionGranted = granted;
        }
      } catch (_) {}
      return systemPermissionGranted;
    }

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return true;
    try {
      final granted = await androidPlugin.requestNotificationsPermission();
      if (granted != null) {
        systemPermissionGranted = granted;
      } else {
        await refreshPermissionStatus();
      }
    } catch (_) {}
    return systemPermissionGranted;
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    notificationsEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefNotifEnabled, enabled);
  }

  Future<void> setSoundEnabled(bool enabled) async {
    soundEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefSoundEnabled, enabled);
  }

  Future<void> setSelectedRingtone(String ringtoneId) async {
    final resolved = resolveRingtone(ringtoneId);
    selectedRingtoneId = resolved.id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefSoundKey, resolved.id);
  }

  Future<void> setBackgroundMonitorEnabled(bool enabled) async {
    backgroundMonitorEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBgMonitorEnabled, enabled);
  }

  Future<void> playRingtone({String? overrideRingtoneId, bool force = false}) async {
    if (!force && !soundEnabled) return;
    final option = overrideRingtoneId != null
        ? resolveRingtone(overrideRingtoneId)
        : currentRingtone;
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/${option.fileName}'));
    } catch (e) {
      debugPrint('[OrderNotificationService] Audio error: $e');
    }
  }

  /// Formate le titre de notification SANS #ID : uniquement « Nouvelle commande • PRIX ».
  static String formatOrderAlertTitle(double total) {
    final prefix = AppL10n.t('notif_new_order');
    if (total > 0) {
      return '$prefix • ${XfyFormatters.formatTnd(total)}';
    }
    return prefix;
  }

  Future<void> notifyNewOrder(OrderModel order) async {
    if (!notificationsEnabled) return;

    HapticFeedback.heavyImpact();
    await playRingtone();

    final title = formatOrderAlertTitle(order.effectiveTotal);
    final productPart =
        (order.produit ?? '').trim().isNotEmpty ? ' • ${order.produit!.trim()}' : '';
    final locPart =
        (order.gouvernorat ?? order.ville ?? '').trim().isNotEmpty
            ? ' (${(order.gouvernorat ?? order.ville)!.trim()})'
            : '';
    final body = '${order.nom}$productPart$locPart';

    await _showSystemNotification(
      id: order.id > 0 ? order.id % 100000 : DateTime.now().millisecond,
      title: title,
      body: body,
    );
  }

  Future<void> sendTestNotification() async {
    HapticFeedback.heavyImpact();
    await playRingtone();
    await _showSystemNotification(
      id: 99901,
      title: formatOrderAlertTitle(129),
      body: AppL10n.t('notif_test_body'),
    );
  }

  Future<void> _showSystemNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    final ringtone = currentRingtone;
    final channelId =
        soundEnabled ? ringtone.androidChannelId : _channelSilentId;
    final channelName =
        soundEnabled ? ringtone.androidChannelName : _channelSilentName;
    final channelDesc = soundEnabled ? _channelSoundDesc : _channelSilentDesc;

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
      sound: soundEnabled ? ringtone.fileName : null,
    );

    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDesc,
      importance: Importance.max,
      priority: Priority.max,
      visibility: NotificationVisibility.public,
      playSound: soundEnabled,
      sound: soundEnabled
          ? RawResourceAndroidNotificationSound(ringtone.rawResource)
          : null,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
      color: const Color(0xFF4F46E5),
    );

    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(android: androidDetails, iOS: iosDetails),
      );
    } catch (e) {
      debugPrint('[OrderNotificationService] show custom sound error: $e');
      try {
        final fallbackAndroid = AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDesc,
          importance: Importance.max,
          priority: Priority.max,
          visibility: NotificationVisibility.public,
          playSound: soundEnabled,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF4F46E5),
        );
        await _plugin.show(
          id,
          title,
          body,
          NotificationDetails(android: fallbackAndroid, iOS: iosDetails),
        );
      } catch (e2) {
        debugPrint('[OrderNotificationService] fallback show error: $e2');
      }
    }
  }
}
