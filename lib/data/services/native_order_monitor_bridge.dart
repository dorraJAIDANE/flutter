import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Passerelle Flutter <-> Service natif Android `OrderMonitorService`
/// pour recevoir les alertes sonores de commandes même quand l'app est en arrière-plan
/// ou l'écran verrouillé.
class NativeOrderMonitorBridge {
  NativeOrderMonitorBridge._();
  static final NativeOrderMonitorBridge instance = NativeOrderMonitorBridge._();

  static const _channel = MethodChannel('tn.xfy.xfy_mobile/order_monitor');

  bool get _isAndroid => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isMobileNative =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void setOnOpenOrdersTab(VoidCallback callback) {
    if (!_isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openOrdersTab') {
        callback();
      }
    });
  }

  Future<bool> consumeOpenOrdersIntent() async {
    if (!_isAndroid) return false;
    try {
      final res = await _channel.invokeMethod<bool>('consumeOpenOrdersIntent');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startMonitor({
    required int storeId,
    required String storeName,
    required String token,
    required int lastSeenOrderId,
    required bool notificationsEnabled,
    required bool soundEnabled,
    String language = 'fr',
  }) async {
    if (!_isAndroid) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('startMonitor', {
        'storeId': storeId,
        'storeName': storeName,
        'token': token,
        'lastSeenOrderId': lastSeenOrderId,
        'notificationsEnabled': notificationsEnabled,
        'soundEnabled': soundEnabled,
        'language': language,
      });
      return ok == true;
    } catch (e) {
      debugPrint('[NativeOrderMonitorBridge] startMonitor error: $e');
      return false;
    }
  }

  Future<void> stopMonitor() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('stopMonitor');
    } catch (_) {
      // ignore
    }
  }

  Future<void> syncLastSeenOrderId(int orderId) async {
    if (!_isAndroid || orderId <= 0) return;
    try {
      await _channel.invokeMethod('syncLastSeenOrderId', {'orderId': orderId});
    } catch (_) {
      // ignore
    }
  }

  Future<void> setAppForeground(bool foreground) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setAppForeground', {'foreground': foreground});
    } catch (_) {
      // ignore
    }
  }

  Future<void> updatePreferences({
    required bool notificationsEnabled,
    required bool soundEnabled,
    String? language,
  }) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('updatePreferences', {
        'notificationsEnabled': notificationsEnabled,
        'soundEnabled': soundEnabled,
        'language': ?language,
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> setLanguage(String language) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('setLanguage', {'language': language});
    } catch (_) {
      // ignore
    }
  }

  Future<bool> isRunning() async {
    if (!_isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('isRunning')) == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!_isAndroid) return true;
    try {
      return (await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations')) ==
          true;
    } catch (_) {
      return true;
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {
      // ignore
    }
  }

  Future<void> openNotificationSettings() async {
    if (!_isMobileNative) return;
    try {
      await _channel.invokeMethod('openNotificationSettings');
    } catch (_) {
      // ignore
    }
  }

  Future<void> openAppSettings() async {
    if (!_isMobileNative) return;
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (_) {
      // ignore
    }
  }

  /// Lance le scanner QR natif (Android `QrScannerActivity` CameraX+MLKit ou iOS `AVFoundation`).
  /// Retourne `{'code': '...'}` si un QR/code-barres est scanné, `{'manual': true}` si saisie manuelle,
  /// ou `null` si l'utilisateur ferme le scanner.
  Future<Map<String, dynamic>?> openNativeQrScanner() async {
    if (!_isMobileNative) return null;
    try {
      final res = await _channel.invokeMethod<dynamic>('openNativeQrScanner');
      if (res is Map) {
        return Map<String, dynamic>.from(res);
      }
      return null;
    } catch (e) {
      debugPrint('[NativeOrderMonitorBridge] openNativeQrScanner error: $e');
      return null;
    }
  }
}
