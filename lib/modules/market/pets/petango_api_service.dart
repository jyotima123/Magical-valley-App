import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:mvc_app/modules/market/pets/shelter_animal.dart';
import 'package:mvc_app/utils/logging_utils.dart';
import 'package:xml/xml.dart';

/// Thrown when the shelter feed cannot be read. The Pets category hides the
/// shelter carousel rather than showing an error: community listings still
/// render when the shelter's feed is down.
class PetangoException implements Exception {
  final String message;
  final int? statusCode;

  const PetangoException(this.message, {this.statusCode});

  @override
  String toString() => 'PetangoException($statusCode): $message';
}

/// Read-only client for PetPoint's adoption web service (Petango), which
/// publishes a shelter's adoptable animals.
///
/// It is an ASP.NET .asmx service: plain GETs, XML back, and every declared
/// parameter must be present even when it means "any". One auth key belongs to
/// one shelter, so the key alone decides whose animals come back.
class PetangoApiService {
  static const String _baseUrl =
      'https://ws.petango.com/webservices/wsAdoption.asmx';
  static const String _logTag = 'PETANGO';

  /// The `dealer_sources.source` key the shelter's messages route through
  /// (migration 088).
  static const String source = 'petango';

  /// The animals change a few times a day at most, so a short cache keeps
  /// reopening Pets from refetching the whole shelter.
  static const Duration cacheTtl = Duration(minutes: 10);

  /// Details requests in flight at once. The search carries no date, so every
  /// animal's record is fetched to place it in the list; a shelter lists tens
  /// of animals, not thousands.
  static const int _detailsConcurrency = 6;

  final Dio _dio;

  PetangoApiService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: _baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.plain,
            ),
          );

  static List<ShelterAnimal>? _cached;
  static DateTime? _cachedAt;
  static final Map<String, ShelterAnimal> _details = {};

  /// Environments without a `PETANGO_KEY` simply have no shelter carousel.
  static String? get _authKey {
    final key = dotenv.env['PETANGO_KEY']?.trim();
    return (key == null || key.isEmpty) ? null : key;
  }

  static bool get isConfigured => _authKey != null;

  static bool get _cacheIsFresh =>
      _cached != null &&
      _cachedAt != null &&
      DateTime.now().difference(_cachedAt!) < cacheTtl;

  /// Drops every cached animal. Exposed for tests and for a forced reload.
  static void clearCache() {
    _cached = null;
    _cachedAt = null;
    _details.clear();
  }

  /// Every adoptable animal the shelter lists, each with its full record
  /// (fee, photos, intake date), in the shelter's order.
  ///
  /// An animal whose record fails to load is still returned, with only what
  /// the search had; it just has no date to sort by.
  ///
  /// Returns an empty list when no key is configured. Throws
  /// [PetangoException] when the service is reachable but unusable.
  Future<List<ShelterAnimal>> fetchAnimals({bool forceRefresh = false}) async {
    final authKey = _authKey;
    if (authKey == null) {
      infoLog('No PETANGO_KEY configured; skipping shelter feed', tag: _logTag);
      return const [];
    }

    if (!forceRefresh && _cacheIsFresh) return _cached!;

    final body = await _get('/AdoptableSearch', {
      'authkey': authKey,
      // "Any" for every filter: the app filters nothing the shelter lists.
      'speciesID': '0',
      'sex': 'A',
      'ageGroup': 'All',
      'location': '',
      'site': '',
      'onHold': 'A',
      'orderBy': 'ID',
      'primaryBreed': 'All',
      'secondaryBreed': 'All',
      'specialNeeds': 'A',
      'noDogs': 'A',
      'noCats': 'A',
      'noKids': 'A',
      'stageID': '',
    });

    final found = PetangoAnimalMapper.parseSearch(body, source: source);
    if (forceRefresh) _details.clear();

    final animals = <ShelterAnimal>[];
    for (var i = 0; i < found.length; i += _detailsConcurrency) {
      final batch = found.skip(i).take(_detailsConcurrency);
      animals.addAll(
        await Future.wait(
          batch.map(
            (animal) => fetchDetails(animal).catchError(
              (Object _) => animal,
              test: (e) => e is PetangoException,
            ),
          ),
        ),
      );
    }

    successLog('Loaded ${animals.length} shelter animals', tag: _logTag);
    _cached = List.unmodifiable(animals);
    _cachedAt = DateTime.now();
    return _cached!;
  }

  /// The full record for one animal: fee, description, every photo.
  Future<ShelterAnimal> fetchDetails(ShelterAnimal animal) async {
    final cached = _details[animal.animalId];
    if (cached != null) return cached;

    final authKey = _authKey;
    if (authKey == null) return animal;

    final body = await _get('/AdoptableDetails', {
      'animalID': animal.animalId,
      'authkey': authKey,
    });

    final details = PetangoAnimalMapper.parseDetails(body, source: source);
    if (details == null) {
      throw const PetangoException(
        'The shelter returned an unreadable record.',
      );
    }
    return _details[animal.animalId] = animal.mergeDetails(details);
  }

  Future<String> _get(String path, Map<String, String> params) async {
    try {
      final response = await _dio.get<String>(path, queryParameters: params);
      return response.data ?? '';
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      errorLog('Shelter feed request failed', tag: _logTag, error: e);
      throw PetangoException(_messageForStatus(status, e), statusCode: status);
    }
  }

  static String _messageForStatus(int? status, DioException e) {
    switch (status) {
      // The service answers a wrong key with a bare "Access denied."
      case 401:
      case 403:
        return 'The shelter feed key was rejected.';
      case 404:
        return 'This animal is no longer listed.';
      default:
        if (e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.connectionError) {
          return 'Could not reach the shelter. Check your connection.';
        }
        return 'Could not load the shelter\'s animals.';
    }
  }
}

/// Translates Petango's XML into [ShelterAnimal]s.
///
/// Kept apart from the transport so the field handling can be exercised
/// without a network call. Empty elements arrive as whitespace, and "unknown"
/// is spelled several ways, so every value goes through [_value].
class PetangoAnimalMapper {
  /// The `AdoptableSearch` response: one `<adoptableSearch>` per animal.
  static List<ShelterAnimal> parseSearch(String xml, {required String source}) {
    final document = _parse(xml);
    final seen = <String>{};
    return document
        .findAllElements('adoptableSearch')
        .map((e) => fromFields(_fields(e), source: source))
        .whereType<ShelterAnimal>()
        // An animal listed twice would key two carousel pages identically.
        .where((animal) => seen.add(animal.animalId))
        .toList();
  }

  /// The `AdoptableDetails` response: a single `<adoptableDetails>`.
  static ShelterAnimal? parseDetails(String xml, {required String source}) {
    final root = _parse(xml).findAllElements('adoptableDetails').firstOrNull;
    return root == null ? null : fromFields(_fields(root), source: source);
  }

  /// Builds an animal from one record's child elements. Search and details
  /// spell a few fields differently (`Name` vs `AnimalName`, `Photo` vs
  /// `Photo1..3`, `SN` vs `Altered`); both are read.
  ///
  /// Returns null when the record lacks an id or a name.
  static ShelterAnimal? fromFields(
    Map<String, String> f, {
    required String source,
  }) {
    final id = _value(f['ID']);
    final name = _value(f['AnimalName']) ?? _value(f['Name']);
    if (id == null || name == null) return null;

    // Search has `Photo`, details `Photo1..3` with `Photo1` the same image.
    final photos = <String>{
      for (final key in ['Photo1', 'Photo2', 'Photo3', 'Photo'])
        ?_value(f[key]),
    }.toList();

    return ShelterAnimal(
      source: source,
      animalId: id,
      name: _titleCase(name),
      species: _value(f['Species']) ?? _value(f['AnimalType']) ?? 'Animal',
      sex: _value(f['Sex']),
      primaryBreed: _breed(_value(f['PrimaryBreed'])),
      secondaryBreed: _breed(_value(f['SecondaryBreed'])),
      ageGroup: _value(f['AgeGroup']),
      altered: _altered(f),
      onHold: _yes(f['OnHold']),
      photos: photos,
      fee: double.tryParse(_value(f['Price']) ?? ''),
      intakeDate: _date(_value(f['LastIntakeDate'])),
      description: _text(_value(f['Dsc'])),
      size: _size(_value(f['Size'])),
      colors: [
        ?_value(f['PrimaryColor']),
        ?_value(f['SecondaryColor']),
        ?_value(f['ColorPattern']),
      ],
      housetrained: _value(f['Housetrained']),
      shelterName: _value(f['Site']),
      livedWithChildren: _value(f['LivedWithChildren']),
      livedWithAnimals: _value(f['LivedWithAnimals']),
      notes: [
        if (_yes(f['NoDogs'])) 'No dogs',
        if (_yes(f['NoCats'])) 'No cats',
        if (_yes(f['NoKids'])) 'No young children',
        if (_value(f['SpecialNeeds']) case final needs? when !_isNo(needs))
          'Special needs: $needs',
      ],
    );
  }

  static XmlDocument _parse(String xml) {
    try {
      return XmlDocument.parse(xml);
    } on XmlException {
      throw const PetangoException(
        'The shelter feed returned unreadable data.',
      );
    }
  }

  /// A record's direct children by element name. Nested lists (memos,
  /// behaviour tests) are not used and would only add noise.
  static Map<String, String> _fields(XmlElement record) => {
    for (final child in record.childElements)
      if (child.childElements.isEmpty) child.localName: child.innerText,
  };

  static String? _value(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    return switch (text.toLowerCase()) {
      'unknown' || 'n/a' || 'none' => null,
      _ => text,
    };
  }

  static bool _yes(String? raw) => switch (_value(raw)?.toLowerCase()) {
    'yes' || 'y' || 'true' => true,
    _ => false,
  };

  static bool _isNo(String raw) =>
      const {'no', 'n', 'false'}.contains(raw.toLowerCase());

  /// Search says `SN: Spayed/Neutered`, details says `Altered: Yes/No`.
  static bool? _altered(Map<String, String> f) {
    final altered = _value(f['Altered']);
    if (altered != null) return _yes(altered);
    final sn = _value(f['SN'])?.toLowerCase();
    if (sn == null) return null;
    return sn == 'spayed' || sn == 'neutered';
  }

  /// PetPoint files breeds the way a catalogue would: `Terrier, Pit Bull`,
  /// `Mixed Breed, Medium (up to 44 lbs fully grown)`. Read aloud they are
  /// `Pit Bull Terrier` and `Medium Mixed Breed`.
  static String? _breed(String? raw) {
    if (raw == null) return null;
    final bare = raw.replaceAll(RegExp(r'\s*\(.*?\)'), '').trim();
    final comma = bare.indexOf(',');
    if (comma < 0) return bare;
    final family = bare.substring(0, comma).trim();
    final variety = bare.substring(comma + 1).trim();
    return variety.isEmpty ? family : '$variety $family';
  }

  /// `2026-09-28 18:00:00`, in the shelter's local time.
  static DateTime? _date(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw.replaceFirst(' ', 'T'));

  static String? _size(String? raw) => switch (raw?.toUpperCase()) {
    null => null,
    'S' => 'Small',
    'M' => 'Medium',
    'L' => 'Large',
    'XL' => 'Extra large',
    _ => raw,
  };

  /// Some shelters type names in capitals; `MAX` reads as shouting on a card.
  static String _titleCase(String name) {
    if (name != name.toUpperCase()) return name;
    return name
        .toLowerCase()
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Descriptions may carry HTML from the shelter's editor.
  static String? _text(String? raw) {
    if (raw == null) return null;
    final text = raw
        .replaceAll(
          RegExp(r'<br\s*/?>|</p>|</div>', caseSensitive: false),
          '\n',
        )
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .trim();
    return text.isEmpty ? null : text;
  }
}
