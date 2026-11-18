import 'package:flutter_test/flutter_test.dart';
import 'package:mvc_app/modules/market/pets/petango_api_service.dart';
import 'package:mvc_app/modules/market/pets/shelter_animal.dart';

/// Trimmed from a live `AdoptableSearch` response. Empty fields arrive as
/// whitespace-only elements, which is most of what the mapper has to handle.
const _search = '''<?xml version="1.0" encoding="utf-8"?>
<ArrayOfXmlNode xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns="http://www.petango.com/">
  <XmlNode>
    <adoptableSearch xmlns="">
      <ID>61814626</ID>
      <Name>Opera</Name>
      <Species>Cat</Species>
      <Sex>Female</Sex>
      <PrimaryBreed>Domestic Shorthair</PrimaryBreed>
      <SecondaryBreed>Mix</SecondaryBreed>
      <SN>Spayed</SN>
      <Age>0</Age>
      <Photo>https://g.petango.com/photos/3206/9f848fc8.jpg</Photo>
      <Location>Cat Room</Location>
      <OnHold>No</OnHold>
      <SpecialNeeds>
      </SpecialNeeds>
      <NoDogs>
      </NoDogs>
      <MemoList />
      <BehaviorTestList>
      </BehaviorTestList>
      <Stage>Available</Stage>
      <AgeGroup>Adult</AgeGroup>
    </adoptableSearch>
  </XmlNode>
  <XmlNode>
    <adoptableSearch xmlns="">
      <ID>61817139</ID>
      <Name>TORTA</Name>
      <Species>Dog</Species>
      <Sex>Male</Sex>
      <PrimaryBreed>Labrador Retriever</PrimaryBreed>
      <SecondaryBreed>Boxer</SecondaryBreed>
      <SN>
      </SN>
      <Photo>
      </Photo>
      <OnHold>Yes</OnHold>
      <NoKids>Yes</NoKids>
      <AgeGroup>Baby</AgeGroup>
    </adoptableSearch>
  </XmlNode>
  <XmlNode>
    <adoptableSearch xmlns="">
      <ID>61814626</ID>
      <Name>Opera</Name>
      <Species>Cat</Species>
    </adoptableSearch>
  </XmlNode>
  <XmlNode>
    <adoptableSearch xmlns="">
      <ID>
      </ID>
      <Name>Nameless</Name>
    </adoptableSearch>
  </XmlNode>
</ArrayOfXmlNode>''';

/// Trimmed from a live `AdoptableDetails` response for the first animal above.
const _details = '''<?xml version="1.0" encoding="utf-8"?>
<adoptableDetails>
  <CompanyID>3206</CompanyID>
  <ID>61814626</ID>
  <AnimalName>Opera</AnimalName>
  <Species>Cat</Species>
  <Sex>Female</Sex>
  <Altered>Yes</Altered>
  <PrimaryBreed>Domestic Shorthair</PrimaryBreed>
  <SecondaryBreed>Mix</SecondaryBreed>
  <PrimaryColor>Black</PrimaryColor>
  <SecondaryColor>White</SecondaryColor>
  <Size>M</Size>
  <Housetrained>Unknown</Housetrained>
  <Price>0.00</Price>
  <LastIntakeDate>2026-09-28 18:00:00</LastIntakeDate>
  <Dsc>Loves &lt;b&gt;naps&lt;/b&gt;.&lt;br/&gt;Shy at first.</Dsc>
  <Photo1>https://g.petango.com/photos/3206/9f848fc8.jpg</Photo1>
  <Photo2>https://g.petango.com/photos/3206/271fa8d5.jpg</Photo2>
  <Photo3>
  </Photo3>
  <OnHold>No</OnHold>
  <SpecialNeeds>
  </SpecialNeeds>
  <NoCats>Yes</NoCats>
  <MemoList />
  <Site>Twin Falls Animal Shelter</Site>
  <LivedWithChildren>No</LivedWithChildren>
  <AgeGroup>Adult</AgeGroup>
  <ColorPattern>Tuxedo</ColorPattern>
</adoptableDetails>''';

void main() {
  group('PetangoAnimalMapper.parseSearch', () {
    late List<ShelterAnimal> animals;

    setUp(() {
      animals = PetangoAnimalMapper.parseSearch(_search, source: 'petango');
    });

    test('drops duplicates and records without an id', () {
      expect(animals.map((a) => a.animalId), ['61814626', '61817139']);
    });

    test('reads identity, breed and age group', () {
      final opera = animals.first;
      expect(opera.externalId, 'petango:61814626');
      expect(opera.name, 'Opera');
      expect(opera.species, 'Cat');
      expect(opera.breedLabel, 'Domestic Shorthair Mix');
      expect(opera.summary, 'Female · Domestic Shorthair Mix · Adult');
      expect(opera.altered, isTrue);
      expect(opera.onHold, isFalse);
      expect(opera.photos, ['https://g.petango.com/photos/3206/9f848fc8.jpg']);
    });

    test('treats whitespace-only elements as missing', () {
      final torta = animals.last;
      expect(torta.altered, isNull);
      expect(torta.photos, isEmpty);
      expect(torta.firstPhotoUrl, isNull);
    });

    test('normalizes shouted names, cross breeds and flags', () {
      final torta = animals.last;
      expect(torta.name, 'Torta');
      expect(torta.breedLabel, 'Labrador Retriever / Boxer');
      expect(torta.onHold, isTrue);
      expect(torta.notes, ['No young children']);
    });

    test('reads catalogue-style breeds the way people say them', () {
      ShelterAnimal withBreed(String breed) => PetangoAnimalMapper.fromFields({
        'ID': '1',
        'Name': 'Rex',
        'PrimaryBreed': breed,
        'SecondaryBreed': 'Mix',
      }, source: 'petango')!;

      expect(withBreed('Terrier, Pit Bull').breedLabel, 'Pit Bull Terrier Mix');
      expect(withBreed('Bulldog, French').breedLabel, 'French Bulldog Mix');
      expect(
        withBreed('Mixed Breed, Medium (up to 44 lbs fully grown)').breedLabel,
        'Medium Mixed Breed',
      );
    });

    test('rejects a body that is not XML', () {
      expect(
        () => PetangoAnimalMapper.parseSearch('Access denied.', source: 'p'),
        throwsA(isA<PetangoException>()),
      );
    });
  });

  group('PetangoAnimalMapper.parseDetails', () {
    late ShelterAnimal opera;

    setUp(() {
      final search = PetangoAnimalMapper.parseSearch(
        _search,
        source: 'petango',
      ).first;
      final details = PetangoAnimalMapper.parseDetails(
        _details,
        source: 'petango',
      );
      opera = search.mergeDetails(details!);
    });

    test('collects every photo once, in order', () {
      expect(opera.photos, [
        'https://g.petango.com/photos/3206/9f848fc8.jpg',
        'https://g.petango.com/photos/3206/271fa8d5.jpg',
      ]);
    });

    test('maps size, colours and housetrained "Unknown"', () {
      expect(opera.size, 'Medium');
      expect(opera.colors, ['Black', 'White', 'Tuxedo']);
      expect(opera.housetrained, isNull);
      expect(opera.shelterName, 'Twin Falls Animal Shelter');
      expect(opera.livedWithChildren, 'No');
      expect(opera.notes, ['No cats']);
    });

    test('reads the intake date as the listing date', () {
      expect(opera.intakeDate, DateTime(2026, 9, 28, 18));
    });

    test('strips HTML from the description', () {
      expect(opera.description, 'Loves naps.\nShy at first.');
    });

    test('a zero fee is unpublished, not free', () {
      expect(opera.fee, 0);
      expect(opera.displayFee, isNull);
    });

    test('the inquiry snapshot describes the animal for the inbox', () {
      final snapshot = opera.toInquirySnapshot();
      expect(snapshot['title'], 'Opera – Domestic Shorthair Mix');
      expect(snapshot['category'], 'pets');
      expect(snapshot['location'], 'Twin Falls Animal Shelter');
      expect(
        snapshot['images'],
        'https://g.petango.com/photos/3206/9f848fc8.jpg,'
        'https://g.petango.com/photos/3206/271fa8d5.jpg',
      );
    });
  });
}
