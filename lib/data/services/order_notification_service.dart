import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/l10n/app_l10n.dart';
import '../../core/utils/formatters.dart';
import '../models/order_model.dart';

/// Gère les notifications Android/iOS haute priorité + la sonnerie Money (`money_chime.wav`)
/// lors de la réception d'une nouvelle commande (sans #ID : uniquement titre + prix).
class OrderNotificationService {
  OrderNotificationService._();
  static final OrderNotificationService instance = OrderNotificationService._();

  // v3 : nouveau canal dédié à la sonnerie Money (`res/raw/money_chime.wav`),
  // aligné avec `OrderMonitorService.kt` et protégé par `res/raw/keep.xml`.
  static const _channelSoundId = 'xfy_new_orders_money_v3';
  static const _channelSoundName = 'Nouvelles commandes XFY (Money)';
  static const _channelSoundDesc =
      'Alertes sonores Money instantanées à chaque nouvelle commande reçue';

  static const _channelSilentId = 'xfy_new_orders_silent_v3';
  static const _channelSilentName = 'Nouvelles commandes XFY (Silencieux)';
  static const _channelSilentDesc = 'Alertes visuelles sans sonnerie';

  static const _prefNotifEnabled = 'xfy_notif_enabled';
  static const _prefSoundEnabled = 'xfy_notif_sound_enabled';
  static const _prefBgMonitorEnabled = 'xfy_bg_monitor_enabled';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _initialized = false;
  bool notificationsEnabled = true;
  bool soundEnabled = true;
  bool backgroundMonitorEnabled = true;
  bool systemPermissionGranted = true;

  VoidCallback? onNotificationTapped;

  Future<void> init({VoidCallback? onTap}) async {
    onNotificationTapped = onTap;
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    notificationsEnabled = prefs.getBool(_prefNotifEnabled) ?? true;
    soundEnabled = prefs.getBool(_prefSoundEnabled) ?? true;
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

    // Supprimer les anciens canaux v2 pour forcer Android à adopter la sonnerie Money v3
    try {
      await androidPlugin.deleteNotificationChannel('xfy_new_orders_sound_v2');
      await androidPlugin.deleteNotificationChannel('xfy_new_orders_silent_v2');
    } catch (_) {}

    // Canal avec sonnerie Money personnalisée (`res/raw/money_chime.wav`)
    try {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelSoundId,
          _channelSoundName,
          description: _channelSoundDesc,
          importance: Importance.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('money_chime'),
          enableVibration: true,
        ),
      );
    } catch (e) {
      debugPrint('[OrderNotificationService] sound channel fallback: $e');
      try {
        await androidPlugin.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelSoundId,
            _channelSoundName,
            description: _channelSoundDesc,
            importance: Importance.max,
            playSound: true,
            enableVibration: true,
          ),
        );
      } catch (_) {}
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

  Future<void> setBackgroundMonitorEnabled(bool enabled) async {
    backgroundMonitorEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBgMonitorEnabled, enabled);
  }

  Future<void> playRingtone() async {
    if (!soundEnabled) return;
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/money_chime.wav'));
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
    final channelId = soundEnabled ? _channelSoundId : _channelSilentId;
    final channelName = soundEnabled ? _channelSoundName : _channelSilentName;
    final channelDesc = soundEnabled ? _channelSoundDesc : _channelSilentDesc;

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: soundEnabled,
      sound: soundEnabled ? 'money_chime.wav' : null,
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
          ? const RawResourceAndroidNotificationSound('money_chime')
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
      // Fallback garanti avec le son système Android pour ne JAMAIS rater l'affichage !
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
