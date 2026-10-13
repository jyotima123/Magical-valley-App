import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/modules/cars/vehicle_inquiry_conversation.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';

/// Buyers message dealers in-app, which means a feed vehicle has to be
/// materialized into `vehicle_listings` before a conversation can point at it.
/// These lock in the three things the `create_or_get_dealer_vehicle_inquiry`
/// RPC is handed: which feed the vehicle came from, its stable external id,
/// and a payload the shadow row can be built from.
void main() {
  VehicleListing dealerListing({
    String id = 'liftkit:PG205293',
    String stock = 'PG205293',
  }) {
    return VehicleListing(
      id: id,
      stock: stock,
      vin: '3GCUDHEL5PG205293',
      year: 2023,
      make: 'Chevrolet',
      model: 'Silverado 1500',
      trim: 'ZR2',
      status: 'Pre-Owned',
      mileage: 12500,
      price: 61995,
      images: const ['https://cdn.example.com/a.jpg', 'https://cdn.example.com/b.jpg'],
      videos: const [],
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      source: 'liftkit',
      externalId: 'liftkit:PG205293',
      vdpUrl: 'https://dealer.example.com/vehicle/PG205293',
    );
  }

  group('dealer source key', () {
    test('matches the values stored in dealer_sources.source', () {
      expect(dealerListing().dealerSourceKey, 'liftkit');
      expect(kCommunitySource, 'community');
    });

    test('dealer feed vehicles are flagged as such', () {
      expect(dealerListing().isFromDealerFeed, isTrue);
    });
  });

  group('external id', () {
    test('is namespaced by feed so two providers cannot collide', () {
      expect(dealerListing().id, startsWith('liftkit:'));
    });

    test('is stable across reloads of the same vehicle', () {
      expect(dealerListing().id, dealerListing().id);
    });
  });

  group('shadow row payload', () {
    test('carries the columns the RPC inserts', () {
      final json = dealerListing().toJson();

      expect(json['stock'], 'PG205293');
      expect(json['vin'], '3GCUDHEL5PG205293');
      expect(json['year'], 2023);
      expect(json['make'], 'Chevrolet');
      expect(json['model'], 'Silverado 1500');
      expect(json['price'], 61995);
      // vehicle_listings stores photo lists as a comma-joined string.
      expect(json['images'], contains(','));
    });

    test('sends a status the vehicle_listings CHECK accepts', () {
      expect(
        dealerListing().toJson()['status'],
        anyOf('New', 'Pre-Owned', 'Certified Pre-Owned'),
      );
    });
  });

  group('source round-trip', () {
    test('a row read back keeps its feed provenance', () {
      final listing = VehicleListing.fromJson({
        'id': '0f1c3e6a-0000-4000-8000-000000000001',
        'stock': 'PG205293',
        'year': 2023,
        'make': 'Chevrolet',
        'model': 'Silverado 1500',
        'price': 61995,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'source': 'liftkit',
      });

      expect(listing.source, 'liftkit');
      expect(listing.isFromDealerFeed, isTrue);
    });

    test('rows without a source column read as community listings', () {
      final listing = VehicleListing.fromJson({
        'id': '0f1c3e6a-0000-4000-8000-000000000002',
        'stock': '1001',
        'year': 2020,
        'make': 'Honda',
        'model': 'Civic',
        'price': 18000,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
      });

      expect(listing.source, kCommunitySource);
      expect(listing.isFromDealerFeed, isFalse);
    });
  });

  /// A dealer conversation belongs to an organization, so it has no seller_id
  /// and is answered by whichever admins currently staff that org. These pin
  /// the parts of that the client has to get right.
  group('conversation ownership', () {
    const buyer = 'aaaaaaaa-0000-4000-8000-000000000001';
    const privateSeller = 'bbbbbbbb-0000-4000-8000-000000000002';
    const premier = 'cccccccc-0000-4000-8000-000000000003';
    const premierAdmin = 'dddddddd-0000-4000-8000-000000000004';

    Map<String, dynamic> row({
      String? sellerId,
      String? organizationId,
      String? sellerFullName,
    }) {
      return {
        'id': '0f1c3e6a-0000-4000-8000-00000000000a',
        'vehicle_id': '0f1c3e6a-0000-4000-8000-00000000000b',
        'buyer_id': buyer,
        'seller_id': sellerId,
        'organization_id': organizationId,
        'created_at': '2026-01-01T00:00:00Z',
        'updated_at': '2026-01-01T00:00:00Z',
        'buyer_full_name': 'Ada Buyer',
        'seller_full_name': sellerFullName,
      };
    }

    VehicleInquiryConversation dealerConversation() =>
        VehicleInquiryConversation.fromJson(row(
          organizationId: premier,
          // The view COALESCEs the org's name into seller_full_name.
          sellerFullName: 'Premier Motors',
        ));

    VehicleInquiryConversation privateConversation() =>
        VehicleInquiryConversation.fromJson(row(
          sellerId: privateSeller,
          sellerFullName: 'Grace Seller',
        ));

    test('a dealer conversation parses with no seller_id', () {
      final conv = dealerConversation();

      expect(conv.sellerId, isNull);
      expect(conv.organizationId, premier);
      expect(conv.isDealerConversation, isTrue);
    });

    test('a private-sale conversation keeps its individual seller', () {
      final conv = privateConversation();

      expect(conv.sellerId, privateSeller);
      expect(conv.organizationId, isNull);
      expect(conv.isDealerConversation, isFalse);
    });

    test('an org admin who is not the seller still counts as the seller side',
        () {
      // The regression this whole change exists to prevent: keying off
      // seller_id would leave every dealership admin on the buyer side of
      // their own inbox, because a dealer conversation has no seller_id.
      final conv = dealerConversation();

      expect(conv.isSellerSide(premierAdmin), isTrue);
      expect(conv.counterpartyName(premierAdmin), 'Ada Buyer');
    });

    test('the buyer sees the dealership as the counterparty', () {
      final conv = dealerConversation();

      expect(conv.isSellerSide(buyer), isFalse);
      expect(conv.counterpartyName(buyer), 'Premier Motors');
    });

    test('a private sale names both people', () {
      final conv = privateConversation();

      expect(conv.counterpartyName(buyer), 'Grace Seller');
      expect(conv.counterpartyName(privateSeller), 'Ada Buyer');
    });

    test('a signed-out viewer is never treated as the seller', () {
      expect(dealerConversation().isSellerSide(null), isFalse);
    });
  });
}
