import 'dart:async';
import 'package:flutter/widgets.dart';
import '../core/l10n/app_l10n.dart';
import '../core/storage/token_storage.dart';
import '../core/utils/formatters.dart';
import '../core/utils/xfy_stats_engine.dart';
import '../data/models/client_model.dart';
import '../data/models/daily_budget_model.dart';
import '../data/models/order_model.dart';
import '../data/models/product_model.dart';
import '../data/models/stats_model.dart';
import '../data/models/store_model.dart';
import '../data/models/store_settings_model.dart';
import '../data/models/user_model.dart';
import '../data/services/native_order_monitor_bridge.dart';
import '../data/services/order_notification_service.dart';
import '../data/services/realtime_order_watcher.dart';
import '../data/services/xfy_api_service.dart';

class AppState extends ChangeNotifier {
  AppState({
    XfyApiService? api,
    TokenStorage? storage,
  })  : api = api ?? XfyApiService(),
        _storage = storage ?? TokenStorage();

  final XfyApiService api;
  final TokenStorage _storage;
  final OrderNotificationService _notifications =
      OrderNotificationService.instance;
  final NativeOrderMonitorBridge _nativeMonitor =
      NativeOrderMonitorBridge.instance;

  late final RealtimeOrderWatcher _orderWatcher = RealtimeOrderWatcher(
    api: api,
    onNewOrder: _onRealtimeNewOrder,
    onStatusChanged: () => notifyListeners(),
  );

  OrderModel? latestIncomingOrder;
  Timer? _incomingBannerTimer;

  bool get notificationsEnabled => _notifications.notificationsEnabled;
  bool get soundEnabled => _notifications.soundEnabled;
  String get selectedRingtoneId => _notifications.selectedRingtoneId;
  OrderRingtoneOption get currentRingtone => _notifications.currentRingtone;
  bool get backgroundMonitorEnabled => _notifications.backgroundMonitorEnabled;
  bool get systemNotificationsAllowed => _notifications.systemPermissionGranted;
  bool get isStompConnected => _orderWatcher.isStompConnected;

  // Index O(1) nom produit normalisé -> URL image produit (pour vignettes dans Commandes)
  Map<String, String> _productImageIndex = const {};
  int _productImageIndexVersion = -1;
  bool _isSyncingCarrierStatuses = false;

  bool isBackgroundMonitorRunning = false;
  bool isIgnoringBatteryOptimizations = true;

  bool isInitializing = true;
  bool isAuthLoading = false;
  String? authError;

  /// Notifier isolé pour `MaterialApp` (ne se déclenche QUE sur init / auth / langue — jamais sur les données ou onglets).
  final ValueNotifier<int> appRootVersion = ValueNotifier<int>(0);

  /// Compteurs de version par domaine pour mémoïsation O(1) dans Dashboard / Commandes / Produits.
  int ordersVersion = 0;
  int productsVersion = 0;
  int settingsVersion = 0;
  int budgetsVersion = 0;
  int languageVersion = 0;

  int _cachedPendingCount = 0;
  DateTime? _lastOrdersFullSync;
  bool _isRefreshingAll = false;

  void _bumpRoot() {
    appRootVersion.value++;
  }

  void _recomputePendingCount() {
    int c = 0;
    for (final o in orders) {
      if (o.unifiedStatus == 'en_cours') c++;
    }
    _cachedPendingCount = c;
  }

  String languageCode = 'fr'; // 'fr' | 'en' | 'ar'
  bool get isRtl => languageCode == 'ar';

  XfyUser? user;
  List<StoreModel> stores = [];
  StoreModel? selectedStore;

  String selectedPeriod = 'day'; // 'day' | 'week' | 'month'
  bool isDashboardLoading = false;
  StatsModel stats = const StatsModel();
  List<OrderModel> recentOrders = [];

  bool isOrdersLoading = false;
  List<OrderModel> orders = [];
  String? ordersError;
  List<String> deliveryCompanies = [];

  bool isProductsLoading = false;
  List<ProductModel> products = [];
  String? productsError;

  List<DailyBudgetModel> dailyBudgets = [];
  String? _loadedBudgetPeriodKey;

  bool isClientsLoading = false;
  List<ClientModel> clients = [];
  String? clientsError;

  bool isSettingsLoading = false;
  StoreSettingsModel? storeSettings;
  String? settingsError;

  // 0 = Commandes, 1 = Produits, 2 = Accueil / Statistiques (Logo XFY au centre), 3 = Clients, 4 = Paramètres
  int currentTabIndex = 2;

  bool get isAuthenticated => user != null;

  void setTab(int index) {
    if (currentTabIndex == index) return;
    currentTabIndex = index;
    notifyListeners();
  }

  Future<void> bootstrap() async {
    isInitializing = true;
    _bumpRoot();

    // 1. Lecture locale ultra-rapide (< 30 ms) : langue, token, utilisateur & boutiques en cache
    final savedLang = await _storage.getLanguage();
    languageCode = AppL10n.normalizeCode(savedLang);
    AppL10n.setLanguage(languageCode);
    languageVersion++;

    final token = await _storage.getToken();
    final cachedUserMap = await _storage.getCachedUser();
    final cachedStoreMaps = await _storage.getCachedStores();
    final savedStoreId = await _storage.getSelectedStoreId();

    // Initialiser notifications & canal natif sans bloquer l'affichage initial
    unawaited(_initNativeHooksAndPermissions());

    if (token != null && token.isNotEmpty) {
      api.setToken(token);

      if (cachedUserMap != null) {
        // Démarrage INSTANTANÉ depuis le cache local (< 150 ms) puis synchronisation en arrière-plan !
        user = XfyUser.fromJson(cachedUserMap);
        _applyStoresList(
          cachedStoreMaps.isNotEmpty
              ? cachedStoreMaps.map(StoreModel.fromJson).toList()
              : user!.stores,
          savedStoreId,
        );
        isInitializing = false;
        _bumpRoot();
        notifyListeners();
        unawaited(_hydrateAuthenticatedSessionInBackground());
        return;
      }

      // Pas de cache utilisateur : valider le token puis entrer immédiatement dans le Shell
      try {
        user = await api.validateToken();
        await _storage.saveCachedUser(user!.toJson());
        _applyStoresList(user!.stores, savedStoreId);
      } catch (_) {
        await logout();
        isInitializing = false;
        _bumpRoot();
        return;
      }
      isInitializing = false;
      _bumpRoot();
      notifyListeners();
      unawaited(_hydrateAuthenticatedSessionInBackground());
      return;
    }

    isInitializing = false;
    _bumpRoot();
    notifyListeners();
  }

  Future<void> _initNativeHooksAndPermissions() async {
    await _nativeMonitor.setLanguage(languageCode);
    await _notifications.init(onTap: () {
      setTab(0); // Ouvre l'onglet Commandes quand on tape la notification
    });
    _nativeMonitor.setOnOpenOrdersTab(() {
      setTab(0);
      refreshOrders();
    });
    await _nativeMonitor.setAppForeground(true);
    if (await _nativeMonitor.consumeOpenOrdersIntent()) {
      setTab(0);
    }
    await _refreshDeviceNotificationStatus();
    notifyListeners();
  }

  void _applyStoresList(List<StoreModel> initialStores, int? savedStoreId) {
    final resolved = <StoreModel>[...initialStores];
    if (user != null) {
      for (final collab in user!.collaborations.where((c) => c.accepted)) {
        if (!resolved.any((s) => s.id == collab.storeId)) {
          resolved.add(StoreModel(id: collab.storeId, name: collab.storeName));
        }
      }
    }
    stores = resolved;
    if (stores.isNotEmpty) {
      selectedStore = stores.firstWhere(
        (s) => s.id == savedStoreId,
        orElse: () => stores.first,
      );
    } else {
      selectedStore = null;
    }
  }

  Future<void> _hydrateAuthenticatedSessionInBackground() async {
    try {
      final freshUser = await api.validateToken();
      user = freshUser;
      await _storage.saveCachedUser(freshUser.toJson());
    } on ApiException catch (e) {
      if (e.statusCode == 401) {
        await logout();
        return;
      }
    } catch (_) {
      // Hors-ligne temporaire : conserver la session en cache
    }
    await _loadStoresAndInitialData(blockUi: false);
  }

  Future<void> _refreshDeviceNotificationStatus() async {
    await _notifications.refreshPermissionStatus();
    isBackgroundMonitorRunning = await _nativeMonitor.isRunning();
    isIgnoringBatteryOptimizations =
        await _nativeMonitor.isIgnoringBatteryOptimizations();
  }

  /// Appelé par `XfyMobileApp` (`WidgetsBindingObserver`) lors des passages avant/arrière-plan.
  Future<void> onAppLifecycleChanged(AppLifecycleState lifecycleState) async {
    if (!isAuthenticated) return;

    if (lifecycleState == AppLifecycleState.resumed) {
      await _nativeMonitor.setAppForeground(true);
      // Vérification légère et instantanée (seulement /recent, sans re-télécharger les milliers de commandes)
      unawaited(_refreshDeviceNotificationStatus());
      unawaited(_orderWatcher.checkNow());
      final shouldFullRefresh = _lastOrdersFullSync == null ||
          DateTime.now().difference(_lastOrdersFullSync!).inMinutes >= 3;
      if (shouldFullRefresh) {
        unawaited(refreshOrders(silent: true));
      }
    } else if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.inactive ||
        lifecycleState == AppLifecycleState.detached) {
      await _nativeMonitor.setAppForeground(false);
      unawaited(_syncBackgroundMonitorService());
    }
  }

  Future<void> setLanguage(String code) async {
    final normalized = AppL10n.normalizeCode(code);
    if (languageCode == normalized) return;
    languageCode = normalized;
    AppL10n.setLanguage(normalized);
    languageVersion++;
    _bumpRoot();
    notifyListeners();

    await _storage.saveLanguage(normalized);
    await _nativeMonitor.setLanguage(normalized);

    // Synchroniser aussi la préférence de langue avec le backend utilisateur si connecté
    final current = user;
    if (current != null && current.id > 0) {
      try {
        final payload = <String, dynamic>{
          'username': current.username,
          if (current.firstName != null) 'firstName': current.firstName,
          'email': current.email,
          if (current.phoneNumber != null &&
              current.phoneNumber!.trim().isNotEmpty)
            'phoneNumber': current.phoneNumber!.trim(),
          'role': current.role,
          'language': normalized,
        };
        final res = await api.updateUser(current.id, payload);
        final newToken = res['token']?.toString();
        final merged = current.copyWith(
          language: normalized,
          token: (newToken != null && newToken.isNotEmpty)
              ? newToken
              : current.token,
        );
        user = merged;
        if (newToken != null && newToken.isNotEmpty) {
          api.setToken(newToken);
          await _storage.saveToken(newToken);
        }
        await _storage.saveCachedUser(merged.toJson());
      } catch (_) {
        // La préférence locale reste appliquée immédiatement même hors-ligne
      }
    }
    unawaited(_syncBackgroundMonitorService());
  }

  Future<String?> getRememberedIdentifier() => _storage.getRememberedIdentifier();

  Future<void> saveRememberedIdentifier(String? identifier) =>
      _storage.saveRememberedIdentifier(identifier);

  Future<String> sendForgotPasswordEmail(String email) =>
      api.forgotPassword(email);

  Future<void> resendSmsCode({
    required String email,
    required String phoneNumber,
  }) =>
      api.sendSmsCode(email: email, phoneNumber: phoneNumber);

  String _translateUserUpdateError(Object e) {
    final msg = e.toString();
    final lower = msg.toLowerCase();
    if (lower.contains('username already exists')) {
      return 'Ce prénom est déjà utilisé par un autre compte.';
    }
    if (lower.contains('email already exists')) {
      return 'Cette adresse email est déjà utilisée.';
    }
    if (lower.contains('phone number already exists')) {
      return 'Ce numéro de téléphone est déjà utilisé.';
    }
    return msg;
  }

  /// Met à jour les informations personnelles via `PUT /api/users/{id}`
  /// (mapping exact Web `profile-settings.component.ts` : Prénom -> `username`, Nom -> `firstName`).
  Future<void> updatePersonalInfo({
    required String firstName,
    required String lastName,
    required String email,
    String? phoneNumber,
  }) async {
    final current = user;
    if (current == null || current.id <= 0) {
      throw ApiException('Session utilisateur introuvable.');
    }

    final cleanPhone = phoneNumber?.trim();
    final payload = <String, dynamic>{
      'username': firstName.trim(),
      'firstName': lastName.trim(),
      'email': email.trim().toLowerCase(),
      if (cleanPhone != null && cleanPhone.isNotEmpty)
        'phoneNumber': cleanPhone
      else if (current.phoneNumber != null &&
          current.phoneNumber!.trim().isNotEmpty)
        'phoneNumber': current.phoneNumber!.trim(),
      'role': current.role,
      'language': current.language,
    };

    try {
      final res = await api.updateUser(current.id, payload);
      final newToken = res['token']?.toString();
      final merged = current.copyWith(
        username: (res['username'] ?? firstName.trim()).toString(),
        firstName: (res['firstName'] ?? lastName.trim()).toString(),
        email: (res['email'] ?? email.trim().toLowerCase()).toString(),
        phoneNumber: (res['phoneNumber'] ?? cleanPhone ?? current.phoneNumber)
            ?.toString(),
        language: (res['language'] ?? current.language).toString(),
        token: (newToken != null && newToken.isNotEmpty)
            ? newToken
            : current.token,
      );
      user = merged;

      if (newToken != null && newToken.isNotEmpty) {
        api.setToken(newToken);
        await _storage.saveToken(newToken);
      }
      await _storage.saveCachedUser(merged.toJson());
      notifyListeners();

      if (newToken != null && newToken.isNotEmpty) {
        await _startOrderWatcher();
      }
    } catch (e) {
      throw ApiException(_translateUserUpdateError(e));
    }
  }

  /// Met à jour le mot de passe via `PUT /api/users/{id}` (exact Web `profile-settings.component.ts`).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final current = user;
    if (current == null || current.id <= 0) {
      throw ApiException('Session utilisateur introuvable.');
    }
    if (currentPassword.trim().isEmpty) {
      throw ApiException('Le mot de passe actuel est requis.');
    }
    if (newPassword.length < 6) {
      throw ApiException(
        'Le nouveau mot de passe doit contenir au moins 6 caractères.',
      );
    }
    if (newPassword == currentPassword) {
      throw ApiException(
        'Le nouveau mot de passe doit être différent du mot de passe actuel.',
      );
    }

    final payload = <String, dynamic>{
      'username': current.username,
      if (current.firstName != null) 'firstName': current.firstName,
      'email': current.email,
      if (current.phoneNumber != null && current.phoneNumber!.trim().isNotEmpty)
        'phoneNumber': current.phoneNumber!.trim(),
      'role': current.role,
      'language': current.language,
      'password': newPassword,
    };

    try {
      final res = await api.updateUser(current.id, payload);
      final newToken = res['token']?.toString();
      if (newToken != null && newToken.isNotEmpty) {
        final merged = current.copyWith(token: newToken);
        user = merged;
        api.setToken(newToken);
        await _storage.saveToken(newToken);
        await _storage.saveCachedUser(merged.toJson());
        await _startOrderWatcher();
      }
      notifyListeners();
    } catch (e) {
      throw ApiException(_translateUserUpdateError(e));
    }
  }

  Future<void> login(String identifier, String password) async {
    isAuthLoading = true;
    authError = null;
    notifyListeners();

    try {
      final res = await api.signin(identifier: identifier, password: password);
      final token = res['token']?.toString();
      if (token == null || token.isEmpty) {
        throw ApiException('Jeton de connexion manquant.');
      }

      api.setToken(token);
      await _storage.saveToken(token);
      await _storage.saveCachedUser(res);
      user = XfyUser.fromJson(res);
      final savedStoreId = await _storage.getSelectedStoreId();
      _applyStoresList(user!.stores, savedStoreId);
      isAuthLoading = false;
      _bumpRoot();
      notifyListeners();

      // Charger toutes les données boutique en arrière-plan pour une ouverture instantanée du dashboard
      unawaited(_loadStoresAndInitialData(blockUi: false));
      return;
    } on SmsVerificationRequiredException {
      isAuthLoading = false;
      notifyListeners();
      rethrow;
    } catch (e) {
      authError = e.toString();
      isAuthLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> verifySmsAndFinishLogin({
    required String email,
    required String code,
  }) async {
    isAuthLoading = true;
    authError = null;
    notifyListeners();

    try {
      final res = await api.verifySms(email: email, code: code);
      final token = res['token']?.toString();
      if (token == null || token.isEmpty) {
        throw ApiException('Code vérifié mais jeton absent. Reconnectez-vous.');
      }
      api.setToken(token);
      await _storage.saveToken(token);
      user = await api.validateToken();
      await _storage.saveCachedUser(user!.toJson());
      final savedStoreId = await _storage.getSelectedStoreId();
      _applyStoresList(user!.stores, savedStoreId);
      isAuthLoading = false;
      _bumpRoot();
      notifyListeners();
      unawaited(_loadStoresAndInitialData(blockUi: false));
      return;
    } catch (e) {
      authError = e.toString();
      isAuthLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _loadStoresAndInitialData({bool blockUi = true}) async {
    final resolved = <StoreModel>[];

    try {
      final apiStores = await api.getUserStores();
      resolved.addAll(apiStores);
      if (apiStores.isNotEmpty) {
        await _storage.saveCachedStores(
          apiStores.map((s) => s.toJson()).toList(),
        );
      }
    } catch (_) {
      if (user != null) {
        resolved.addAll(user!.stores);
      }
    }

    final savedId = await _storage.getSelectedStoreId();
    _applyStoresList(resolved, savedId);

    if (selectedStore != null) {
      await _storage.saveSelectedStoreId(selectedStore!.id);
      notifyListeners();
      if (blockUi) {
        await refreshAllStoreData();
      } else {
        unawaited(refreshAllStoreData());
      }
    } else {
      notifyListeners();
    }
  }

  Future<void> selectStore(StoreModel store) async {
    if (selectedStore?.id == store.id) return;
    _orderWatcher.stop();
    selectedStore = store;
    await _storage.saveSelectedStoreId(store.id);
    orders = [];
    recentOrders = [];
    _cachedPendingCount = 0;
    ordersVersion++;
    products = [];
    productsVersion++;
    dailyBudgets = [];
    budgetsVersion++;
    _loadedBudgetPeriodKey = null;
    clients = [];
    storeSettings = null;
    settingsVersion++;
    stats = const StatsModel();
    _lastOrdersFullSync = null;
    notifyListeners();
    await refreshAllStoreData();
  }

  Future<void> refreshAllStoreData() async {
    final storeId = selectedStore?.id;
    if (storeId == null || _isRefreshingAll) return;
    _isRefreshingAll = true;
    final defaultBounds = XfyStatsEngine.resolveBounds(preset: '30days');

    try {
      // Chargement groupé sans appels morts (/clients supprimé) et sans cascade de 14 notifyListeners()
      await Future.wait([
        refreshOrders(silent: true),
        refreshProducts(silent: true),
        refreshSettings(silent: true),
        _loadDeliveryCompanies(silent: true),
        loadDailyBudgetsForBounds(defaultBounds, force: true, silent: true),
      ]);
      notifyListeners();
      await _startOrderWatcher();
    } finally {
      _isRefreshingAll = false;
    }
  }

  Future<void> loadDailyBudgetsForBounds(
    PeriodBounds bounds, {
    bool force = false,
    bool silent = false,
  }) async {
    final storeId = selectedStore?.id;
    if (storeId == null) return;

    final startYmd = bounds.isAllTime ? '2023-01-01' : bounds.prevStartYmd;
    final endYmd = bounds.endYmd;
    final key = '${storeId}_${startYmd}_$endYmd';
    if (!force && _loadedBudgetPeriodKey == key) return;

    try {
      dailyBudgets = await api.getDailyBudgetsRange(storeId, startYmd, endYmd);
      _loadedBudgetPeriodKey = key;
      budgetsVersion++;
      if (!silent) notifyListeners();
    } catch (_) {
      // Non bloquant : certains comptes n'ont pas de budgets journaliers configurés
    }
  }

  Future<void> _startOrderWatcher() async {
    final storeId = selectedStore?.id;
    if (storeId == null) return;
    _orderWatcher.start(
      storeId: storeId,
      token: api.currentToken,
      existingOrders: [...orders, ...recentOrders],
    );
    await _syncBackgroundMonitorService();
  }

  Future<void> _syncBackgroundMonitorService() async {
    final store = selectedStore;
    final token = api.currentToken;
    if (store == null ||
        token == null ||
        token.isEmpty ||
        !notificationsEnabled ||
        !backgroundMonitorEnabled) {
      await _nativeMonitor.stopMonitor();
      isBackgroundMonitorRunning = false;
      notifyListeners();
      return;
    }

    int maxId = _orderWatcher.highestSeenOrderId;
    for (final o in orders) {
      if (o.id > maxId) maxId = o.id;
    }
    for (final o in recentOrders) {
      if (o.id > maxId) maxId = o.id;
    }

    isBackgroundMonitorRunning = await _nativeMonitor.startMonitor(
      storeId: store.id,
      storeName: store.name,
      token: token,
      lastSeenOrderId: maxId,
      notificationsEnabled: notificationsEnabled,
      soundEnabled: soundEnabled,
      soundKey: selectedRingtoneId,
      language: languageCode,
    );
    notifyListeners();
  }

  void _onRealtimeNewOrder(OrderModel incoming) {
    // Synchroniser immédiatement l'ID avec le service natif pour éviter tout doublon
    _nativeMonitor.syncLastSeenOrderId(incoming.id);

    if (!orders.any((o) => o.id == incoming.id)) {
      orders = [incoming, ...orders];
      _recomputePendingCount();
      ordersVersion++;
    }
    if (!recentOrders.any((o) => o.id == incoming.id)) {
      recentOrders = [incoming, ...recentOrders.take(14)];
    }

    latestIncomingOrder = incoming;
    _incomingBannerTimer?.cancel();
    _incomingBannerTimer = Timer(const Duration(seconds: 6), () {
      latestIncomingOrder = null;
      notifyListeners();
    });

    notifyListeners();
    _notifications.notifyNewOrder(incoming);
  }

  void dismissIncomingBanner() {
    _incomingBannerTimer?.cancel();
    latestIncomingOrder = null;
    notifyListeners();
  }

  Future<void> setNotificationsEnabled(bool value) async {
    await _notifications.setNotificationsEnabled(value);
    if (value) {
      await _notifications.requestPermission();
    }
    await _nativeMonitor.updatePreferences(
      notificationsEnabled: value,
      soundEnabled: soundEnabled,
      soundKey: selectedRingtoneId,
    );
    await _syncBackgroundMonitorService();
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool value) async {
    await _notifications.setSoundEnabled(value);
    await _nativeMonitor.updatePreferences(
      notificationsEnabled: notificationsEnabled,
      soundEnabled: value,
      soundKey: selectedRingtoneId,
    );
    notifyListeners();
  }

  Future<void> setSelectedRingtone(String ringtoneId) async {
    await _notifications.setSelectedRingtone(ringtoneId);
    await _nativeMonitor.setSoundKey(selectedRingtoneId);
    await _nativeMonitor.updatePreferences(
      notificationsEnabled: notificationsEnabled,
      soundEnabled: soundEnabled,
      soundKey: selectedRingtoneId,
    );
    notifyListeners();
    unawaited(_notifications.playRingtone(overrideRingtoneId: selectedRingtoneId, force: true));
  }

  Future<void> previewRingtone(String ringtoneId) async {
    await _notifications.playRingtone(overrideRingtoneId: ringtoneId, force: true);
  }

  Future<void> setBackgroundMonitorEnabled(bool value) async {
    await _notifications.setBackgroundMonitorEnabled(value);
    await _syncBackgroundMonitorService();
    notifyListeners();
  }

  Future<bool> requestNotificationPermission() async {
    final granted = await _notifications.requestPermission();
    if (!granted) {
      await _nativeMonitor.openNotificationSettings();
    }
    await _refreshDeviceNotificationStatus();
    notifyListeners();
    return granted;
  }

  Future<void> requestBatteryOptimizationExemption() async {
    await _nativeMonitor.requestIgnoreBatteryOptimizations();
    await _refreshDeviceNotificationStatus();
    notifyListeners();
  }

  Future<void> testOrderNotification() async {
    await _notifications.requestPermission();
    await _notifications.sendTestNotification();
    await _refreshDeviceNotificationStatus();
    notifyListeners();
  }

  Future<void> refreshSettings({bool silent = false}) async {
    final storeId = selectedStore?.id;
    if (storeId == null) return;

    isSettingsLoading = true;
    settingsError = null;
    if (!silent) notifyListeners();
    try {
      storeSettings = await api.getStoreSettings(storeId);
      settingsVersion++;
      if (!silent && user != null && user!.id > 0) {
        try {
          final freshUser = await api.getUserById(user!.id);
          user = user!.copyWith(
            username: (freshUser['username'] ?? user!.username).toString(),
            firstName: freshUser['firstName']?.toString() ?? user!.firstName,
            email: (freshUser['email'] ?? user!.email).toString(),
            phoneNumber:
                freshUser['phoneNumber']?.toString() ?? user!.phoneNumber,
            language: (freshUser['language'] ?? user!.language).toString(),
          );
          await _storage.saveCachedUser(user!.toJson());
        } catch (_) {
          // Non bloquant
        }
      }
      await _refreshDeviceNotificationStatus();
    } catch (e) {
      settingsError = e.toString();
    } finally {
      isSettingsLoading = false;
      if (!silent) notifyListeners();
    }
  }

  Future<StoreSettingsModel> saveStoreSettings(StoreSettingsModel updated) async {
    final storeId = selectedStore?.id;
    if (storeId == null) {
      throw ApiException('Aucune boutique sélectionnée.');
    }
    final saved = await api.updateStoreSettings(storeId, updated);
    storeSettings = saved;
    settingsVersion++;
    notifyListeners();
    return saved;
  }

  Future<void> toggleStockZeroBehavior(bool value) async {
    final storeId = selectedStore?.id;
    if (storeId == null) return;
    await api.updateStockZeroBehavior(storeId, value);
    if (storeSettings != null) {
      storeSettings = storeSettings!.copyWith(afficherRuptureStockZero: value);
      settingsVersion++;
      notifyListeners();
    }
  }

  Future<void> _loadDeliveryCompanies({bool silent = false}) async {
    final storeId = selectedStore?.id;
    if (storeId == null) return;
    deliveryCompanies = await api.getDeliveryCompanies(storeId);
    if (!silent) notifyListeners();
  }

  Future<void> setPeriod(String period) async {
    if (selectedPeriod == period) return;
    selectedPeriod = period;
    notifyListeners();
    await refreshDashboard();
  }

  Future<void> refreshDashboard() async {
    final storeId = selectedStore?.id;
    if (storeId == null) return;
    if (orders.isNotEmpty) {
      recentOrders = orders.take(10).toList();
      return;
    }
    isDashboardLoading = true;
    notifyListeners();
    try {
      recentOrders = await api
          .getRecentOrders(storeId)
          .catchError((_) => <OrderModel>[]);
    } finally {
      isDashboardLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshOrders({bool silent = false}) async {
    final storeId = selectedStore?.id;
    if (storeId == null) return;

    isOrdersLoading = true;
    ordersError = null;
    if (!silent && orders.isEmpty) notifyListeners();
    try {
      orders = await api.getOrdersByStore(storeId);
      recentOrders = orders.take(10).toList();
      _recomputePendingCount();
      ordersVersion++;
      _lastOrdersFullSync = DateTime.now();
      unawaited(syncActiveCarrierStatusesInBackground());
    } catch (e) {
      ordersError = e.toString();
    } finally {
      isOrdersLoading = false;
      if (!silent) notifyListeners();
    }
  }

  Future<OrderModel> updateOrderStatus(
    OrderModel order,
    String newStatus, {
    String? newComment,
  }) async {
    final updated = await api.updateOrder(
      order,
      newStatus: newStatus,
      newComment: newComment,
    );
    _replaceOrderInLists(updated);
    notifyListeners();
    refreshDashboard();
    return updated;
  }

  Future<OrderModel> createQuickOrder({
    required String clientName,
    required String phone,
    required String productName,
    required int quantity,
    required double totalPrice,
    required String gouvernorat,
    required String ville,
    String? adresse,
    String? commentaire,
  }) async {
    final storeId = selectedStore?.id;
    if (storeId == null) {
      throw ApiException('Aucune boutique sélectionnée.');
    }

    final now = DateTime.now();
    String pad2(int n) => n.toString().padLeft(2, '0');
    String pad3(int n) => n.toString().padLeft(3, '0');
    final localIso =
        '${now.year}-${pad2(now.month)}-${pad2(now.day)}T${pad2(now.hour)}:${pad2(now.minute)}:${pad2(now.second)}.${pad3(now.millisecond)}';

    final payload = <String, dynamic>{
      'nom': clientName.trim(),
      'phoneNumber': phone.trim(),
      'produit': productName.trim(),
      'quantite': quantity.toString(),
      'prix': totalPrice.toStringAsFixed(2),
      'total': totalPrice,
      'gouvernorat': gouvernorat.trim(),
      'ville': ville.trim(),
      'adresse': (adresse ?? '').trim(),
      'commentaire': (commentaire ?? '').trim(),
      'status': 'en_cours',
      'envoyerAIntigo': 'false',
      'color': '#FFFFFF',
      'timestamp': localIso,
      'dayMonth': XfyFormatters.currentDayMonth(now),
      'monthYear': XfyFormatters.currentFrenchMonthYear(now),
    };

    final created = await api.addOrder(storeId, payload);
    _orderWatcher.seedKnownOrders([created]);
    await _nativeMonitor.syncLastSeenOrderId(created.id);
    orders = [created, ...orders];
    recentOrders = [created, ...recentOrders.take(9)];
    _recomputePendingCount();
    ordersVersion++;
    notifyListeners();
    return created;
  }

  Future<void> deleteOrder(OrderModel order) async {
    await api.deleteOrder(order.id);
    orders.removeWhere((o) => o.id == order.id);
    recentOrders.removeWhere((o) => o.id == order.id);
    _recomputePendingCount();
    ordersVersion++;
    notifyListeners();
  }

  Future<String> sendOrderToCarrier(OrderModel order, String carrier) async {
    final res = await saveAndSendOrderToCarrier(order, carrier);
    return res.message;
  }

  /// Enregistre les champs modifiés d'une commande (`PUT /commande/orders/{id}`).
  Future<OrderModel> updateOrderDetails(OrderModel updatedOrder) async {
    final saved = await api.updateOrderFields(updatedOrder);
    _replaceOrderInLists(saved);
    notifyListeners();
    return saved;
  }

  /// Enregistre d'abord les champs complétés puis envoie la commande à la société de livraison choisie.
  Future<({OrderModel order, String message})> saveAndSendOrderToCarrier(
    OrderModel editedOrder,
    String carrier,
  ) async {
    // 1. Sauvegarder les champs complétés en base avant l'expédition (comme Web)
    final savedOrder = await api.updateOrderFields(editedOrder);
    _replaceOrderInLists(savedOrder);

    // 2. Envoyer à la société de livraison
    final res = await api.sendOrderToCarrier(
      orderId: savedOrder.id,
      carrier: carrier,
    );
    if (res['success'] == false) {
      throw ApiException(
        (res['error'] ?? res['message'] ?? 'Échec envoi transporteur')
            .toString(),
      );
    }
    final tracking = (res['tracking'] ??
            res['barCode'] ??
            res['nid'] ??
            res['code'] ??
            '')
        .toString()
        .trim();
    final carrierStatus = (res['status'] ??
            res['status_message'] ??
            'En attente')
        .toString()
        .trim();

    final updated = savedOrder.copyWith(
      status: 'confirmee',
      numeroBordereau:
          tracking.isNotEmpty ? tracking : savedOrder.numeroBordereau,
      statutIntigo:
          carrierStatus.isNotEmpty ? carrierStatus : savedOrder.statutIntigo,
      deliveryCompany: carrier,
      envoyerAIntigo: 'true',
    );
    _replaceOrderInLists(updated);
    notifyListeners();
    refreshDashboard();

    final label = OrderModel.formatCarrierLabel(carrier);
    final msg = tracking.isNotEmpty
        ? 'Colis envoyé à $label ($tracking)'
        : 'Colis envoyé à $label';
    return (order: updated, message: msg);
  }

  /// Actualise en direct le statut de livraison auprès de la société de livraison.
  Future<OrderModel> refreshOrderCarrierStatus(OrderModel order) async {
    if (!order.hasBordereau) return order;
    final res = await api.fetchCarrierParcelStatus(order);
    final changed = (res.carrierStatus != null &&
            res.carrierStatus != order.statutIntigo) ||
        (res.orderStatus != null && res.orderStatus != order.status) ||
        (res.deliveryCompany != null &&
            res.deliveryCompany != order.deliveryCompany);
    if (!changed) return order;

    final updated = order.copyWith(
      statutIntigo: res.carrierStatus ?? order.statutIntigo,
      status: res.orderStatus ?? order.status,
      deliveryCompany: res.deliveryCompany ?? order.deliveryCompany,
    );
    _replaceOrderInLists(updated);
    notifyListeners();
    return updated;
  }

  /// Rafraîchissement léger et non-bloquant des statuts de livraison des commandes récentes en transit.
  Future<void> syncActiveCarrierStatusesInBackground() async {
    if (_isSyncingCarrierStatuses) return;
    _isSyncingCarrierStatuses = true;
    try {
      const finalTokens = [
        'colis livré',
        'livré',
        'colis livre',
        'livre',
        'annulé',
        'annulée',
        'annule',
        'annulee',
        'retourné',
        'retourne',
        'delivered',
        'canceled',
        'returned',
      ];
      final candidates = <OrderModel>[];
      for (final o in orders) {
        if (!o.hasBordereau) continue;
        final cur = (o.statutIntigo ?? '').toLowerCase().trim();
        if (cur.isNotEmpty && finalTokens.any((f) => cur == f)) continue;
        candidates.add(o);
        if (candidates.length >= 15) break;
      }
      if (candidates.isEmpty) return;

      bool anyUpdated = false;
      for (int i = 0; i < candidates.length; i += 3) {
        final chunk = candidates.skip(i).take(3).toList();
        await Future.wait(chunk.map((o) async {
          try {
            final res = await api.fetchCarrierParcelStatus(o);
            final changed = (res.carrierStatus != null &&
                    res.carrierStatus != o.statutIntigo) ||
                (res.orderStatus != null && res.orderStatus != o.status) ||
                (res.deliveryCompany != null &&
                    res.deliveryCompany != o.deliveryCompany);
            if (changed) {
              final updated = o.copyWith(
                statutIntigo: res.carrierStatus ?? o.statutIntigo,
                status: res.orderStatus ?? o.status,
                deliveryCompany: res.deliveryCompany ?? o.deliveryCompany,
              );
              _replaceOrderInLists(updated);
              anyUpdated = true;
            }
          } catch (_) {}
        }));
      }
      if (anyUpdated) {
        notifyListeners();
      }
    } finally {
      _isSyncingCarrierStatuses = false;
    }
  }

  /// Résout instantanément (O(1)) la photo d'un produit depuis le catalogue chargé.
  String? resolveCatalogProductImage(String? rawProductName) {
    if (rawProductName == null || rawProductName.trim().isEmpty) return null;
    if (_productImageIndexVersion != productsVersion) {
      final map = <String, String>{};
      for (final p in products) {
        final img = p.imageUrl?.trim();
        if (img == null || img.isEmpty || img == 'null') continue;
        final key = XfyFormatters.stripAccents(p.nom.trim());
        map.putIfAbsent(key, () => img);
      }
      _productImageIndex = map;
      _productImageIndexVersion = productsVersion;
    }
    if (_productImageIndex.isEmpty) return null;

    // Nettoyer d'éventuels suffixes de variante/offre ex: "Robe Noir [Offre: ...]" ou "Robe (M)"
    final cleaned = rawProductName
        .split(';')
        .first
        .replaceAll(RegExp(r'\[Offre:[^\]]*\]', caseSensitive: false), '')
        .trim();
    final norm = XfyFormatters.stripAccents(cleaned);
    if (norm.isEmpty) return null;

    final exact = _productImageIndex[norm];
    if (exact != null) return exact;

    for (final entry in _productImageIndex.entries) {
      if (entry.key.length >= 3 &&
          (norm.contains(entry.key) || entry.key.contains(norm))) {
        return entry.value;
      }
    }
    return null;
  }

  /// Crée un nouveau produit sur le backend XFY puis recharge le catalogue.
  Future<void> createProduct({
    required Map<String, dynamic> productData,
    required List<String> imagePaths,
    List<String> variantCombinationImagePaths = const [],
    List<String> variantValueImagePaths = const [],
    List<String?> variantValueImageKeysDebug = const [],
    int? initialSimpleStock,
  }) async {
    final res = await api.createProduct(
      productData: productData,
      imagePaths: imagePaths,
      variantCombinationImagePaths: variantCombinationImagePaths,
      variantValueImagePaths: variantValueImagePaths,
      variantValueImageKeysDebug: variantValueImageKeysDebug,
    );
    // Si produit simple avec stock initial explicite et ID retourné, synchroniser le stock
    if (initialSimpleStock != null && initialSimpleStock >= 0 && res != null) {
      final rawId = res['id'];
      final createdId = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
      if (createdId != null && createdId > 0) {
        try {
          await api.updateProductStock(createdId, initialSimpleStock);
        } catch (_) {}
      }
    }
    await refreshProducts();
  }

  Future<OrderModel> lookupScannedOrder(String code) async {
    final cleaned = code.trim();
    if (cleaned.isEmpty) {
      throw ApiException('Code QR vide.');
    }

    // 1. Chercher d'abord en local par bordereau / ID pour une réponse instantanée si déjà chargé
    final lower = cleaned.toLowerCase();
    for (final o in orders) {
      if ((o.numeroBordereau ?? '').trim().toLowerCase() == lower) {
        return o;
      }
    }

    // 2. Appel officiel XFY `GET /api/commande/getCommandeById/{idOrRef}`
    try {
      final fetched = await api.getOrderByIdOrRef(cleaned);
      _replaceOrInsertOrder(fetched);
      notifyListeners();
      return fetched;
    } catch (e) {
      // 3. Fallback local par ID numérique
      final numericId = int.tryParse(cleaned);
      if (numericId != null) {
        for (final o in orders) {
          if (o.id == numericId) return o;
        }
      }
      rethrow;
    }
  }

  Future<OrderModel> markScannedRetour(OrderModel order) async {
    if (order.hasBordereau) {
      try {
        final updated = await api.createRetourFromBordereau(order.numeroBordereau!);
        _replaceOrInsertOrder(updated);
        notifyListeners();
        refreshDashboard();
        return updated;
      } catch (_) {
        // Fallback vers la mise à jour standard du statut retournee
      }
    }
    return updateOrderStatus(order, 'retournee');
  }

  void _replaceOrInsertOrder(OrderModel updated) {
    final idx = orders.indexWhere((o) => o.id == updated.id);
    if (idx >= 0) {
      orders[idx] = updated;
    } else {
      orders = [updated, ...orders];
    }
    final rIdx = recentOrders.indexWhere((o) => o.id == updated.id);
    if (rIdx >= 0) {
      recentOrders[rIdx] = updated;
    }
    _recomputePendingCount();
    ordersVersion++;
  }

  void _replaceOrderInLists(OrderModel updated) {
    final idx = orders.indexWhere((o) => o.id == updated.id);
    if (idx >= 0) {
      orders[idx] = updated;
    }
    final rIdx = recentOrders.indexWhere((o) => o.id == updated.id);
    if (rIdx >= 0) {
      recentOrders[rIdx] = updated;
    }
    _recomputePendingCount();
    ordersVersion++;
  }

  Future<void> refreshProducts({bool silent = false}) async {
    final storeId = selectedStore?.id;
    if (storeId == null) return;

    isProductsLoading = true;
    productsError = null;
    if (!silent && products.isEmpty) notifyListeners();
    try {
      products = await api.getProductsByStore(storeId);
      productsVersion++;
    } catch (e) {
      productsError = e.toString();
    } finally {
      isProductsLoading = false;
      if (!silent) notifyListeners();
    }
  }

  Future<void> updateSimpleProductStock(
    ProductModel product,
    int newStock,
  ) async {
    await api.updateProductStock(product.id, newStock);
    final idx = products.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      products[idx] = products[idx].copyWith(stock: newStock);
      productsVersion++;
      notifyListeners();
    }
  }

  Future<void> updateVariantProductStock(
    ProductModel product,
    ProductVariantModel variant,
    int newStock,
  ) async {
    await api.updateVariantStock(variant.id, newStock);
    final idx = products.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      final updatedVariants = products[idx]
          .variants
          .map((v) => v.id == variant.id ? v.copyWith(stock: newStock) : v)
          .toList();
      products[idx] = products[idx].copyWith(variants: updatedVariants);
      productsVersion++;
      notifyListeners();
    }
  }

  Future<void> refreshClients() async {
    final storeId = selectedStore?.id;
    if (storeId == null) return;

    isClientsLoading = true;
    clientsError = null;
    notifyListeners();
    try {
      clients = await api.getClientsByStore(storeId);
    } catch (e) {
      clientsError = e.toString();
    } finally {
      isClientsLoading = false;
      notifyListeners();
    }
  }

  int get pendingOrdersCount => _cachedPendingCount;

  Future<void> logout() async {
    _orderWatcher.stop();
    await _nativeMonitor.stopMonitor();
    isBackgroundMonitorRunning = false;
    _incomingBannerTimer?.cancel();
    latestIncomingOrder = null;
    await _storage.clearAll();
    api.setToken(null);
    user = null;
    stores = [];
    selectedStore = null;
    orders = [];
    recentOrders = [];
    _cachedPendingCount = 0;
    ordersVersion++;
    products = [];
    productsVersion++;
    dailyBudgets = [];
    budgetsVersion++;
    _loadedBudgetPeriodKey = null;
    clients = [];
    storeSettings = null;
    settingsVersion++;
    stats = const StatsModel();
    _lastOrdersFullSync = null;
    currentTabIndex = 2;
    _bumpRoot();
    notifyListeners();
  }

  @override
  void dispose() {
    _orderWatcher.stop();
    _incomingBannerTimer?.cancel();
    appRootVersion.dispose();
    super.dispose();
  }
}
