import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/car_data.dart';
import 'package:mvc_app/modules/cars/vehicle_listing.dart';
import 'package:mvc_app/modules/market/widgets/listing_form_fields.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AddVehicleScreen extends StatefulWidget {
  /// When provided, the screen edits this listing instead of creating one.
  final VehicleListing? existing;

  const AddVehicleScreen({super.key, this.existing});

  @override
  State<AddVehicleScreen> createState() => _AddVehicleScreenState();
}

class _AddVehicleScreenState extends State<AddVehicleScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  final List<String> _imageUrls = [];

  static const _otherOption = 'Other';

  // Required fields
  final _yearCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _customMakeCtrl = TextEditingController();
  final _customModelCtrl = TextEditingController();
  String? _selectedMake;
  String? _selectedModel;
  String _status = 'New';

  bool get _isEdit => widget.existing != null;

  bool get _isCustomMake => _selectedMake == _otherOption;

  bool get _isCustomModel =>
      _isCustomMake || _selectedModel == _otherOption;

  // Optional fields
  final _vinCtrl = TextEditingController();
  final _trimCtrl = TextEditingController();
  final _mileageCtrl = TextEditingController(text: '0');
  final _promotionCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _videosCtrl = TextEditingController();
  final _engineTypeCtrl = TextEditingController();
  final _engineOptionsCtrl = TextEditingController();
  final _packageOptionsCtrl = TextEditingController();
  final _transmissionOptionsCtrl = TextEditingController();
  final _addonsCtrl = TextEditingController();
  final _interiorCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();

  String? _selectedBody;
  String? _selectedFuel;
  String? _selectedTransmission;
  String? _selectedColor;
  String _doors = '4';
  String _speed = '6';

  static const _statusOptions = ['New', 'Pre-Owned', 'Certified Pre-Owned'];
  static const _doorsOptions = ['2', '3', '4', '5'];
  static const _speedOptions = ['4', '5', '6', '7', '8', '9', '10', 'CVT'];

  @override
  void initState() {
    super.initState();
    final v = widget.existing;
    if (v != null) _prefillFrom(v);
  }

  void _prefillFrom(VehicleListing v) {
    if (CarData.allBrands.contains(v.make)) {
      _selectedMake = v.make;
      final models = CarData.brandModels[v.make] ?? [];
      if (models.contains(v.model)) {
        _selectedModel = v.model;
      } else {
        _selectedModel = _otherOption;
        _customModelCtrl.text = v.model;
      }
    } else {
      _selectedMake = _otherOption;
      _customMakeCtrl.text = v.make;
      _customModelCtrl.text = v.model;
    }

    _status = v.status;
    _yearCtrl.text = '${v.year}';
    _priceCtrl.text = v.price.toStringAsFixed(2);
    _vinCtrl.text = v.vin ?? '';
    _trimCtrl.text = v.trim ?? '';
    _mileageCtrl.text = '${v.mileage}';
    _promotionCtrl.text =
        v.promotion != null ? v.promotion!.toStringAsFixed(2) : '';
    _descriptionCtrl.text = v.description ?? '';
    _locationCtrl.text = v.location ?? '';
    _videosCtrl.text = v.videos.join(',');
    _engineTypeCtrl.text = v.engineType ?? '';
    _engineOptionsCtrl.text = v.engineOptions ?? '';
    _packageOptionsCtrl.text = v.packageOptions ?? '';
    _transmissionOptionsCtrl.text = v.transmissionOptions ?? '';
    _addonsCtrl.text = v.addonsDescription ?? '';
    _interiorCtrl.text = v.interior ?? '';
    _contactPhoneCtrl.text = v.contactPhone ?? '';
    _selectedBody = v.body;
    _selectedFuel = v.fuel;
    _selectedTransmission = v.transmission;
    _selectedColor = v.color;
    if (_doorsOptions.contains(v.doors)) _doors = v.doors!;
    if (_speedOptions.contains(v.speed)) _speed = v.speed!;
    _imageUrls.addAll(v.images);
  }

  @override
  void dispose() {
    for (final c in [
      _yearCtrl, _priceCtrl, _customMakeCtrl, _customModelCtrl,
      _vinCtrl, _trimCtrl,
      _mileageCtrl, _promotionCtrl, _descriptionCtrl, _locationCtrl,
      _videosCtrl, _engineTypeCtrl, _engineOptionsCtrl,
      _packageOptionsCtrl, _transmissionOptionsCtrl, _addonsCtrl,
      _interiorCtrl, _contactPhoneCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Next stock number: 1 + the highest existing numeric stock, starting at
  /// 1001. Scoped to in-app listings — a dealership's own stock numbers live
  /// in a separate namespace and must not push our counter up.
  Future<String> _generateStock() async {
    final rows = await Supabase.instance.client
        .from('vehicle_listings')
        .select('stock')
        .eq('source', 'community');
    var highest = 1000;
    for (final row in rows as List) {
      final n = int.tryParse((row['stock'] as String? ?? '').trim());
      if (n != null && n > highest) highest = n;
    }
    return '${highest + 1}';
  }

  Map<String, dynamic> _buildPayload() {
    final promotion = _promotionCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(_promotionCtrl.text.trim());

    final make =
        _isCustomMake ? _customMakeCtrl.text.trim() : _selectedMake!;
    final model =
        _isCustomModel ? _customModelCtrl.text.trim() : _selectedModel!;

    return {
      'vin': _vinCtrl.text.trim().isEmpty ? null : _vinCtrl.text.trim(),
      'year': int.parse(_yearCtrl.text.trim()),
      'make': make,
      'model': model,
      'trim': _trimCtrl.text.trim().isEmpty ? null : _trimCtrl.text.trim(),
      'body': _selectedBody,
      'status': _status,
      'mileage': int.tryParse(_mileageCtrl.text.trim()) ?? 0,
      'color': _selectedColor,
      'interior': _interiorCtrl.text.trim().isEmpty ? null : _interiorCtrl.text.trim(),
      'transmission': _selectedTransmission,
      'speed': _speed,
      'engine_type': _engineTypeCtrl.text.trim().isEmpty
          ? null
          : _engineTypeCtrl.text.trim(),
      'fuel': _selectedFuel,
      'doors': _doors,
      'price': double.parse(_priceCtrl.text.trim()),
      'promotion': promotion,
      'description': _descriptionCtrl.text.trim().isEmpty
          ? null
          : _descriptionCtrl.text.trim(),
      'location':
          _locationCtrl.text.trim().isEmpty ? null : _locationCtrl.text.trim(),
      'images': _imageUrls.isEmpty ? null : _imageUrls.join(','),
      'videos':
          _videosCtrl.text.trim().isEmpty ? null : _videosCtrl.text.trim(),
      'engine_options': _engineOptionsCtrl.text.trim().isEmpty
          ? null
          : _engineOptionsCtrl.text.trim(),
      'package_options': _packageOptionsCtrl.text.trim().isEmpty
          ? null
          : _packageOptionsCtrl.text.trim(),
      'transmission_options': _transmissionOptionsCtrl.text.trim().isEmpty
          ? null
          : _transmissionOptionsCtrl.text.trim(),
      'addons_description':
          _addonsCtrl.text.trim().isEmpty ? null : _addonsCtrl.text.trim(),
      'contact_phone':
          _contactPhoneCtrl.text.trim().isEmpty ? null : _contactPhoneCtrl.text.trim(),
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final payload = _buildPayload();

      if (_isEdit) {
        await Supabase.instance.client
            .from('vehicle_listings')
            .update(payload)
            .eq('id', widget.existing!.id);
      } else {
        payload['created_by'] = Supabase.instance.client.auth.currentUser?.id;

        // Retry a couple of times in case another listing claims the same
        // auto-generated stock number between generation and insert.
        var inserted = false;
        for (var attempt = 0; attempt < 3 && !inserted; attempt++) {
          payload['stock'] = await _generateStock();
          try {
            await Supabase.instance.client
                .from('vehicle_listings')
                .insert(payload);
            inserted = true;
          } on PostgrestException catch (e) {
            final isDuplicateStock =
                e.code == '23505' && (e.message.contains('stock'));
            if (!isDuplicateStock || attempt == 2) rethrow;
          }
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: AppTheme.headerBackground,
        elevation: 0,
        title: Text(
          _isEdit ? 'Edit Listing' : 'New Listing',
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.black,
          ),
        ),
        actions: [
          if (_saving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: AppTheme.accentPrimary,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text(
                'Save',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentPrimary,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ListingFormSection(title: 'Basic Info', children: [
              ListingDropdownField<String>(
                label: 'Status',
                value: _status,
                items: _statusOptions,
                itemLabel: (s) => s,
                onChanged: (v) => setState(() => _status = v!),
                required: true,
              ),
              _StockInfoRow(
                stock: _isEdit ? widget.existing!.stock : null,
              ),
              ListingTextField(
                label: 'VIN',
                controller: _vinCtrl,
                hint: '1HGBH41JXMN109186',
                maxLength: 17,
              ),
            ]),
            ListingFormSection(title: 'Vehicle', children: [
              ListingDropdownField<String>(
                label: 'Make',
                value: _selectedMake,
                items: [...CarData.allBrands, _otherOption],
                itemLabel: (s) => s,
                required: true,
                onChanged: (v) => setState(() {
                  _selectedMake = v;
                  _selectedModel = null;
                }),
              ),
              if (_isCustomMake)
                ListingTextField(
                  label: 'Make (type manually)',
                  controller: _customMakeCtrl,
                  required: true,
                  hint: 'e.g. Koenigsegg',
                ),
              if (!_isCustomMake)
                ListingDropdownField<String>(
                  label: 'Model',
                  value: _selectedModel,
                  items: _selectedMake != null
                      ? [
                          ...(CarData.brandModels[_selectedMake!] ?? []),
                          _otherOption,
                        ]
                      : [],
                  itemLabel: (s) => s,
                  required: true,
                  onChanged: (v) => setState(() => _selectedModel = v),
                ),
              if (_isCustomModel)
                ListingTextField(
                  label: 'Model (type manually)',
                  controller: _customModelCtrl,
                  required: true,
                  hint: 'e.g. Jesko',
                ),
              ListingTextField(
                label: 'Trim / Version',
                controller: _trimCtrl,
                hint: 'EX',
              ),
              ListingNumberField(
                label: 'Year',
                controller: _yearCtrl,
                required: true,
                hint: '2020',
                min: 1900,
                max: 2030,
              ),
              ListingDropdownField<String>(
                label: 'Body Type',
                value: _selectedBody,
                items: CarData.bodyTypes,
                itemLabel: (s) => s,
                onChanged: (v) => setState(() => _selectedBody = v),
              ),
            ]),
            ListingFormSection(title: 'Specs', children: [
              ListingNumberField(
                label: 'Mileage (mi)',
                controller: _mileageCtrl,
                hint: '0',
                min: 0,
              ),
              ListingDropdownField<String>(
                label: 'Fuel',
                value: _selectedFuel,
                items: CarData.fuelTypes,
                itemLabel: (s) => s,
                onChanged: (v) => setState(() => _selectedFuel = v),
              ),
              ListingDropdownField<String>(
                label: 'Transmission',
                value: _selectedTransmission,
                items: CarData.transmissions,
                itemLabel: (s) => s,
                onChanged: (v) => setState(() => _selectedTransmission = v),
              ),
              ListingDropdownField<String>(
                label: 'Speeds',
                value: _speed,
                items: _speedOptions,
                itemLabel: (s) => s,
                onChanged: (v) => setState(() => _speed = v!),
              ),
              ListingDropdownField<String>(
                label: 'Doors',
                value: _doors,
                items: _doorsOptions,
                itemLabel: (s) => s,
                onChanged: (v) => setState(() => _doors = v!),
              ),
              ListingTextField(
                label: 'Engine Type',
                controller: _engineTypeCtrl,
                hint: 'ENGINE: 2.0L I4, TRANSMISSION: CVT AUTOMATIC',
              ),
            ]),
            ListingFormSection(title: 'Appearance', children: [
              ListingDropdownField<String>(
                label: 'Exterior Color',
                value: _selectedColor,
                items: CarData.colorOptions.map((c) => c.name).toList(),
                itemLabel: (s) => s,
                onChanged: (v) => setState(() => _selectedColor = v),
              ),
              ListingTextField(
                label: 'Interior Color',
                controller: _interiorCtrl,
                hint: 'Black',
              ),
            ]),
            ListingFormSection(title: 'Pricing', children: [
              ListingPriceField(
                label: 'Price',
                controller: _priceCtrl,
                required: true,
                hint: '25000.00',
              ),
              ListingPriceField(
                label: 'Promotional Price',
                controller: _promotionCtrl,
                hint: '24500.00',
              ),
            ]),
            ListingFormSection(title: 'Details', children: [
              ListingTextField(
                label: 'Contact Phone',
                controller: _contactPhoneCtrl,
                hint: '(555) 123-4567',
              ),
              ListingTextField(
                label: 'Location',
                controller: _locationCtrl,
                hint: 'Lot A',
              ),
              ListingTextField(
                label: 'Description',
                controller: _descriptionCtrl,
                maxLines: 3,
                hint: 'Vehicle description',
              ),
              ListingPhotosField(
                urls: _imageUrls,
                fileNamePrefix: 'vehicle_photo',
                onChanged: () => setState(() {}),
              ),
              ListingTextField(
                label: 'Video URLs',
                controller: _videosCtrl,
                hint: 'https://…',
              ),
            ]),
            ListingFormSection(title: 'Options & Packages', children: [
              ListingTextField(
                label: 'Engine Options',
                controller: _engineOptionsCtrl,
                hint: '501A 994',
              ),
              ListingTextField(
                label: 'Package Options',
                controller: _packageOptionsCtrl,
                hint: 'P01',
              ),
              ListingTextField(
                label: 'Transmission Options',
                controller: _transmissionOptionsCtrl,
                hint: 'T01',
              ),
              ListingTextField(
                label: 'Add-ons Description',
                controller: _addonsCtrl,
                hint: 'Floor mats',
                maxLines: 2,
              ),
            ]),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// ─── Vehicle-only form widgets ────────────────────────────────────────────────

class _StockInfoRow extends StatelessWidget {
  /// Existing stock number when editing, or null when it will be auto-generated.
  final String? stock;

  const _StockInfoRow({this.stock});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            'Stock #',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          Text(
            stock ?? 'Auto-generated on save',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: stock != null ? FontWeight.w600 : FontWeight.w400,
              fontStyle: stock != null ? FontStyle.normal : FontStyle.italic,
              color: stock != null ? AppTheme.black : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }
}
