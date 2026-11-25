import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:stomp_dart_client/stomp_dart_client.dart';
import '../../core/constants/api_constants.dart';
import '../models/order_model.dart';
import 'xfy_api_service.dart';

/// Surveille l'arrivée de nouvelles commandes en temps réel quand l'app est active :
/// 1. Connexion WebSocket STOMP (SockJS `https://xfy.tn/ws`) sur :
///    - `/topic/commandes/{storeId}` (commandes site web, paiements, chatbot)
///    - `/topic/orders` filtré par `storeId` (commandes ajoutées depuis le panel)
/// 2. Polling de secours toutes les 10s via `/api/commande/recent/{storeId}`
///    + vérification immédiate au retour au premier plan (`checkNow()`).
class RealtimeOrderWatcher {
  RealtimeOrderWatcher({
    required this.api,
    required this.onNewOrder,
    this.onStatusChanged,
  });

  final XfyApiService api;
  final void Function(OrderModel order) onNewOrder;
  final VoidCallback? onStatusChanged;

  StompClient? _stompClient;
  Timer? _pollTimer;
  int? _storeId;
  String? _token;
  int _highestSeenOrderId = 0;
  bool _isSeeded = false;
  bool _stompConnected = false;
  bool _isChecking = false;
  DateTime? _lastPollSuccess;

  final Set<int> _notifiedIds = <int>{};

  void _setStompConnected(bool value) {
    if (_stompConnected == value) return;
    _stompConnected = value;
    onStatusChanged?.call();
  }

  bool get isStompConnected => _stompConnected;
  DateTime? get lastPollSuccess => _lastPollSuccess;
  int get highestSeenOrderId => _highestSeenOrderId;

  void seedKnownOrders(List<OrderModel> existing) {
    for (final o in existing) {
      if (o.id > _highestSeenOrderId) {
        _highestSeenOrderId = o.id;
      }
      _notifiedIds.add(o.id);
    }
    _isSeeded = true;
  }

  /// Démarre ou maintient la surveillance pour `storeId`.
  /// Ne réinitialise PAS `_notifiedIds` si c'est déjà le même `storeId` actif,
  /// afin de ne jamais avaler silencieusement une nouvelle commande lors d'un refresh.
  void start({
    required int storeId,
    required String? token,
    required List<OrderModel> existingOrders,
  }) {
    final isSameStore = _storeId == storeId && _isSeeded;
    if (!isSameStore) {
      stop();
      _storeId = storeId;
      _token = token;
      _notifiedIds.clear();
      _highestSeenOrderId = 0;
      seedKnownOrders(existingOrders);
    } else {
      _token = token;
      seedKnownOrders(existingOrders);
    }

    if (token != null && token.isNotEmpty && !_stompConnected && _stompClient == null) {
      _connectStomp(storeId, token);
    }

    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) {
        // Quand STOMP WebSocket est connecté, on vérifie en secours seulement toutes les 45s
        if (_stompConnected &&
            _lastPollSuccess != null &&
            DateTime.now().difference(_lastPollSuccess!).inSeconds < 45) {
          return;
        }
        checkNow();
      },
    );
  }

  /// Force une vérification immédiate (appelée lors du retour au premier plan).
  Future<void> checkNow() async {
    final storeId = _storeId;
    if (storeId == null || _isChecking) return;
    _isChecking = true;

    // Reconnecter STOMP s'il a été coupé pendant la veille
    if (!_stompConnected && _stompClient == null && _token != null && _token!.isNotEmpty) {
      _connectStomp(storeId, _token!);
    }

    try {
      final recent = await api.getRecentOrders(storeId);
      _lastPollSuccess = DateTime.now();
      if (recent.isEmpty) return;

      final sorted = List<OrderModel>.from(recent)
        ..sort((a, b) => a.id.compareTo(b.id));
      for (final order in sorted) {
        if (order.id > _highestSeenOrderId && !_notifiedIds.contains(order.id)) {
          _handleIncomingOrder(order);
        }
      }
    } catch (e) {
      debugPrint('[RealtimeOrderWatcher] poll error: $e');
    } finally {
      _isChecking = false;
    }
  }

  void _connectStomp(int storeId, String token) {
    try {
      _stompClient = StompClient(
        config: StompConfig.sockJS(
          url: '${ApiConstants.hostUrl}/ws',
          stompConnectHeaders: {'Authorization': 'Bearer $token'},
          webSocketConnectHeaders: {'Authorization': 'Bearer $token'},
          heartbeatIncoming: const Duration(seconds: 10),
          heartbeatOutgoing: const Duration(seconds: 10),
          reconnectDelay: const Duration(seconds: 4),
          onConnect: (frame) {
            _setStompConnected(true);
            debugPrint('[RealtimeOrderWatcher] STOMP connecté (store $storeId)');

            // 1. Topic principal des commandes boutique (site web, paiement, chatbot)
            _stompClient?.subscribe(
              destination: '/topic/commandes/$storeId',
              callback: (StompFrame msg) => _parseAndDispatch(msg.body, filterStoreId: null),
            );

            // 2. Topic global `/topic/orders` (commandes créées depuis le dashboard)
            _stompClient?.subscribe(
              destination: '/topic/orders',
              callback: (StompFrame msg) => _parseAndDispatch(msg.body, filterStoreId: storeId),
            );
          },
          onDisconnect: (_) {
            _setStompConnected(false);
          },
          onWebSocketError: (err) {
            _setStompConnected(false);
            debugPrint('[RealtimeOrderWatcher] WS error: $err');
          },
          onStompError: (frame) {
            _setStompConnected(false);
            debugPrint('[RealtimeOrderWatcher] STOMP error: ${frame.body}');
          },
        ),
      );
      _stompClient?.activate();
    } catch (e) {
      _stompConnected = false;
      _stompClient = null;
      debugPrint('[RealtimeOrderWatcher] STOMP init failed: $e');
    }
  }

  void _parseAndDispatch(String? body, {int? filterStoreId}) {
    if (body == null || body.isEmpty) return;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final order = OrderModel.fromJson(decoded);
        if (filterStoreId != null &&
            order.storeId != null &&
            order.storeId != filterStoreId) {
          return;
        }
        // Ignorer les mises à jour d'anciennes commandes déjà connues
        if (order.id <= _highestSeenOrderId || _notifiedIds.contains(order.id)) {
          return;
        }
        _handleIncomingOrder(order);
      }
    } catch (e) {
      debugPrint('[RealtimeOrderWatcher] Parse error: $e');
    }
  }

  void _handleIncomingOrder(OrderModel order) {
    if (order.id <= 0) return;
    if (_notifiedIds.contains(order.id)) return;
    _notifiedIds.add(order.id);
    if (order.id > _highestSeenOrderId) {
      _highestSeenOrderId = order.id;
    }
    onNewOrder(order);
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
    try {
      _stompClient?.deactivate();
    } catch (_) {
      // ignore
    }
    _stompClient = null;
    _stompConnected = false;
    _storeId = null;
    _isSeeded = false;
  }
}
