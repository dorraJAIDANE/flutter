import 'package:flutter_test/flutter_test.dart';
import 'package:xfy_mobile/core/l10n/app_l10n.dart';
import 'package:xfy_mobile/core/utils/formatters.dart';
import 'package:xfy_mobile/core/utils/xfy_stats_engine.dart';
import 'package:xfy_mobile/data/models/daily_budget_model.dart';
import 'package:xfy_mobile/data/models/order_model.dart';
import 'package:xfy_mobile/data/models/product_model.dart';
import 'package:xfy_mobile/data/models/store_settings_model.dart';
import 'package:xfy_mobile/data/models/user_model.dart';
import 'package:xfy_mobile/data/services/order_notification_service.dart';
import 'package:xfy_mobile/features/scanner/scan_qr_screen.dart';

void main() {
  test('formatTnd formats dinars cleanly', () {
    expect(XfyFormatters.formatTnd(120), '120 DT');
    expect(XfyFormatters.formatTnd(49.5), '49.50 DT');
  });

  test('computeUnifiedStatus matches Web XFY multi-carrier rules', () {
    // statutIntigo = "Livré" overrides status = "traitee"
    expect(
      XfyFormatters.computeUnifiedStatus(
        status: 'traitee',
        statutIntigo: 'Livré',
      ),
      'encaissee',
    );
    // "En cours de livraison" MUST stay "traitee", NOT "encaissee"
    expect(
      XfyFormatters.computeUnifiedStatus(
        status: 'traitee',
        statutIntigo: 'En cours de livraison',
      ),
      'traitee',
    );
    // "Retour reçu" -> retournee
    expect(
      XfyFormatters.computeUnifiedStatus(
        status: 'traitee',
        statutIntigo: 'Retour reçu',
      ),
      'retournee',
    );
    // "Annulée" -> annulee
    expect(
      XfyFormatters.computeUnifiedStatus(
        status: 'annulee',
        statutIntigo: 'N/A',
      ),
      'annulee',
    );
    // Explicit XFY status "encaissee" MUST ALWAYS count as delivered ("encaissee"),
    // even if a previous carrier statutIntigo was still "En cours de livraison", "Retour reçu" or "Annulation"
    expect(
      XfyFormatters.computeUnifiedStatus(
        status: 'encaissee',
        statutIntigo: 'En cours de livraison',
      ),
      'encaissee',
    );
    expect(
      XfyFormatters.computeUnifiedStatus(
        status: 'encaissee',
        statutIntigo: 'Retour reçu',
      ),
      'encaissee',
    );
    expect(
      XfyFormatters.computeUnifiedStatus(
        status: 'encaissee',
        statutIntigo: 'Annulation',
      ),
      'encaissee',
    );
  });

  test('Manual XFY encaissee status auto-fills dateLivraison and counts as delivered in stats', () {
    final baseOrder = OrderModel.fromJson({
      'id': 99,
      'nom': 'Sami',
      'phoneNumber': '29123456',
      'status': 'traitee',
      'statutIntigo': 'En cours de livraison',
      'produit': 'Montre Pro',
      'quantite': '1',
      'prix': '80 DT',
      'fraisLivraison': 8,
      'total': 88,
      'timestamp': '2026-10-01T10:00:00',
    });

    final payload = baseOrder.toUpdatePayload(newStatus: 'encaissee');
    expect(payload['status'], 'encaissee');
    expect((payload['dateLivraison'] ?? '').toString().isNotEmpty, isTrue);

    final now = DateTime(2026, 11, 26, 21, 0);
    final encaisseeOrder = baseOrder.copyWith(
      status: 'encaissee',
      dateLivraison: '26/11/2026 20:30',
    );
    expect(encaisseeOrder.unifiedStatus, 'encaissee');
    expect(encaisseeOrder.isDelivered, isTrue);

    final stats = XfyStatsEngine.compute(
      allOrders: [encaisseeOrder],
      products: const [
        ProductModel(id: 100, nom: 'Montre Pro', price: 80),
      ],
      preset: 'today',
      settings: const StoreSettingsModel(
        storeId: 1,
        fraisLivraison: 8,
        fraisLivraisonSociete: 6,
      ),
      nowOverride: now,
    );
    expect(stats.deliveredOrdersCount, 1);
    expect(stats.productsSold, 1);
    expect(stats.revenue, 82.0); // 80 produit + 2 marge livraison
    expect(stats.activeClientsCount, 1);
  });

  test('parseDateRobust handles DD/MM/YYYY, YYYY-MM-DD, space-time, and arrays', () {
    final fr = XfyFormatters.parseDateRobust('24/11/2026 14:35');
    expect(fr?.year, 2026);
    expect(fr?.month, 11);
    expect(fr?.day, 24);
    expect(fr?.hour, 14);
    expect(fr?.minute, 35);

    final sql = XfyFormatters.parseDateRobust('2026-11-20 09:10:00');
    expect(sql?.year, 2026);
    expect(sql?.month, 11);
    expect(sql?.day, 20);

    final arr = XfyFormatters.parseDateRobust([2026, 11, 18]);
    expect(arr?.year, 2026);
    expect(arr?.month, 11);
    expect(arr?.day, 18);

    expect(XfyFormatters.parseDateRobust('Non spécifié'), isNull);
  });

  test('OrderModel parses semicolon multi-item revenue and units like Web', () {
    final order = OrderModel.fromJson({
      'id': 10,
      'nom': 'Ahmed',
      'phoneNumber': '22111222',
      'status': 'traitee',
      'statutIntigo': 'Livré',
      'produit': 'Montre Pro; Bracelet Cuir',
      'quantite': '2; 1',
      'prix': '45 DT; 20 DT',
      'fraisLivraison': 8,
      'total': 118,
      'dateLivraison': '24/11/2026 10:00',
    });

    expect(order.unifiedStatus, 'encaissee');
    expect(order.totalUnitsCount, 3);
    expect(order.productRevenue, 110.0);
    expect(order.effectiveAnalyticsDate?.day, 24);
    expect(order.effectiveAnalyticsDate?.month, 11);
  });

  test('XfyStatsEngine matches Web Analytics and Statistics formulas exactly', () {
    final now = DateTime(2026, 11, 24, 15, 0);
    final settings = const StoreSettingsModel(
      storeId: 1,
      fraisLivraison: 8,
      fraisLivraisonSociete: 6, // +2 DT delivery margin per delivered order
      fraisRetourSociete: 4, // 4 DT return cost per returned order
    );
    final products = [
      const ProductModel(
        id: 100,
        nom: 'Montre Pro',
        price: 50,
        purchasePrice: 20,
        packagingCost: 2,
        metaAdsCost: 3,
        otherCosts: 1,
      ),
    ];
    final dailyBudgets = [
      const DailyBudgetModel(
        id: 1,
        productId: 100,
        dateYmd: '2026-11-24',
        purchasePrice: 20,
        packagingCost: 2,
        metaAdsCost: 10,
        otherCosts: 1,
      ),
    ];

    final orders = [
      // 1. Delivered via statutIntigo ("Livré") on 24/11/2026 -> counts in KPIs
      OrderModel.fromJson({
        'id': 1,
        'nom': 'Client A',
        'phoneNumber': '20000001',
        'status': 'traitee',
        'statutIntigo': 'Livré',
        'produit': 'Montre Pro',
        'quantite': '2',
        'prix': '50 DT',
        'fraisLivraison': 8,
        'total': 108,
        'timestamp': '2026-11-20T10:00:00',
        'dateLivraison': '24/11/2026 11:00',
      }),
      // 2. Pending ("en_cours") on 24/11/2026 -> must NOT count in delivered revenue/orders
      OrderModel.fromJson({
        'id': 2,
        'nom': 'Client B',
        'phoneNumber': '20000002',
        'status': 'en_cours',
        'produit': 'Montre Pro',
        'quantite': '1',
        'prix': '50 DT',
        'fraisLivraison': 8,
        'total': 58,
        'timestamp': '2026-11-24T12:00:00',
      }),
      // 3. Returned via statutIntigo on 24/11/2026 -> counts in returns
      OrderModel.fromJson({
        'id': 3,
        'nom': 'Client C',
        'phoneNumber': '20000003',
        'status': 'traitee',
        'statutIntigo': 'Retour reçu',
        'produit': 'Montre Pro',
        'quantite': '1',
        'prix': '50 DT',
        'total': 58,
        'timestamp': '2026-11-18T09:00:00',
        'datePremierRetour': '24/11/2026',
      }),
      // 4. Cancelled -> excluded
      OrderModel.fromJson({
        'id': 4,
        'nom': 'Client D',
        'phoneNumber': '20000004',
        'status': 'annulee',
        'produit': 'Montre Pro',
        'quantite': '1',
        'prix': '50 DT',
        'timestamp': '2026-11-24T13:00:00',
      }),
    ];

    final result = XfyStatsEngine.compute(
      allOrders: orders,
      products: products,
      preset: 'today',
      settings: settings,
      dailyBudgets: dailyBudgets,
      nowOverride: now,
    );

    // Exact Web KPIs:
    expect(result.deliveredOrdersCount, 1);
    expect(result.productsSold, 2);
    expect(result.totalReturns, 1);
    // Return rate = 1 / (1 + 1) * 100 = 50%
    expect(result.returnRate, 50.0);
    // Revenue = (50 * 2) + deliveryMargin (8 - 6 = 2) = 102 DT
    expect(result.revenue, 102.0);
    // Returned amount = 1 * fraisRetourSociete (4) = 4 DT
    expect(result.returnedAmount, 4.0);
    // Analytics budget = (20+2+3+1)*2 + 1*4 = 56 DT -> profit = 46 DT
    expect(result.analyticsBudget, 56.0);
    expect(result.analyticsProfit, 46.0);
    // Statistics budget = (20+2+1)*2 + metaAds(10) + returnFee(4) = 60 DT -> profit = 42 DT
    expect(result.statisticsBudget, 60.0);
    expect(result.statisticsProfit, 42.0);
    // Active clients (delivered only) = 1
    expect(result.activeClientsCount, 1);
  });

  test('tunisianWhatsAppNumber adds 216 prefix', () {
    expect(XfyFormatters.tunisianWhatsAppNumber('92 557 500'), '21692557500');
    expect(XfyFormatters.tunisianWhatsAppNumber('+216 92557500'), '21692557500');
  });

  test('ProductModel parses ProduitAvecSousCategoriesDTO with String variant IDs and inStock', () {
    final prod = ProductModel.fromJson({
      'id': 55,
      'nom': 'Sneakers XFY',
      'price': 129.0,
      'images': ['https://xfy.tn/uploads/categories/shoe.jpg'],
      'variants': [
        {
          'id': '401',
          'variantName': 'Noir 42',
          'inStock': 7,
          'available': 7,
          'price': 129.0,
          'option1': 'Noir',
          'option2': '42',
          'produitId': 55,
        },
        {
          'id': '402',
          'inStock': 3,
          'price': 129.0,
          'option1': 'Blanc',
          'option2': '43',
        },
      ],
    });

    expect(prod.id, 55);
    expect(prod.resolvedImageUrl, 'https://xfy.tn/uploads/categories/shoe.jpg');
    expect(prod.variants.length, 2);
    expect(prod.variants.first.id, '401');
    expect(prod.variants.first.label, 'Noir 42');
    expect(prod.variants.last.label, 'Blanc / 43');
    expect(prod.totalStock, 10);
  });

  test('XfyQrParser extracts order ID, reference, and bordereau codes', () {
    expect(
      XfyQrParser.extractCode('https://xfy.tn/scan-commande/1042'),
      '1042',
    );
    expect(
      XfyQrParser.extractCode('https://xfy.tn/scan-commande/CMD-2026-88?src=qr'),
      'CMD-2026-88',
    );
    expect(XfyQrParser.extractCode('#5012'), '5012');
    expect(XfyQrParser.extractCode('INTIGO-998877'), 'INTIGO-998877');
  });

  test('XfyUser matches Web profile DB mapping and preserves stores on copyWith', () {
    final user = XfyUser.fromJson({
      'id': 7,
      'username': 'Dorra',
      'firstName': 'Ben Ali',
      'email': 'dorra@xfy.tn',
      'phoneNumber': '92557500',
      'language': 'fr',
      'role': 'SELLER',
      'stores': [
        {'id': 12, 'name': 'Ma Boutique'},
      ],
    });

    expect(user.uiFirstName, 'Dorra');
    expect(user.uiLastName, 'Ben Ali');
    expect(user.displayName, 'Dorra Ben Ali');
    expect(user.initials, 'DB');

    final updated = user.copyWith(
      username: 'Dorra2',
      phoneNumber: '55112233',
      token: 'new-jwt',
    );
    expect(updated.stores.length, 1);
    expect(updated.toJson()['phoneNumber'], '55112233');
    expect(updated.toJson()['token'], 'new-jwt');
  });

  test('AppL10n switches FR/EN/AR with RTL and notifications omit #ID', () {
    AppL10n.setLanguage('fr');
    expect(AppL10n.isRtl, isFalse);
    final frTitle = OrderNotificationService.formatOrderAlertTitle(129);
    expect(frTitle, 'Nouvelle commande • 129 DT');
    expect(frTitle.contains('#'), isFalse);

    AppL10n.setLanguage('en');
    expect(AppL10n.isRtl, isFalse);
    expect(OrderNotificationService.formatOrderAlertTitle(85.5), 'New order • 85.50 DT');
    expect(AppL10n.t('nav_settings'), 'Settings');

    AppL10n.setLanguage('ar');
    expect(AppL10n.isRtl, isTrue);
    expect(OrderNotificationService.formatOrderAlertTitle(120), 'طلب جديد • 120 DT');
    expect(AppL10n.t('nav_settings'), 'الإعدادات');

    AppL10n.setLanguage('fr');
  });

  test('OrderNotificationService exposes Shopify/Converty default + 3 extra ringtones', () {
    expect(OrderNotificationService.ringtones.length, 4);
    expect(OrderNotificationService.defaultRingtoneId, 'shopify_chaching');
    expect(OrderNotificationService.ringtones.first.id, 'shopify_chaching');
    expect(OrderNotificationService.ringtones.first.isDefault, isTrue);
    expect(
      OrderNotificationService.resolveRingtone('unknown').id,
      'shopify_chaching',
    );
    expect(OrderNotificationService.resolveRingtone('gold_coins').fileName, 'gold_coins.wav');
  });

  test('OrderModel detects missing delivery fields, capture source, and carrier status', () {
    final incomplete = OrderModel.fromJson({
      'id': 99,
      'nom': 'Sami',
      'phoneNumber': '1234',
      'status': 'en_cours',
      'produit': 'Veste',
      'total': 120,
      'image': '/Uploads/capture_99.jpg',
    });
    expect(incomplete.hasCapture, isTrue);
    expect(incomplete.captureSource, '/Uploads/capture_99.jpg');
    expect(incomplete.canDispatchToCarrier, isTrue);
    expect(incomplete.hasMissingDeliveryFields, isTrue);
    expect(
      incomplete.missingDeliveryFields,
      containsAll(['Téléphone (8 chiffres)', 'Gouvernorat', 'Ville / Délégation', 'Adresse']),
    );

    final shipped = incomplete.copyWith(
      phoneNumber: '92557500',
      gouvernorat: 'Tunis',
      ville: 'La Marsa',
      adresse: 'Avenue Habib Bourguiba',
      numeroBordereau: 'FD-123456',
      deliveryCompany: 'first',
      statutIntigo: 'En cours de livraison',
    );
    expect(shipped.hasMissingDeliveryFields, isFalse);
    expect(shipped.canDispatchToCarrier, isFalse);
    expect(shipped.formattedCarrierName, 'First Delivery');
    expect(shipped.carrierStatusLabel, 'En cours de livraison');
  });
}
