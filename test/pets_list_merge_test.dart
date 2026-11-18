import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/modules/market/market_item.dart';
import 'package:mvc_app/modules/market/pets/pets_list_merge.dart';
import 'package:mvc_app/modules/market/pets/shelter_animal.dart';

MarketItem _item(String id, int day) => MarketItem(
  id: id,
  category: 'pets',
  title: id,
  price: 0,
  createdBy: 'seller',
  createdAt: DateTime(2026, 10, day),
  updatedAt: DateTime(2026, 10, day),
);

ShelterAnimal _animal(String id, int? day) => ShelterAnimal(
  source: 'petango',
  animalId: id,
  name: id,
  species: 'Dog',
  intakeDate: day == null ? null : DateTime(2026, 10, day),
);

/// Row ids, whichever kind each row is.
List<String> _ids(List<Object> rows) => [
  for (final row in rows)
    switch (row) {
      final MarketItem item => item.id,
      final ShelterAnimal animal => animal.animalId,
      _ => '?',
    },
];

void main() {
  test('interleaves animals and items newest first', () {
    final rows = mergePetsList(
      items: [_item('i20', 20), _item('i10', 10)],
      animals: [_animal('a05', 5), _animal('a25', 25), _animal('a15', 15)],
      itemsComplete: true,
    );
    expect(_ids(rows), ['a25', 'i20', 'a15', 'i10', 'a05']);
  });

  test('an animal older than every loaded page waits for the next page', () {
    final rows = mergePetsList(
      items: [_item('i20', 20), _item('i10', 10)],
      animals: [_animal('a15', 15), _animal('a05', 5)],
      itemsComplete: false,
    );
    expect(_ids(rows), ['i20', 'a15', 'i10']);
  });

  test('an animal dated the same day as the oldest loaded item is placed', () {
    final rows = mergePetsList(
      items: [_item('i10', 10)],
      animals: [_animal('a10', 10)],
      itemsComplete: false,
    );
    // A tie goes to the community listing.
    expect(_ids(rows), ['i10', 'a10']);
  });

  test('undated animals go last, and only once every page is in', () {
    final partial = mergePetsList(
      items: [_item('i10', 10)],
      animals: [_animal('nodate', null), _animal('a20', 20)],
      itemsComplete: false,
    );
    expect(_ids(partial), ['a20', 'i10']);

    final complete = mergePetsList(
      items: [_item('i10', 10)],
      animals: [_animal('nodate', null), _animal('a20', 20)],
      itemsComplete: true,
    );
    expect(_ids(complete), ['a20', 'i10', 'nodate']);
  });

  test('with no community listings every animal shows', () {
    final rows = mergePetsList(
      items: const [],
      animals: [_animal('b', 3), _animal('a', 3), _animal('c', 9)],
      itemsComplete: true,
    );
    // Same-day animals keep the shelter's order.
    expect(_ids(rows), ['c', 'b', 'a']);
  });
}
