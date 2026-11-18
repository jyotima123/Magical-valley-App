import 'package:mvc_app/modules/market/market_item.dart';
import 'package:mvc_app/modules/market/pets/shelter_animal.dart';

/// Pets as one newest-first list: community listings by when they were
/// listed, shelter animals by when they came into the shelter. Each row is a
/// [MarketItem] or a [ShelterAnimal].
///
/// Community listings arrive a page at a time, so an animal is only placed
/// once the loaded pages reach back to its date; until then it waits for a
/// later page. Otherwise loading more would slot rows in above ones the user
/// has already scrolled past. [itemsComplete] is false while more pages remain.
///
/// An animal with no date — its record failed to load — has nothing to sort
/// by and goes at the very end, once every page is in.
///
/// On a tie the community listing comes first, and animals keep the shelter's
/// own order among themselves.
List<Object> mergePetsList({
  required List<MarketItem> items,
  required List<ShelterAnimal> animals,
  required bool itemsComplete,
}) {
  final indexed = [
    for (var i = 0; i < animals.length; i++) (position: i, animal: animals[i]),
  ];
  final dated = indexed.where((e) => e.animal.intakeDate != null).toList()
    ..sort((a, b) {
      final byDate = b.animal.intakeDate!.compareTo(a.animal.intakeDate!);
      return byDate != 0 ? byDate : a.position.compareTo(b.position);
    });
  final undated = indexed.where((e) => e.animal.intakeDate == null);

  final oldestLoaded = items.isEmpty ? null : items.last.createdAt;
  bool reached(DateTime date) =>
      itemsComplete || (oldestLoaded != null && !date.isBefore(oldestLoaded));

  final rows = <Object>[];
  var next = 0;
  for (final item in items) {
    while (next < dated.length &&
        dated[next].animal.intakeDate!.isAfter(item.createdAt)) {
      rows.add(dated[next++].animal);
    }
    rows.add(item);
  }
  while (next < dated.length && reached(dated[next].animal.intakeDate!)) {
    rows.add(dated[next++].animal);
  }
  if (itemsComplete) rows.addAll(undated.map((e) => e.animal));
  return rows;
}
