/// One adoptable animal from a shelter's feed. Never stored as browsable data:
/// the Pets category renders the live feed, and an animal becomes a
/// `market_items` shadow row only when someone messages the shelter about it
/// (migration 088).
///
/// The search feed carries the identity fields; the rest are filled in by the
/// per-animal details call and are null until then.
class ShelterAnimal {
  /// The `dealer_sources.source` key the shelter's messages route through.
  final String source;

  /// The shelter system's own id for the animal.
  final String animalId;

  final String name;

  /// `Dog`, `Cat`, … as the shelter words it.
  final String species;
  final String? sex;
  final String? primaryBreed;
  final String? secondaryBreed;

  /// `Baby`, `Young`, `Adult` or `Senior`. The numeric age in the feed is
  /// mostly left at zero by the shelter, so the group is what is shown.
  final String? ageGroup;

  /// Spayed or neutered.
  final bool? altered;
  final bool onHold;
  final List<String> photos;

  // ─── Details only ───────────────────────────────────────────────────────
  /// Adoption fee. Null when the shelter has not set one.
  final double? fee;

  /// When the animal last came into the shelter: its listing date, which is
  /// what places it among community listings in the Pets list.
  final DateTime? intakeDate;
  final String? description;
  final String? size;
  final List<String> colors;
  final String? housetrained;
  final String? shelterName;
  final String? livedWithChildren;
  final String? livedWithAnimals;

  /// Free-text compatibility notes the shelter fills in (no dogs, no kids, …).
  final List<String> notes;

  const ShelterAnimal({
    required this.source,
    required this.animalId,
    required this.name,
    required this.species,
    this.sex,
    this.primaryBreed,
    this.secondaryBreed,
    this.ageGroup,
    this.altered,
    this.onHold = false,
    this.photos = const [],
    this.fee,
    this.intakeDate,
    this.description,
    this.size,
    this.colors = const [],
    this.housetrained,
    this.shelterName,
    this.livedWithChildren,
    this.livedWithAnimals,
    this.notes = const [],
  });

  /// Stable across sources, and the `market_items.external_id` the shadow row
  /// is keyed on.
  String get externalId => '$source:$animalId';

  /// `Domestic Shorthair Mix`, `Labrador Retriever / Boxer`, or the species
  /// when the shelter gave no breed.
  String get breedLabel {
    final primary = primaryBreed;
    if (primary == null) return species;
    final secondary = secondaryBreed;
    if (secondary == null) return primary;
    if (secondary.toLowerCase() != 'mix') return '$primary / $secondary';
    // "Mixed Breed Mix" says the same thing twice.
    return primary.toLowerCase().contains('mix') ? primary : '$primary Mix';
  }

  /// `Female · Domestic Shorthair Mix · Adult`.
  String get summary =>
      [sex, breedLabel, ageGroup].whereType<String>().join(' · ');

  String? get firstPhotoUrl => photos.isNotEmpty ? photos.first : null;

  /// The shelter's fee when it has one; a missing or zero fee is not "free" —
  /// shelters often just do not publish it.
  String? get displayFee {
    final value = fee;
    if (value == null || value <= 0) return null;
    return value == value.roundToDouble()
        ? '\$${value.round()}'
        : '\$${value.toStringAsFixed(2)}';
  }

  /// [details] wins wherever it has a value; the search row fills the gaps.
  ShelterAnimal mergeDetails(ShelterAnimal details) {
    return ShelterAnimal(
      source: source,
      animalId: animalId,
      name: details.name,
      species: details.species,
      sex: details.sex ?? sex,
      primaryBreed: details.primaryBreed ?? primaryBreed,
      secondaryBreed: details.secondaryBreed ?? secondaryBreed,
      ageGroup: details.ageGroup ?? ageGroup,
      altered: details.altered ?? altered,
      onHold: details.onHold,
      photos: details.photos.isNotEmpty ? details.photos : photos,
      fee: details.fee,
      intakeDate: details.intakeDate,
      description: details.description,
      size: details.size,
      colors: details.colors,
      housetrained: details.housetrained,
      shelterName: details.shelterName,
      livedWithChildren: details.livedWithChildren,
      livedWithAnimals: details.livedWithAnimals,
      notes: details.notes,
    );
  }

  /// The snapshot `create_or_get_sourced_item_inquiry` stores in the shadow
  /// row, which is what the conversation shows once the animal is adopted.
  Map<String, dynamic> toInquirySnapshot() {
    return {
      'title': '$name – $breedLabel',
      'description': description,
      'price': fee ?? 0,
      'location': shelterName,
      'images': photos.join(','),
      'category': 'pets',
    };
  }
}
