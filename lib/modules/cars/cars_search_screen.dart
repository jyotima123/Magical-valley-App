import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/car_data.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/cars/vehicle_search_filters.dart';

class CarsSearchScreen extends StatefulWidget {
  /// Filters currently applied on the vehicles screen, used to seed the form.
  final VehicleSearchFilters? initialFilters;

  /// Loaded listings, used to preview how many vehicles match the filters.
  final List<VehicleListing> listings;

  const CarsSearchScreen({
    super.key,
    this.initialFilters,
    this.listings = const [],
  });

  @override
  State<CarsSearchScreen> createState() => _CarsSearchScreenState();
}

class _CarsSearchScreenState extends State<CarsSearchScreen> {
  // Brand / Model
  Set<String> _selectedBrands = {};
  Set<String> _selectedModels = {};

  // Trim / Version
  final _trimController = TextEditingController();

  // Year range (slider)
  RangeValues _yearRange = const RangeValues(2010, 2025);

  // Specific years (tags)
  final Set<int> _specificYears = {};
  final _yearTagController = TextEditingController();

  // Price range (USD)
  RangeValues _priceRange = const RangeValues(0, 80000);

  // Mileage range (km)
  RangeValues _mileageRange = const RangeValues(0, 150000);

  // Categorical filters
  Set<String> _selectedBodyTypes = {};
  Set<String> _selectedFuelTypes = {};
  Set<String> _selectedTransmissions = {};
  Set<String> _selectedDriveTypes = {};
  Set<String> _selectedEngineSizes = {};
  Set<String> _selectedSteering = {};
  Set<int> _selectedDoors = {};
  Set<String> _selectedColors = {};
  Set<String> _selectedFeatures = {};
  Set<String> _selectedConditions = {};
  Set<String> _selectedSellerTypes = {};

  // Sort
  String _sortBy = 'Most Relevant';

  @override
  void initState() {
    super.initState();
    final f = widget.initialFilters;
    if (f != null) {
      _selectedBrands = {...f.brands};
      _selectedModels = {...f.models};
      _trimController.text = f.trim;
      _yearRange = f.yearRange;
      _specificYears.addAll(f.specificYears);
      _priceRange = f.priceRange;
      _mileageRange = f.mileageRange;
      _selectedBodyTypes = {...f.bodyTypes};
      _selectedFuelTypes = {...f.fuelTypes};
      _selectedTransmissions = {...f.transmissions};
      _selectedDriveTypes = {...f.driveTypes};
      _selectedEngineSizes = {...f.engineSizes};
      _selectedSteering = {...f.steering};
      _selectedDoors = {...f.doors};
      _selectedColors = {...f.colors};
      _selectedFeatures = {...f.features};
      _selectedConditions = {...f.conditions};
      _selectedSellerTypes = {...f.sellerTypes};
      _sortBy = f.sortBy;
    }
  }

  VehicleSearchFilters _buildFilters() {
    return VehicleSearchFilters(
      brands: {..._selectedBrands},
      models: {..._selectedModels},
      trim: _trimController.text.trim(),
      yearRange: _yearRange,
      specificYears: {..._specificYears},
      priceRange: _priceRange,
      mileageRange: _mileageRange,
      bodyTypes: {..._selectedBodyTypes},
      fuelTypes: {..._selectedFuelTypes},
      transmissions: {..._selectedTransmissions},
      driveTypes: {..._selectedDriveTypes},
      engineSizes: {..._selectedEngineSizes},
      steering: {..._selectedSteering},
      doors: {..._selectedDoors},
      colors: {..._selectedColors},
      features: {..._selectedFeatures},
      conditions: {..._selectedConditions},
      sellerTypes: {..._selectedSellerTypes},
      sortBy: _sortBy,
    );
  }

  void _resetAll() {
    setState(() {
      _selectedBrands = {};
      _selectedModels = {};
      _trimController.clear();
      _yearRange = const RangeValues(2010, 2025);
      _specificYears.clear();
      _priceRange = const RangeValues(0, 80000);
      _mileageRange = const RangeValues(0, 150000);
      _selectedBodyTypes = {};
      _selectedFuelTypes = {};
      _selectedTransmissions = {};
      _selectedDriveTypes = {};
      _selectedEngineSizes = {};
      _selectedSteering = {};
      _selectedDoors = {};
      _selectedColors = {};
      _selectedFeatures = {};
      _selectedConditions = {};
      _selectedSellerTypes = {};
      _sortBy = 'Most Relevant';
    });
  }

  int get _activeFilterCount => _buildFilters().activeCount;

  int get _matchingCount {
    final f = _buildFilters();
    return widget.listings.where(f.matches).length;
  }

  @override
  void dispose() {
    _trimController.dispose();
    _yearTagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: AppTheme.headerBackground,
        elevation: 0,
        title: const Text(
          'Find Your Car',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.black,
          ),
        ),
        actions: [
          if (_activeFilterCount > 0)
            TextButton(
              onPressed: _resetAll,
              child: Text(
                'Reset ($_activeFilterCount)',
                style: const TextStyle(
                  color: AppTheme.accentPrimary,
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 88),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildResultsBar(),
                _buildSellerTypeSection(),
                _buildDivider(),
                _buildBrandSection(),
                _buildDivider(),
                _buildModelSection(),
                _buildDivider(),
                _buildTrimSection(),
                _buildDivider(),
                _buildYearRangeSection(),
                _buildDivider(),
                _buildSpecificYearsSection(),
                _buildDivider(),
                _buildPriceSection(),
                _buildDivider(),
                _buildMileageSection(),
                _buildDivider(),
                _buildBodyTypeSection(),
                _buildDivider(),
                _buildFuelTypeSection(),
                _buildDivider(),
                _buildTransmissionSection(),
                _buildDivider(),
                _buildDriveTypeSection(),
                _buildDivider(),
                _buildEngineSizeSection(),
                _buildDivider(),
                _buildSteeringSection(),
                _buildDivider(),
                _buildDoorsSection(),
                _buildDivider(),
                _buildColorSection(),
                _buildDivider(),
                _buildFeaturesSection(),
                _buildDivider(),
                _buildConditionSection(),
                _buildDivider(),
                _buildSortSection(),
                const SizedBox(height: 8),
              ],
            ),
          ),
          _buildSearchButton(),
        ],
      ),
    );
  }

  // ─── Results bar ───────────────────────────────────────────────────────────

  Widget _buildResultsBar() {
    final total = widget.listings.length;
    final matching = _matchingCount;
    final text = _activeFilterCount > 0
        ? '$matching of $total vehicle${total != 1 ? 's' : ''} match your filters'
        : '$total vehicle${total != 1 ? 's' : ''} available — apply filters to narrow results';
    return Container(
      color: AppTheme.accentPrimary.withOpacity(0.08),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 16, color: AppTheme.accentPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: AppTheme.accentPrimary.withOpacity(0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Brand section ─────────────────────────────────────────────────────────

  Widget _buildBrandSection() {
    return _FilterSection(
      title: 'Make',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selectedBrands.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedBrands
                  .map(
                    (brand) => _SelectedBrandBadge(
                      brand: brand,
                      onClear: () => setState(() => _deselectBrand(brand)),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
          ],
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.0,
            children: [
              ...CarData.featuredBrands.map(
                (brand) => _BrandTile(
                  brand: brand,
                  isSelected: _selectedBrands.contains(brand),
                  onTap: () => setState(() {
                    if (_selectedBrands.contains(brand)) {
                      _deselectBrand(brand);
                    } else {
                      _selectedBrands.add(brand);
                    }
                  }),
                ),
              ),
              _AllMakesTile(
                onTap: () => _showBrandPicker(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Removes [brand] plus any selected models that belong only to it — the
  /// model set is shared across every selected brand.
  void _deselectBrand(String brand) {
    _selectedBrands.remove(brand);
    final brandModels = CarData.brandModels[brand] ?? const [];
    _selectedModels.removeWhere(brandModels.contains);
  }

  Future<void> _showBrandPicker(BuildContext context) async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BrandPickerSheet(currentBrands: _selectedBrands),
    );
    if (selected != null && mounted) {
      setState(() {
        for (final brand in _selectedBrands.difference(selected)) {
          _deselectBrand(brand);
        }
        _selectedBrands = selected;
      });
    }
  }

  // ─── Model section ─────────────────────────────────────────────────────────

  Widget _buildModelSection() {
    if (_selectedBrands.isEmpty) {
      return _FilterSection(
        title: 'Model',
        child: _PlaceholderHint(
          icon: Icons.directions_car_outlined,
          text: 'Select a make above to see available models',
        ),
      );
    }

    final brands = _selectedBrands.toList();

    return _FilterSection(
      title: 'Model',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < brands.length; i++) ...[
            if (brands.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  brands[i],
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[500],
                  ),
                ),
              ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (CarData.brandModels[brands[i]] ?? []).map((model) {
                final isSelected = _selectedModels.contains(model);
                return _SelectChip(
                  label: model,
                  isSelected: isSelected,
                  onTap: () => setState(() {
                    if (isSelected) {
                      _selectedModels.remove(model);
                    } else {
                      _selectedModels.add(model);
                    }
                  }),
                );
              }).toList(),
            ),
            if (i != brands.length - 1) const SizedBox(height: 14),
          ],
        ],
      ),
    );
  }

  // ─── Trim / Version ────────────────────────────────────────────────────────

  Widget _buildTrimSection() {
    return _FilterSection(
      title: 'Trim / Version',
      child: TextField(
        controller: _trimController,
        decoration: InputDecoration(
          hintText: 'e.g. Limited, Sport, EX-L, Platinum…',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppTheme.accentPrimary),
          ),
        ),
        style: const TextStyle(fontSize: 14),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  // ─── Range edit dialog ─────────────────────────────────────────────────────

  Future<void> _showRangeDialog({
    required String title,
    required RangeValues current,
    required double min,
    required double max,
    String prefix = '',
    String suffix = '',
    required void Function(RangeValues) onConfirm,
  }) async {
    final fromCtrl = TextEditingController(text: current.start.round().toString());
    final toCtrl = TextEditingController(text: current.end.round().toString());

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: fromCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'From',
                  prefixText: prefix.isNotEmpty ? prefix : null,
                  suffixText: suffix.isNotEmpty ? suffix : null,
                  border: const OutlineInputBorder(),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.accentPrimary),
                  ),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('–', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w300)),
            ),
            Expanded(
              child: TextField(
                controller: toCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'To',
                  prefixText: prefix.isNotEmpty ? prefix : null,
                  suffixText: suffix.isNotEmpty ? suffix : null,
                  border: const OutlineInputBorder(),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.accentPrimary),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final from = double.tryParse(fromCtrl.text.trim());
              final to = double.tryParse(toCtrl.text.trim());
              if (from != null && to != null) {
                final lo = from.clamp(min, max);
                final hi = to.clamp(min, max);
                onConfirm(RangeValues(lo <= hi ? lo : hi, lo <= hi ? hi : lo));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    fromCtrl.dispose();
    toCtrl.dispose();
  }

  // ─── Year range ────────────────────────────────────────────────────────────

  Widget _buildYearRangeSection() {
    final from = _yearRange.start.round();
    final to = _yearRange.end.round();
    return _FilterSection(
      title: 'Year Range',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$from – $to',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.accentPrimary,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _showRangeDialog(
              title: 'Year Range',
              current: _yearRange,
              min: 1980,
              max: 2026,
              onConfirm: (v) => setState(() => _yearRange = v),
            ),
            child: Icon(Icons.edit, size: 14, color: AppTheme.accentPrimary.withOpacity(0.65)),
          ),
        ],
      ),
      child: RangeSlider(
        values: _yearRange,
        min: 1980,
        max: 2026,
        divisions: 46,
        activeColor: AppTheme.accentPrimary,
        inactiveColor: AppTheme.accentPrimary.withOpacity(0.15),
        labels: RangeLabels('$from', '$to'),
        onChanged: (v) => setState(() => _yearRange = v),
      ),
    );
  }

  // ─── Specific years (tags) ────────────────────────────────────────────────

  Widget _buildSpecificYearsSection() {
    return _FilterSection(
      title: 'Specific Year',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _yearTagController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'e.g. 2022',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.accentPrimary),
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () {
                  final year = int.tryParse(_yearTagController.text.trim());
                  if (year != null && year >= 1980 && year <= 2026) {
                    setState(() => _specificYears.add(year));
                    _yearTagController.clear();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentPrimary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                child: const Text('Add', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (_specificYears.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: (_specificYears.toList()..sort()).map((year) => Chip(
                    label: Text(
                      '$year',
                      style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: AppTheme.accentPrimary.withOpacity(0.12),
                    side: BorderSide(color: AppTheme.accentPrimary.withOpacity(0.3)),
                    deleteIcon: Icon(Icons.close, size: 14,
                        color: AppTheme.accentPrimary.withOpacity(0.7)),
                    onDeleted: () => setState(() => _specificYears.remove(year)),
                  )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ─── Price ─────────────────────────────────────────────────────────────────

  Widget _buildPriceSection() {
    final lo = _priceRange.start.round();
    final hi = _priceRange.end.round();
    final loStr = lo == 0 ? 'Any' : '\$${_formatNumber(lo)}';
    final hiStr = hi == 200000 ? 'Any' : '\$${_formatNumber(hi)}';
    return _FilterSection(
      title: 'Price',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$loStr – $hiStr',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.accentPrimary,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _showRangeDialog(
              title: 'Price Range',
              current: _priceRange,
              min: 0,
              max: 200000,
              prefix: '\$',
              onConfirm: (v) => setState(() => _priceRange = v),
            ),
            child: Icon(Icons.edit, size: 14, color: AppTheme.accentPrimary.withOpacity(0.65)),
          ),
        ],
      ),
      child: RangeSlider(
        values: _priceRange,
        min: 0,
        max: 200000,
        divisions: 40,
        activeColor: AppTheme.accentPrimary,
        inactiveColor: AppTheme.accentPrimary.withOpacity(0.15),
        labels: RangeLabels('\$${_formatNumber(lo)}', '\$${_formatNumber(hi)}'),
        onChanged: (v) => setState(() => _priceRange = v),
      ),
    );
  }

  // ─── Mileage ───────────────────────────────────────────────────────────────

  Widget _buildMileageSection() {
    final lo = _mileageRange.start.round();
    final hi = _mileageRange.end.round();
    final hiStr = hi >= 300000 ? 'Any' : '${_formatNumber(hi)} km';
    return _FilterSection(
      title: 'Mileage',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${_formatNumber(lo)} – $hiStr',
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.accentPrimary,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _showRangeDialog(
              title: 'Mileage Range',
              current: _mileageRange,
              min: 0,
              max: 300000,
              suffix: ' km',
              onConfirm: (v) => setState(() => _mileageRange = v),
            ),
            child: Icon(Icons.edit, size: 14, color: AppTheme.accentPrimary.withOpacity(0.65)),
          ),
        ],
      ),
      child: RangeSlider(
        values: _mileageRange,
        min: 0,
        max: 300000,
        divisions: 60,
        activeColor: AppTheme.accentPrimary,
        inactiveColor: AppTheme.accentPrimary.withOpacity(0.15),
        labels: RangeLabels(
          '${_formatNumber(lo)} km',
          hi >= 300000 ? 'Any' : '${_formatNumber(hi)} km',
        ),
        onChanged: (v) => setState(() => _mileageRange = v),
      ),
    );
  }

  // ─── Body type ─────────────────────────────────────────────────────────────

  Widget _buildBodyTypeSection() {
    return _FilterSection(
      title: 'Body Type',
      child: _ChipGroup(
        options: CarData.bodyTypes,
        selected: _selectedBodyTypes,
        onChanged: (val, on) => setState(() => on
            ? _selectedBodyTypes.add(val)
            : _selectedBodyTypes.remove(val)),
      ),
    );
  }

  // ─── Fuel type ─────────────────────────────────────────────────────────────

  Widget _buildFuelTypeSection() {
    return _FilterSection(
      title: 'Fuel Type',
      child: _ChipGroup(
        options: CarData.fuelTypes,
        selected: _selectedFuelTypes,
        onChanged: (val, on) => setState(() => on
            ? _selectedFuelTypes.add(val)
            : _selectedFuelTypes.remove(val)),
      ),
    );
  }

  // ─── Transmission ──────────────────────────────────────────────────────────

  Widget _buildTransmissionSection() {
    return _FilterSection(
      title: 'Transmission',
      child: _ChipGroup(
        options: CarData.transmissions,
        selected: _selectedTransmissions,
        onChanged: (val, on) => setState(() => on
            ? _selectedTransmissions.add(val)
            : _selectedTransmissions.remove(val)),
      ),
    );
  }

  // ─── Drivetrain ────────────────────────────────────────────────────────────

  Widget _buildDriveTypeSection() {
    return _FilterSection(
      title: 'Drivetrain',
      child: _ChipGroup(
        options: CarData.driveTypes,
        selected: _selectedDriveTypes,
        onChanged: (val, on) => setState(() => on
            ? _selectedDriveTypes.add(val)
            : _selectedDriveTypes.remove(val)),
      ),
    );
  }

  // ─── Engine size ───────────────────────────────────────────────────────────

  Widget _buildEngineSizeSection() {
    return _FilterSection(
      title: 'Engine Size',
      child: _ChipGroup(
        options: CarData.engineSizes,
        selected: _selectedEngineSizes,
        onChanged: (val, on) => setState(() => on
            ? _selectedEngineSizes.add(val)
            : _selectedEngineSizes.remove(val)),
      ),
    );
  }

  // ─── Steering ──────────────────────────────────────────────────────────────

  Widget _buildSteeringSection() {
    return _FilterSection(
      title: 'Power Steering',
      child: _ChipGroup(
        options: CarData.steeringTypes,
        selected: _selectedSteering,
        onChanged: (val, on) => setState(() => on
            ? _selectedSteering.add(val)
            : _selectedSteering.remove(val)),
      ),
    );
  }

  // ─── Doors ─────────────────────────────────────────────────────────────────

  Widget _buildDoorsSection() {
    return _FilterSection(
      title: 'Number of Doors',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [2, 3, 4, 5].map((doors) {
          final isSelected = _selectedDoors.contains(doors);
          return _SelectChip(
            label: doors == 5 ? '5+' : '$doors',
            isSelected: isSelected,
            onTap: () => setState(() => isSelected
                ? _selectedDoors.remove(doors)
                : _selectedDoors.add(doors)),
          );
        }).toList(),
      ),
    );
  }

  // ─── Color ─────────────────────────────────────────────────────────────────

  Widget _buildColorSection() {
    return _FilterSection(
      title: 'Color',
      child: Wrap(
        spacing: 10,
        runSpacing: 12,
        children: CarData.colorOptions.map((c) {
          final isSelected = _selectedColors.contains(c.name);
          return GestureDetector(
            onTap: () => setState(() => isSelected
                ? _selectedColors.remove(c.name)
                : _selectedColors.add(c.name)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c.color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.accentPrimary
                          : c.needsBorder
                              ? Colors.grey[300]!
                              : Colors.transparent,
                      width: isSelected ? 3 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: isSelected
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: c.needsBorder ? AppTheme.accentPrimary : Colors.white,
                        )
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  c.name,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                    color: isSelected ? AppTheme.accentPrimary : Colors.grey[600],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── Optional features ─────────────────────────────────────────────────────

  Widget _buildFeaturesSection() {
    return _FilterSection(
      title: 'Features & Options',
      child: _ChipGroup(
        options: CarData.optionalFeatures,
        selected: _selectedFeatures,
        onChanged: (val, on) => setState(() => on
            ? _selectedFeatures.add(val)
            : _selectedFeatures.remove(val)),
      ),
    );
  }

  // ─── Condition & history ───────────────────────────────────────────────────

  Widget _buildConditionSection() {
    return _FilterSection(
      title: 'Condition & History',
      child: _ChipGroup(
        options: CarData.conditionItems,
        selected: _selectedConditions,
        onChanged: (val, on) => setState(() => on
            ? _selectedConditions.add(val)
            : _selectedConditions.remove(val)),
      ),
    );
  }

  // ─── Seller type ───────────────────────────────────────────────────────────

  Widget _buildSellerTypeSection() {
    return _FilterSection(
      title: 'Seller',
      child: _ChipGroup(
        options: VehicleSearchFilters.sellerTypeOptions,
        selected: _selectedSellerTypes,
        onChanged: (val, on) => setState(() => on
            ? _selectedSellerTypes.add(val)
            : _selectedSellerTypes.remove(val)),
      ),
    );
  }

  // ─── Sort by ───────────────────────────────────────────────────────────────

  Widget _buildSortSection() {
    return _FilterSection(
      title: 'Sort By',
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: CarData.sortOptions.map((option) {
          final isSelected = _sortBy == option;
          return _SelectChip(
            label: option,
            isSelected: isSelected,
            onTap: () => setState(() => _sortBy = option),
            isRadio: true,
          );
        }).toList(),
      ),
    );
  }

  // ─── Search button ─────────────────────────────────────────────────────────

  Widget _buildSearchButton() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          12 + MediaQuery.of(context).padding.bottom,
        ),
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).pop(_buildFilters()),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.accentPrimary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.search, size: 20),
              const SizedBox(width: 8),
              Text(
                _activeFilterCount > 0
                    ? 'Search Cars · $_activeFilterCount filter${_activeFilterCount != 1 ? 's' : ''}'
                    : 'Search All Cars',
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Widget _buildDivider() => Container(
        height: 6,
        color: const Color(0xFFEEEEEE),
      );

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}

// ─── Brand Picker Sheet ────────────────────────────────────────────────────────

class _BrandPickerSheet extends StatefulWidget {
  final Set<String> currentBrands;
  const _BrandPickerSheet({required this.currentBrands});

  @override
  State<_BrandPickerSheet> createState() => _BrandPickerSheetState();
}

class _BrandPickerSheetState extends State<_BrandPickerSheet> {
  late String _selectedLetter;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late PageController _letterPageController;
  int _letterPageIndex = 0;
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.currentBrands};
    final letters = CarData.availableLetters;
    _selectedLetter = letters.contains('A') ? 'A' : letters.first;
    _letterPageIndex = letters.indexOf(_selectedLetter);
    _letterPageController = PageController(
      initialPage: _letterPageIndex,
      viewportFraction: 0.2,
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _letterPageController.dispose();
    super.dispose();
  }

  List<String> get _filteredBrands {
    if (_searchQuery.isNotEmpty) {
      return CarData.allBrands
          .where((b) => b.toLowerCase().contains(_searchQuery.toLowerCase()))
          .toList();
    }
    return CarData.brandsByLetter[_selectedLetter] ?? [];
  }

  @override
  Widget build(BuildContext context) {
    final letters = CarData.availableLetters;

    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
                child: Row(
                  children: [
                    const Text(
                      'Select Makes',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    if (_selected.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _selected.clear()),
                        child: const Text(
                          'Clear',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, _selected),
                      child: Text(
                        'Done${_selected.isNotEmpty ? ' (${_selected.length})' : ''}',
                        style: const TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          color: AppTheme.accentPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search makes…',
                    hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(height: 10),
              // Alphabet carousel (hidden when searching)
              if (_searchQuery.isEmpty) ...[
                SizedBox(
                  height: 72,
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.chevron_left,
                          color: _letterPageIndex > 0
                              ? Colors.grey[700]
                              : Colors.grey[300],
                        ),
                        onPressed: _letterPageIndex > 0
                            ? () => _letterPageController.animateToPage(
                                  _letterPageIndex - 1,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                )
                            : null,
                      ),
                      Expanded(
                        child: PageView.builder(
                          controller: _letterPageController,
                          itemCount: letters.length,
                          onPageChanged: (i) => setState(() {
                            _letterPageIndex = i;
                            _selectedLetter = letters[i];
                          }),
                          itemBuilder: (context, i) {
                            return AnimatedBuilder(
                              animation: _letterPageController,
                              builder: (context, _) {
                                final currentPage = _letterPageController.hasClients
                                    ? (_letterPageController.page ?? _letterPageIndex.toDouble())
                                    : _letterPageIndex.toDouble();
                                final delta = (currentPage - i).abs();
                                final scale = (1.0 - delta * 0.3).clamp(0.5, 1.0);
                                final opacity = (1.0 - delta * 0.45).clamp(0.2, 1.0);
                                final isActive = delta < 0.5;
                                return GestureDetector(
                                  onTap: () => _letterPageController.animateToPage(
                                    i,
                                    duration: const Duration(milliseconds: 250),
                                    curve: Curves.easeInOut,
                                  ),
                                  child: Center(
                                    child: Transform.scale(
                                      scale: scale,
                                      child: Opacity(
                                        opacity: opacity,
                                        child: Container(
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: isActive
                                                ? AppTheme.accentPrimary.withOpacity(0.12)
                                                : Colors.transparent,
                                          ),
                                          child: Center(
                                            child: Text(
                                              letters[i],
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w800,
                                                fontSize: 22,
                                                color: isActive
                                                    ? AppTheme.accentPrimary
                                                    : Colors.grey[500],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.chevron_right,
                          color: _letterPageIndex < letters.length - 1
                              ? Colors.grey[700]
                              : Colors.grey[300],
                        ),
                        onPressed: _letterPageIndex < letters.length - 1
                            ? () => _letterPageController.animateToPage(
                                  _letterPageIndex + 1,
                                  duration: const Duration(milliseconds: 250),
                                  curve: Curves.easeInOut,
                                )
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
              // Brand list
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragEnd: (details) {
                    if (_searchQuery.isNotEmpty) return;
                    final dx = details.velocity.pixelsPerSecond.dx;
                    if (dx < -300 && _letterPageIndex < letters.length - 1) {
                      _letterPageController.animateToPage(
                        _letterPageIndex + 1,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    } else if (dx > 300 && _letterPageIndex > 0) {
                      _letterPageController.animateToPage(
                        _letterPageIndex - 1,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  },
                  child: _filteredBrands.isEmpty
                      ? const Center(
                          child: Text(
                            'No makes found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                        controller: scrollController,
                        itemCount: _filteredBrands.length,
                        itemBuilder: (context, i) {
                          final brand = _filteredBrands[i];
                          final isSelected = _selected.contains(brand);
                          return ListTile(
                            leading: _BrandAvatar(brand: brand, size: 40),
                            title: Text(
                              brand,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                fontSize: 15,
                                color: isSelected
                                    ? AppTheme.accentPrimary
                                    : AppTheme.black,
                              ),
                            ),
                            subtitle: Text(
                              '${CarData.brandModels[brand]?.length ?? 0} models',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500],
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(Icons.check_circle,
                                    color: AppTheme.accentPrimary)
                                : Icon(Icons.circle_outlined,
                                    color: Colors.grey[300]),
                            onTap: () => setState(() {
                              if (isSelected) {
                                _selected.remove(brand);
                              } else {
                                _selected.add(brand);
                              }
                            }),
                          );
                        },
                      ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Shared sub-widgets ────────────────────────────────────────────────────────

class _FilterSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _FilterSection({
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.black,
                ),
              ),
              if (trailing != null) ...[
                const Spacer(),
                trailing!,
              ],
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final void Function(String val, bool on) onChanged;

  const _ChipGroup({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selected.contains(option);
        return _SelectChip(
          label: option,
          isSelected: isSelected,
          onTap: () => onChanged(option, !isSelected),
        );
      }).toList(),
    );
  }
}

class _SelectChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isRadio;

  const _SelectChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isRadio = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentPrimary
              : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppTheme.accentPrimary
                : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.white : Colors.grey[700],
          ),
        ),
      ),
    );
  }
}

class _BrandTile extends StatelessWidget {
  final String brand;
  final bool isSelected;
  final VoidCallback onTap;

  const _BrandTile({
    required this.brand,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppTheme.accentPrimary
                : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? AppTheme.accentPrimary.withOpacity(0.15)
                  : Colors.black.withOpacity(0.04),
              blurRadius: isSelected ? 8 : 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _BrandAvatar(brand: brand, size: 44),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                brand,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                  color: isSelected ? AppTheme.accentPrimary : Colors.grey[800],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AllMakesTile extends StatelessWidget {
  final VoidCallback onTap;
  const _AllMakesTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.accentPrimary.withOpacity(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.accentPrimary.withOpacity(0.25),
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.accentPrimary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                size: 22,
                color: AppTheme.accentPrimary,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'All Makes',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BrandAvatar extends StatelessWidget {
  final String brand;
  final double size;
  const _BrandAvatar({required this.brand, required this.size});

  Color _brandColor(String brand) {
    const palette = [
      Color(0xFFF48867), Color(0xFF5C7CFA), Color(0xFF20C997),
      Color(0xFFFCC419), Color(0xFFFF6B6B), Color(0xFF74C0FC),
      Color(0xFFE599F7), Color(0xFF63E6BE), Color(0xFFFFA94D),
    ];
    return palette[brand.codeUnitAt(0) % palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final logoPath = CarData.logoAssetPath(brand);

    if (logoPath != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.grey.shade200, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        padding: EdgeInsets.all(size * 0.15),
        child: Image.asset(
          logoPath,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildInitials(),
        ),
      );
    }

    return _buildInitials();
  }

  Widget _buildInitials() {
    final initials = brand.split(' ').take(2).map((w) => w[0]).join();
    final color = _brandColor(brand);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3), width: 1.5),
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w800,
            fontSize: size * 0.32,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _SelectedBrandBadge extends StatelessWidget {
  final String brand;
  final VoidCallback onClear;

  const _SelectedBrandBadge({required this.brand, required this.onClear});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.accentPrimary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accentPrimary.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BrandAvatar(brand: brand, size: 28),
          const SizedBox(width: 10),
          Text(
            brand,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentPrimary,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClear,
            child: Icon(Icons.close, size: 16,
                color: AppTheme.accentPrimary.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderHint extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PlaceholderHint({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey[400], size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[500],
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
