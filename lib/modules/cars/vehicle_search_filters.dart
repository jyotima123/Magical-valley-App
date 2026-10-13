import 'package:flutter/material.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';

/// Filter + sort criteria built on [CarsSearchScreen] and applied client-side
/// to the listings loaded by [CarsVehiclesScreen].
class VehicleSearchFilters {
  static const RangeValues defaultYearRange = RangeValues(2010, 2025);
  static const RangeValues defaultPriceRange = RangeValues(0, 80000);
  static const RangeValues defaultMileageRange = RangeValues(0, 150000);
  static const double priceAnyCeiling = 200000;
  static const double mileageAnyCeiling = 300000;
  static const String sellerTypeDealer = 'Dealer';
  static const String sellerTypePrivate = 'Private Seller';
  static const List<String> sellerTypeOptions = [
    sellerTypeDealer,
    sellerTypePrivate,
  ];

  Set<String> brands;
  Set<String> models;
  String trim;
  RangeValues yearRange;
  Set<int> specificYears;
  RangeValues priceRange;
  RangeValues mileageRange;
  Set<String> bodyTypes;
  Set<String> fuelTypes;
  Set<String> transmissions;
  Set<String> driveTypes;
  Set<String> engineSizes;
  Set<String> steering;
  Set<int> doors;
  Set<String> colors;
  Set<String> features;
  Set<String> conditions;

  /// Subset of [sellerTypeDealer] / [sellerTypePrivate]. Empty means both.
  Set<String> sellerTypes;
  String sortBy;

  VehicleSearchFilters({
    Set<String>? brands,
    Set<String>? models,
    this.trim = '',
    this.yearRange = defaultYearRange,
    Set<int>? specificYears,
    this.priceRange = defaultPriceRange,
    this.mileageRange = defaultMileageRange,
    Set<String>? bodyTypes,
    Set<String>? fuelTypes,
    Set<String>? transmissions,
    Set<String>? driveTypes,
    Set<String>? engineSizes,
    Set<String>? steering,
    Set<int>? doors,
    Set<String>? colors,
    Set<String>? features,
    Set<String>? conditions,
    Set<String>? sellerTypes,
    this.sortBy = 'Most Relevant',
  })  : brands = brands ?? {},
        models = models ?? {},
        specificYears = specificYears ?? {},
        bodyTypes = bodyTypes ?? {},
        fuelTypes = fuelTypes ?? {},
        transmissions = transmissions ?? {},
        driveTypes = driveTypes ?? {},
        engineSizes = engineSizes ?? {},
        steering = steering ?? {},
        doors = doors ?? {},
        colors = colors ?? {},
        features = features ?? {},
        conditions = conditions ?? {},
        sellerTypes = sellerTypes ?? {};

  int get activeCount {
    int count = 0;
    count += brands.length;
    if (models.isNotEmpty) count++;
    if (trim.trim().isNotEmpty) count++;
    if (yearRange != defaultYearRange) count++;
    if (specificYears.isNotEmpty) count++;
    if (priceRange != defaultPriceRange) count++;
    if (mileageRange != defaultMileageRange) count++;
    count += bodyTypes.length;
    count += fuelTypes.length;
    count += transmissions.length;
    count += driveTypes.length;
    count += engineSizes.length;
    count += steering.length;
    count += doors.length;
    count += colors.length;
    count += features.length;
    count += conditions.length;
    count += sellerTypes.length;
    if (sortBy != 'Most Relevant') count++;
    return count;
  }

  bool get isEmpty => activeCount == 0;

  bool matches(VehicleListing v) {
    if (sellerTypes.isNotEmpty) {
      final type = v.isFromDealerFeed ? sellerTypeDealer : sellerTypePrivate;
      if (!sellerTypes.contains(type)) return false;
    }
    if (brands.isNotEmpty && !brands.any((b) => _eq(v.make, b))) {
      return false;
    }
    if (models.isNotEmpty && !models.any((m) => _eq(v.model, m))) return false;

    final trimQuery = trim.trim().toLowerCase();
    if (trimQuery.isNotEmpty &&
        !(v.trim ?? '').toLowerCase().contains(trimQuery)) {
      return false;
    }

    // Specific years take priority over the range slider.
    if (specificYears.isNotEmpty) {
      if (!specificYears.contains(v.year)) return false;
    } else if (yearRange != defaultYearRange) {
      if (v.year < yearRange.start.round() || v.year > yearRange.end.round()) {
        return false;
      }
    }

    if (priceRange != defaultPriceRange) {
      final price = v.promotion != null && v.promotion! > 0
          ? v.promotion!
          : v.price;
      if (price < priceRange.start) return false;
      if (priceRange.end < priceAnyCeiling && price > priceRange.end) {
        return false;
      }
    }

    if (mileageRange != defaultMileageRange) {
      if (v.mileage < mileageRange.start) return false;
      if (mileageRange.end < mileageAnyCeiling &&
          v.mileage > mileageRange.end) {
        return false;
      }
    }

    if (bodyTypes.isNotEmpty &&
        !bodyTypes.any((b) => _eq(v.body ?? '', b))) {
      return false;
    }
    if (fuelTypes.isNotEmpty &&
        !fuelTypes.any((f) => _eq(v.fuel ?? '', f))) {
      return false;
    }
    if (transmissions.isNotEmpty &&
        !transmissions.any((t) => _eq(v.transmission ?? '', t))) {
      return false;
    }
    if (colors.isNotEmpty && !colors.any((c) => _eq(v.color ?? '', c))) {
      return false;
    }

    if (doors.isNotEmpty) {
      final d = int.tryParse(v.doors ?? '');
      if (d == null) return false;
      // The "5+" chip is stored as 5 and matches any door count >= 5.
      final ok = doors.any((sel) => sel == 5 ? d >= 5 : d == sel);
      if (!ok) return false;
    }

    // Free-form criteria without a dedicated column are matched against the
    // listing's descriptive text.
    final fuzzy = [
      ...driveTypes,
      ...engineSizes,
      ...steering,
      ...features,
      ...conditions,
    ];
    if (fuzzy.isNotEmpty) {
      final haystack = _haystack(v);
      for (final term in fuzzy) {
        if (!haystack.contains(_loose(term))) return false;
      }
    }

    return true;
  }

  /// Sorts [listings] in place according to [sortBy].
  /// 'Most Relevant' keeps the incoming order, which is every provider's
  /// inventory merged newest first — see [VehicleProviders.mergeNewestFirst].
  void sort(List<VehicleListing> listings) {
    double effectivePrice(VehicleListing v) =>
        v.promotion != null && v.promotion! > 0 ? v.promotion! : v.price;

    switch (sortBy) {
      case 'Newest Listing':
        listings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case 'Lowest Price':
        listings.sort(
            (a, b) => effectivePrice(a).compareTo(effectivePrice(b)));
      case 'Highest Price':
        listings.sort(
            (a, b) => effectivePrice(b).compareTo(effectivePrice(a)));
      case 'Lowest Mileage':
        listings.sort((a, b) => a.mileage.compareTo(b.mileage));
      case 'Newest Year':
        listings.sort((a, b) => b.year.compareTo(a.year));
      case 'Oldest Year':
        listings.sort((a, b) => a.year.compareTo(b.year));
    }
  }

  static bool _eq(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Built once per listing: dealer vehicles carry a full description plus a
  /// few hundred option strings, and [matches] runs on every keystroke.
  /// Entries are discarded with the listings themselves on the next load.
  static final Expando<String> _haystackCache = Expando<String>();

  static String _haystack(VehicleListing v) {
    final cached = _haystackCache[v];
    if (cached != null) return cached;

    final built = _loose([
      v.description,
      v.engineType,
      v.engineOptions,
      v.packageOptions,
      v.transmissionOptions,
      v.addonsDescription,
      v.trim,
      v.body,
      v.drivetrain,
      ...v.features,
    ].whereType<String>().join(' '));
    _haystackCache[v] = built;
    return built;
  }

  /// Lowercases and drops the spacing that separates our chip labels from the
  /// same value in a dealer feed ('Apple CarPlay / Android Auto' vs
  /// 'Apple CarPlay/Android Auto').
  static String _loose(String value) => value
      .toLowerCase()
      .replaceAllMapped(RegExp(r'\s*([/–-])\s*'), (m) => m[1]!);
}
