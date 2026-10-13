import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/utils/logging_utils.dart';

/// Thrown when the LiftKit feed cannot be read. The Cars screen surfaces this
/// as a dismissible banner rather than an error state — our own listings still
/// render when the dealer feed is down.
class LiftKitException implements Exception {
  final String message;
  final int? statusCode;

  const LiftKitException(this.message, {this.statusCode});

  @override
  String toString() => 'LiftKitException($statusCode): $message';
}

/// Read-only client for the dealer's LiftKit outgoing feed.
///
/// The response shape is decided by the dealer's feed mapping, not by us, so
/// every field is read defensively and normalized into the vocabulary the app
/// already uses for our own listings (see [CarData]) — otherwise the search
/// filters would silently hide the entire dealer inventory.
class LiftKitApiService {
  static const String _baseUrl = 'https://api.liftkit.io/api/v1';
  static const String _logTag = 'LIFTKIT';

  /// The feed is served 100 vehicles at a time; the guard stops a malformed
  /// `has_more` from looping forever (the API allows 60 requests/minute).
  static const int _pageSize = 100;
  static const int _maxPages = 20;

  /// The inventory changes on a dealer's schedule, not per screen open, so a
  /// short cache keeps returning to the Cars tab from burning rate limit.
  static const Duration cacheTtl = Duration(minutes: 10);

  final Dio _dio;

  LiftKitApiService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: _baseUrl,
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 30),
                responseType: ResponseType.json,
              ),
            );

  static List<VehicleListing>? _cached;
  static DateTime? _cachedAt;

  /// The key is optional: environments without a `LIFTKIT_KEY` (QA) simply show
  /// our own listings instead of reporting a failure.
  static String? get _apiKey {
    final key = dotenv.env['LIFTKIT_KEY']?.trim();
    return (key == null || key.isEmpty) ? null : key;
  }

  static bool get isConfigured => _apiKey != null;

  static bool get _cacheIsFresh =>
      _cached != null &&
      _cachedAt != null &&
      DateTime.now().difference(_cachedAt!) < cacheTtl;

  /// Drops the cached inventory. Exposed for tests and for a forced reload.
  static void clearCache() {
    _cached = null;
    _cachedAt = null;
  }

  /// Fetches the dealer inventory, walking every page of the feed.
  ///
  /// Returns an empty list when no API key is configured. Throws
  /// [LiftKitException] when the feed is reachable but unusable.
  Future<List<VehicleListing>> fetchVehicles({bool forceRefresh = false}) async {
    final apiKey = _apiKey;
    if (apiKey == null) {
      infoLog('No LIFTKIT_KEY configured; skipping dealer feed', tag: _logTag);
      return const [];
    }

    if (!forceRefresh && _cacheIsFresh) {
      return _cached!;
    }

    final vehicles = <VehicleListing>[];
    final seenIds = <String>{};
    var page = 1;

    try {
      while (page <= _maxPages) {
        final response = await _dio.get<dynamic>(
          '/vehicles',
          queryParameters: {'page': page, 'limit': _pageSize},
          options: Options(headers: {'X-API-Key': apiKey}),
        );

        final body = response.data;
        if (body is! Map<String, dynamic>) {
          // A non-JSON body means the feed is configured for XML or CSV, which
          // we do not parse — the dealer has to switch the feed to JSON.
          throw const LiftKitException(
            'Dealer feed is not returning JSON. Set the outgoing feed format '
            'to JSON in LiftKit.',
          );
        }

        if (body['success'] == false) {
          throw LiftKitException(
            body['message']?.toString() ?? 'Dealer feed rejected the request',
            statusCode: response.statusCode,
          );
        }

        final rawVehicles = body['vehicles'];
        if (rawVehicles is! List || rawVehicles.isEmpty) break;

        for (final raw in rawVehicles) {
          if (raw is! Map) continue;
          final listing = LiftKitVehicleMapper.toListing(
            Map<String, dynamic>.from(raw),
          );
          // Paging over live inventory can repeat a vehicle if the feed shifts
          // between requests.
          if (listing != null && seenIds.add(listing.id)) {
            vehicles.add(listing);
          }
        }

        if (!_hasMore(body, response.headers)) break;
        page++;
      }

      successLog('Loaded ${vehicles.length} dealer vehicles', tag: _logTag);
      _cached = List.unmodifiable(vehicles);
      _cachedAt = DateTime.now();
      return _cached!;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      errorLog('Dealer feed request failed', tag: _logTag, error: e);
      throw LiftKitException(_messageForStatus(status, e), statusCode: status);
    }
  }

  /// Pagination is header-driven across all formats; JSON repeats it in `meta`.
  static bool _hasMore(Map<String, dynamic> body, Headers headers) {
    final meta = body['meta'];
    if (meta is Map && meta['has_more'] != null) {
      return meta['has_more'] == true || meta['has_more'] == 'true';
    }
    return headers.value('x-has-more')?.toLowerCase() == 'true';
  }

  static String _messageForStatus(int? status, DioException e) {
    switch (status) {
      case 401:
        return 'Dealer inventory key is missing from the request.';
      case 404:
        return 'Dealer inventory key is invalid or the feed is inactive.';
      case 429:
        return 'Dealer inventory is rate limited. Try again in a minute.';
      case 500:
        return 'Dealer inventory is temporarily unavailable.';
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          return 'Could not reach dealer inventory. Check your connection.';
        }
        return 'Could not load dealer inventory.';
    }
  }
}

/// Translates one LiftKit feed vehicle into a [VehicleListing].
///
/// Kept separate from the transport so the (feed-shaped, dealer-configurable)
/// field handling can be exercised without a network call.
class LiftKitVehicleMapper {
  /// Returns null when the payload lacks the identity fields the UI needs.
  static VehicleListing? toListing(Map<String, dynamic> json) {
    final stock = _string(json['stock']);
    final vin = _string(json['vin']);
    final make = _string(json['make']);
    final model = _string(json['model']);

    // Without an identifier we cannot de-duplicate or key list items, and
    // without make/model the card has nothing to show.
    final identifier = stock ?? vin;
    if (identifier == null || make == null || model == null) return null;

    final color = _map(json['color']);
    final engine = _map(json['engine']);
    final transmission = _map(json['transmission']);
    final pricing = _map(json['pricing']);
    final description = _map(json['description']);

    // The feed exposes a full price breakdown; `final` is what the dealer
    // actually advertises, with `original` shown struck through when lower
    // pricing has been applied.
    final listPrice = _toDouble(pricing['original']);
    final finalPrice = _toDouble(pricing['final']) ?? listPrice;
    final hasDiscount =
        listPrice != null && finalPrice != null && finalPrice < listPrice;

    final acquired = _toDate(json['vehicle_acquired']);

    return VehicleListing(
      id: 'liftkit:$identifier',
      stock: stock ?? vin!,
      vin: vin,
      year: int.tryParse(_string(json['year']) ?? '') ?? 0,
      make: make,
      model: model,
      trim: _string(json['trim']),
      body: _body(_string(json['body']), _string(json['type'])),
      status: _status(_string(json['status']), json['certified'] == true),
      mileage: _toInt(json['mileage']) ?? 0,
      // `simple` is the normalized bucket the colour filter chips are built
      // from; the free-text name is only a fallback.
      color: _string(color['simple']) ?? _string(color['name']),
      interior: _string(color['interior']),
      transmission: _transmission(_string(transmission['type'])),
      speed: _string(transmission['speed']),
      engineType: _string(engine['name']) ?? _string(engine['size']),
      fuel: _fuel(_string(json['fuel'])),
      doors: _string(json['doors']),
      price: (hasDiscount ? listPrice : finalPrice) ?? 0,
      promotion: hasDiscount ? finalPrice : null,
      description: _text(
        _string(description['full']) ?? _string(description['short']),
      ),
      location: null,
      images: _urls(json['photos']),
      videos: _urls(json['videos']),
      engineOptions: _string(engine['cylinders']) != null
          ? '${engine['cylinders']} cyl'
          : null,
      packageOptions: _packages(json['packages']),
      transmissionOptions: _string(transmission['description']),
      addonsDescription: _string(_map(json['pricing'])['options_description']),
      contactPhone: null,
      isSold: false,
      createdBy: null,
      createdAt: acquired ?? DateTime.now(),
      updatedAt: acquired ?? DateTime.now(),
      source: 'liftkit',
      externalId: 'liftkit:$identifier',
      vdpUrl: _string(json['vdpurl']) ?? _string(json['vdp_url']),
      drivetrain: _drivetrain(_string(json['drivetrain'])),
      features: _features(json),
    );
  }

  // ─── Vocabulary normalization ───────────────────────────────────────────
  // Filters compare against CarData's option lists, so feed values have to be
  // mapped onto those exact strings or the filtered result set comes back empty.

  /// The feed says `New`/`Used`; our status chips say `Pre-Owned`, with
  /// certified cars promoted to their own chip.
  static String _status(String? raw, bool certified) {
    if (certified) return 'Certified Pre-Owned';
    switch (raw?.toLowerCase().trim()) {
      case 'new':
      case 'n':
        return 'New';
      case 'cpo':
      case 'certified':
      case 'certified pre-owned':
        return 'Certified Pre-Owned';
      default:
        return 'Pre-Owned';
    }
  }

  /// LiftKit splits shape across `type` (SUV/Truck/Van) and `body`
  /// (Wagon/Pickup); every SUV in the feed carries a `Wagon` body, so `type`
  /// wins where the two disagree.
  static String? _body(String? body, String? type) {
    switch (type?.toLowerCase().trim()) {
      case 'suv':
        return 'SUV';
      case 'truck':
        return 'Pickup Truck';
    }
    switch (body?.toLowerCase().trim()) {
      case 'pickup':
      case 'pickup truck':
      case 'crew cab':
      case 'regular cab':
        return 'Pickup Truck';
      case 'passenger van':
      case 'cargo van':
      case 'van':
        return 'Van';
      case 'minivan':
        return 'Minivan';
      case 'sedan':
        return 'Sedan';
      case 'coupe':
        return 'Coupe';
      case 'convertible':
        return 'Convertible';
      case 'hatchback':
        return 'Hatchback';
      case 'wagon':
        return 'Wagon';
      case 'crossover':
        return 'Crossover';
    }
    return body ?? type;
  }

  static String? _fuel(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'gas':
      case 'gasoline':
      case 'unleaded':
        return 'Gasoline';
      case 'diesel':
        return 'Diesel';
      case 'hybrid':
        return 'Hybrid';
      case 'plug-in hybrid':
      case 'plugin hybrid':
        return 'Plug-in Hybrid';
      case 'electric':
      case 'ev':
        return 'Electric';
      case 'flex':
      case 'flex fuel':
      case 'ethanol':
        return 'Flex Fuel';
      case 'hydrogen':
        return 'Hydrogen';
      default:
        return raw;
    }
  }

  static String? _transmission(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'automatic':
        return 'Automatic';
      case 'manual':
        return 'Manual';
      case 'cvt':
      case 'ivt':
        return 'CVT';
      case 'dct':
      case 'semi-auto':
      case 'semi-automatic':
        return 'Semi-Auto / DCT';
      default:
        return raw;
    }
  }

  static String? _drivetrain(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'front wheel drive':
      case 'fwd':
        return 'FWD';
      case 'rear wheel drive':
      case 'rwd':
        return 'RWD';
      case 'all wheel drive':
      case 'awd':
        return 'AWD';
      case 'four wheel drive':
      case '4wd':
      case '4x4':
        return '4WD / 4x4';
      default:
        return raw;
    }
  }

  /// `key_features` is the curated shortlist; the raw `features` array is a
  /// few hundred OEM option strings, useful for matching but not for display.
  static List<String> _features(Map<String, dynamic> json) {
    final key = _stringList(json['key_features']);
    final all = _stringList(json['features']);
    return {...key, ...all}.toList();
  }

  static String? _packages(dynamic raw) {
    if (raw is List && raw.isNotEmpty) {
      final names = raw
          .map((p) => p is Map ? _string(p['name']) : _string(p))
          .whereType<String>();
      return names.isEmpty ? null : names.join(', ');
    }
    return _string(raw);
  }

  // ─── Primitive coercion ─────────────────────────────────────────────────
  // Feed values arrive as strings, numbers or empty strings interchangeably
  // depending on the dealer's DMS.

  static Map<String, dynamic> _map(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  static String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    // Dealer feeds send prices as "$25,000.00" as often as they send numbers.
    final cleaned = value.toString().replaceAll(RegExp(r'[^0-9.\-]'), '');
    return cleaned.isEmpty ? null : double.tryParse(cleaned);
  }

  static int? _toInt(dynamic value) => _toDouble(value)?.round();

  static DateTime? _toDate(dynamic value) {
    final seconds = _toInt(value);
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }

  static List<String> _urls(dynamic value) {
    if (value is List) {
      return value.map(_string).whereType<String>().toList();
    }
    final raw = _string(value);
    if (raw == null) return const [];
    return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.map(_string).whereType<String>().toList();
  }

  /// Descriptions may contain HTML; the detail screen renders plain text.
  static String? _text(String? raw) {
    if (raw == null) return null;
    final unescaped = raw
        .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .trim();
    return unescaped.isEmpty ? null : unescaped;
  }
}
