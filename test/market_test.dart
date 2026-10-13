import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_provider.dart';
import 'package:mvc_app/modules/cars/providers/vehicle_providers.dart';
import 'package:mvc_app/modules/cars/vehicle_inquiry_conversation.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/market/listing_contact.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/market_category_screen.dart';
import 'package:mvc_app/modules/market/market_item.dart';
import 'package:mvc_app/modules/market/market_repository.dart';
import 'package:mvc_app/modules/market/market_screen.dart';
import 'package:mvc_app/modules/market/my_listings_screen.dart';
import 'package:mvc_app/modules/market/widgets/cars_carousel_card.dart';
import 'package:mvc_app/modules/market/widgets/pressable_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A repository that believes [userId] is signed in, without a real session.
class _SignedInRepository extends MarketRepository {
  _SignedInRepository(super.client, this.userId);

  final String userId;

  @override
  String? get currentUserId => userId;
}

Future<void> _settle(WidgetTester tester, [int frames = 6]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A client whose every PostgREST call is answered by [respond] and recorded
/// in [requests], so a test can assert on the query the app actually sends.
SupabaseClient _fakeClient(
  List<Uri> requests,
  String Function(Uri url) respond,
) {
  return SupabaseClient(
    'https://test.supabase.co',
    'test-anon-key',
    authOptions: const AuthClientOptions(
      autoRefreshToken: false,
      authFlowType: AuthFlowType.implicit,
    ),
    // postgrest reads `response.request` while parsing, so it has to be
    // carried back on every canned response.
    httpClient: MockClient((request) async {
      requests.add(request.url);
      return http.Response(
        respond(request.url),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

Map<String, dynamic> _itemRow({
  String id = 'item-1',
  String title = 'Oak dining table',
  num price = 1200,
  num? promotion,
  String? condition = 'like_new',
  String? images,
  bool isSold = false,
}) {
  return {
    'id': id,
    'category': 'furniture',
    'title': title,
    'description': null,
    'condition': condition,
    'price': price,
    'promotion': promotion,
    'location': 'Austin',
    'images': images,
    'videos': null,
    'contact_phone': null,
    'is_sold': isSold,
    'created_by': 'seller-1',
    'created_at': '2026-09-01T00:00:00Z',
    'updated_at': '2026-09-01T00:00:00Z',
  };
}

VehicleListing _car({
  String id = 'car-1',
  int year = 2019,
  String make = 'Ford',
  String model = 'F-150',
  num price = 30000,
  String source = 'community',
  String createdAt = '2026-09-01T00:00:00Z',
  bool isSold = false,
  String? images,
}) {
  return VehicleListing.fromJson({
    'id': id,
    'stock': '1001',
    'year': year,
    'make': make,
    'model': model,
    'status': 'Pre-Owned',
    'price': price,
    'images': images,
    'is_sold': isSold,
    'source': source,
    'created_at': createdAt,
    'updated_at': createdAt,
  });
}

/// A provider that reports [name], for building [ProviderFetch] results.
class _FakeProvider implements VehicleProvider {
  _FakeProvider(this.providerKey);

  @override
  final String providerKey;

  @override
  String get displayName => providerKey;

  @override
  Future<List<VehicleListing>> fetchVehicles({
    bool forceRefresh = false,
  }) async {
    throw UnimplementedError();
  }
}

void main() {
  group('MarketItem', () {
    test('parses a market_items row', () {
      final item = MarketItem.fromJson(
        _itemRow(promotion: 999.5, images: 'https://a/1.jpg, https://a/2.jpg,'),
      );

      expect(item.images, ['https://a/1.jpg', 'https://a/2.jpg']);
      expect(item.firstImageUrl, 'https://a/1.jpg');
      expect(item.conditionLabel, 'Used – Like New');
      expect(item.displayPrice, r'$1,200');
      expect(item.hasPromo, isTrue);
      expect(item.displayPromoPrice, r'$999.50');
      expect(item.isOwnedBy('seller-1'), isTrue);
      expect(item.isOwnedBy(null), isFalse);
    });

    test('a zero price is a giveaway, not "call for price"', () {
      final item = MarketItem.fromJson(_itemRow(price: 0, condition: null));

      expect(item.isFree, isTrue);
      expect(item.displayPrice, 'Free');
      expect(item.conditionLabel, isNull);
    });

    test('prices show cents only when there are some', () {
      expect(MarketItem.formatPrice(4.99), r'$4.99');
      expect(MarketItem.formatPrice(4.5), r'$4.50');
      expect(MarketItem.formatPrice(1234567), r'$1,234,567');
    });
  });

  group('inquiry conversations about Market items', () {
    Map<String, dynamic> row(Map<String, dynamic> extra) => {
      'id': 'conv-1',
      'buyer_id': 'buyer-1',
      'seller_id': 'seller-1',
      'organization_id': null,
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-01T00:00:00Z',
      ...extra,
    };

    test('an item conversation parses with no vehicle_id', () {
      // Before migration 081's client work, vehicle_id was cast to a
      // non-null String — this row would have failed the whole inbox.
      final conv = VehicleInquiryConversation.fromJson(
        row({
          'vehicle_id': null,
          'market_item_id': 'item-1',
          'listing_type': 'market_item',
          'listing_category': 'furniture',
          'listing_title': 'Oak dining table',
          'listing_price': 1200,
          'listing_image_url': 'https://a/1.jpg',
          'listing_is_sold': true,
        }),
      );

      expect(conv.vehicleId, isNull);
      expect(conv.isMarketItem, isTrue);
      expect(conv.listingTitle, 'Oak dining table');
      expect(conv.listingPrice, 1200);
      expect(conv.listingImageUrl, 'https://a/1.jpg');
      expect(conv.listingCategory, 'furniture');
      expect(conv.listingIsSold, isTrue);
    });

    test('a vehicle conversation without listing_* columns still reads', () {
      // A database the app reaches before migration 081 is applied.
      final conv = VehicleInquiryConversation.fromJson(
        row({
          'vehicle_id': 'vehicle-1',
          'vehicle_year': 2020,
          'vehicle_make': 'Honda',
          'vehicle_model': 'Civic',
          'vehicle_price': 18000,
          'vehicle_image_url': 'https://v/1.jpg',
        }),
      );

      expect(conv.isMarketItem, isFalse);
      expect(conv.listingTitle, '2020 Honda Civic');
      expect(conv.listingPrice, 18000);
      expect(conv.listingImageUrl, 'https://v/1.jpg');
      expect(conv.listingIsSold, isFalse);
    });
  });

  group('MarketRepository queries', () {
    test('categories: active only, in ascending display order', () async {
      final requests = <Uri>[];
      final repo = MarketRepository(_fakeClient(requests, (_) => '[]'));

      await repo.fetchCategories();

      final params = requests.single.queryParameters;
      expect(requests.single.path, endsWith('/market_categories'));
      expect(params['is_active'], 'eq.true');
      // postgrest-dart defaults to descending; Cars & Trucks must come first.
      expect(params['order'], startsWith('sort_order.asc'));
    });

    test('items: one category, newest first, paged by offset', () async {
      final requests = <Uri>[];
      final repo = MarketRepository(_fakeClient(requests, (_) => '[]'));

      await repo.fetchItems(category: 'furniture', offset: 20, limit: 20);

      final params = requests.single.queryParameters;
      expect(requests.single.path, endsWith('/market_items'));
      expect(
        params['or'],
        '(category.eq.furniture,secondary_category.eq.furniture)',
      );
      expect(params['order'], startsWith('created_at.desc'));
      expect(params['offset'], '20');
      expect(params['limit'], '20');
      expect(params.containsKey('title'), isFalse);
    });

    test("my listings: the user's items, and only their in-app cars", () async {
      final requests = <Uri>[];
      final repo = MarketRepository(_fakeClient(requests, (_) => '[]'));

      await repo.fetchItemsBy('seller-1');
      await repo.fetchVehiclesBy('seller-1');

      final items = requests[0].queryParameters;
      expect(requests[0].path, endsWith('/market_items'));
      expect(items['created_by'], 'eq.seller-1');
      expect(items.containsKey('category'), isFalse);

      final cars = requests[1].queryParameters;
      expect(requests[1].path, endsWith('/vehicle_listings'));
      expect(cars['created_by'], 'eq.seller-1');
      // A vendor's car is never offered for editing.
      expect(cars['source'], 'eq.community');
    });

    test('search treats LIKE wildcards in the text literally', () async {
      final requests = <Uri>[];
      final repo = MarketRepository(_fakeClient(requests, (_) => '[]'));

      await repo.fetchItems(
        category: 'furniture',
        search: ' 50%_off ',
        offset: 0,
        limit: 20,
      );

      expect(requests.single.queryParameters['title'], r'ilike.%50\%\_off%');
    });
  });

  group('category icons', () {
    test('every slug migration 083 ships has one of its own', () {
      const slugs = [
        'cars_trucks',
        'recreational_vehicles',
        'home_garden',
        'industrial',
        'ag_livestock',
        'sports_fitness',
        'clothing',
        'electronics',
        'furniture',
        'pets',
        'musical_instruments',
        'auto_parts',
        'outdoors',
        'general',
      ];

      final icons = {for (final slug in slugs) MarketCategory.iconFor(slug)};

      expect(icons.length, slugs.length, reason: 'no two share an icon');
      expect(icons, isNot(contains(Icons.storefront_outlined)));
      // A category added in SQL after this build still renders.
      expect(MarketCategory.iconFor('drones'), Icons.storefront_outlined);
    });
  });

  group("the seller's phone number", () {
    test('shows six digits, keeping the way the seller wrote them', () {
      expect(shortenedPhone('+1 (555) 123-4567'), '+1 (555) 12…');
      expect(shortenedPhone('5551234567'), '555123…');
    });

    test('a number no longer than that is left whole', () {
      expect(shortenedPhone('555123'), '555123');
      expect(shortenedPhone('5551'), '5551');
      expect(shortenedPhone(''), '');
    });
  });

  group('the Cars list', () {
    test(
      'mixes every vendor, newest first, and skips the ones that failed',
      () {
        final merged = VehicleProviders.mergeNewestFirst([
          ProviderFetch(
            provider: _FakeProvider('vauto'),
            vehicles: [
              _car(id: 'dealer-old', createdAt: '2026-09-01T00:00:00Z'),
              _car(id: 'dealer-new', createdAt: '2026-09-05T00:00:00Z'),
            ],
          ),
          ProviderFetch(
            provider: _FakeProvider('community'),
            vehicles: [_car(id: 'mine', createdAt: '2026-09-03T00:00:00Z')],
          ),
          ProviderFetch(
            provider: _FakeProvider('liftkit'),
            error: 'Could not load LiftKit inventory.',
          ),
        ]);

        // Interleaved by date: whose inventory it is decides nothing.
        expect(merged.map((v) => v.id), ['dealer-new', 'mine', 'dealer-old']);
      },
    );

    test('one import shares one date, so ties keep the order they came in', () {
      List<String> order() => VehicleProviders.mergeNewestFirst([
        ProviderFetch(
          provider: _FakeProvider('vauto'),
          vehicles: [
            for (var i = 0; i < 40; i++)
              _car(id: 'feed-$i', createdAt: '2026-09-01T00:00:00Z'),
          ],
        ),
      ]).map((v) => v.id).toList();

      // List.sort is not stable: without a tiebreak this shuffles, and shuffles
      // differently each call, so the list would jitter on every refresh.
      expect(order(), [for (var i = 0; i < 40; i++) 'feed-$i']);
      expect(order(), order());
    });
  });

  group('CarsCarouselCard', () {
    testWidgets('advances on its own and comes back round', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CarsCarouselCard(
              name: 'Cars',
              cars: [
                _car(id: 'a', price: 30000),
                _car(id: 'b', price: 21500),
              ],
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump();

      final pages = tester.widget<PageView>(find.byType(PageView)).controller!;
      expect(pages.page, 0);
      expect(find.text(r'$30,000'), findsOneWidget);

      // Each car holds the stage for a while before the next slides in.
      await tester.pump(const Duration(seconds: 3));
      expect(pages.page, 0);

      await tester.pump(const Duration(milliseconds: 2100));
      await tester.pump(const Duration(seconds: 1));
      expect(pages.page, 1);
      expect(find.text(r'$21,500'), findsOneWidget);

      // Two cars, but the rotation never runs out: it comes back round.
      for (var i = 0; i < 7; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(pages.page, 2);
      expect(find.text(r'$30,000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tap anywhere opens the category', (tester) async {
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CarsCarouselCard(
              name: 'Cars',
              cars: [_car(id: 'a'), _car(id: 'b')],
              onTap: () => opened++,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(CarsCarouselCard));
      await tester.pump(const Duration(milliseconds: 300));
      expect(opened, 1);
    });

    testWidgets('holds the space while inventory loads', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CarsCarouselCard(
              name: 'Cars',
              cars: const [],
              loading: true,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(ShimmerBox), findsOneWidget);
      expect(find.byType(PageView), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('MarketScreen', () {
    testWidgets('lists categories and opens one', (tester) async {
      final requests = <Uri>[];
      final client = _fakeClient(requests, (url) {
        if (url.path.endsWith('/market_categories')) {
          return jsonEncode([
            {'slug': 'cars_trucks', 'name': 'Cars', 'sort_order': 10},
            {'slug': 'furniture', 'name': 'Furniture', 'sort_order': 90},
            {'slug': 'pets', 'name': 'Pets', 'sort_order': 100},
          ]);
        }
        if (url.path.endsWith('/market_items')) {
          return jsonEncode([
            _itemRow(id: 'a', title: 'Oak dining table'),
            _itemRow(id: 'b', title: 'Leather sofa', isSold: true),
          ]);
        }
        return '[]';
      });
      // Not disposed: SupabaseClient.dispose waits on work that never runs
      // under the test binding's fake async, and hangs the teardown.

      await tester.pumpWidget(
        MaterialApp(
          home: MarketScreen(
            repository: MarketRepository(client),
            carsLoader: () async => [_car(id: 'a', price: 30000)],
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Cars is the hero card, and so is not also a tile.
      expect(find.byType(CarsCarouselCard), findsOneWidget);
      expect(find.text('Cars'), findsOneWidget);
      expect(find.text(r'$30,000'), findsWidgets);
      expect(find.text('Furniture'), findsOneWidget);
      expect(find.text('Pets'), findsOneWidget);

      // The tiles sit below the Cars hero, past the test window's fold.
      await tester.ensureVisible(find.text('Furniture'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Furniture'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Oak dining table'), findsOneWidget);
      expect(find.text('Leather sofa'), findsOneWidget);
      // Sold items stay listed, stamped rather than hidden.
      expect(find.text('SOLD'), findsOneWidget);
      // A short page is the last one: the footer says so instead of spinning.
      // Scoped to this screen, so the search is not thrown by any scrollable
      // on the Market screen below it.
      await tester.scrollUntilVisible(
        find.text('Showing all 2 listings'),
        200,
        scrollable: find.descendant(
          of: find.descendant(
            of: find.byType(MarketCategoryScreen),
            matching: find.byType(ListView),
          ),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Showing all 2 listings'), findsOneWidget);
      expect(
        requests.last.queryParameters['or'],
        '(category.eq.furniture,secondary_category.eq.furniture)',
      );
    });
  });

  group('MyListingsScreen', () {
    testWidgets('shows cars and items together, each editable', (tester) async {
      final client = _fakeClient([], (url) {
        if (url.path.endsWith('/market_categories')) {
          return jsonEncode([
            {'slug': 'cars_trucks', 'name': 'Cars', 'sort_order': 10},
            {'slug': 'furniture', 'name': 'Furniture', 'sort_order': 90},
          ]);
        }
        if (url.path.endsWith('/market_items')) {
          return jsonEncode([_itemRow(title: 'Oak dining table')]);
        }
        if (url.path.endsWith('/vehicle_listings')) {
          return jsonEncode([
            {
              'id': 'car-1',
              'stock': '1001',
              'year': 2019,
              'make': 'Ford',
              'model': 'F-150',
              'status': 'Pre-Owned',
              'price': 30000,
              'is_sold': true,
              'created_by': 'seller-1',
              'created_at': '2026-08-01T00:00:00Z',
              'updated_at': '2026-08-01T00:00:00Z',
            },
          ]);
        }
        return '[]';
      });

      await tester.pumpWidget(
        MaterialApp(
          home: MyListingsScreen(
            repository: _SignedInRepository(client, 'seller-1'),
          ),
        ),
      );
      await _settle(tester);

      // Newest first: the item (September) above the car (August).
      final itemY = tester.getTopLeft(find.text('Oak dining table')).dy;
      final carY = tester.getTopLeft(find.text('2019 Ford F-150')).dy;
      expect(itemY, lessThan(carY));
      expect(find.text('Furniture'), findsOneWidget);
      expect(find.text('Cars'), findsOneWidget);
      expect(find.text('Sold'), findsOneWidget);

      await tester.tap(find.byTooltip('Listing actions').last);
      await _settle(tester, 3);
      expect(find.text('Edit'), findsOneWidget);
      // The car is sold, so the offer is to put it back on the market.
      expect(find.text('Mark as Available'), findsOneWidget);
    });
  });
}
