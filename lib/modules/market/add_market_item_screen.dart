import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/market_item.dart';
import 'package:mvc_app/modules/market/market_repository.dart';
import 'package:mvc_app/modules/market/widgets/listing_form_fields.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// New Listing / Edit Listing for every Market category except Cars & Trucks,
/// which has its own form ([AddVehicleScreen]). Pops `true` once saved.
class AddMarketItemScreen extends StatefulWidget {
  /// When provided, the screen edits this item instead of creating one.
  final MarketItem? existing;

  /// Category a new item starts in; the seller can still change it.
  final MarketCategory? initialCategory;

  final MarketRepository? repository;

  const AddMarketItemScreen({
    super.key,
    this.existing,
    this.initialCategory,
    this.repository,
  });

  @override
  State<AddMarketItemScreen> createState() => _AddMarketItemScreenState();
}

class _AddMarketItemScreenState extends State<AddMarketItemScreen> {
  /// Stands for "no condition" in the dropdown, which cannot hold null as an
  /// item: once a condition is picked, this is how the seller clears it.
  static const _noCondition = '';

  late final MarketRepository _repo = widget.repository ?? MarketRepository();

  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _promotionCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final List<String> _imageUrls = [];

  String? _category;

  /// [_noCondition] (the empty string) stands for "no second category".
  String _secondaryCategory = _noCondition;
  String _condition = _noCondition;

  /// Categories an item can be listed under. Starts with whatever the screen
  /// was opened from, so the form is usable before the full list arrives.
  List<MarketCategory> _categories = [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialCategory;
    if (initial != null && !initial.isCars) {
      _categories = [initial];
      _category = initial.slug;
    }
    final item = widget.existing;
    if (item != null) _prefillFrom(item);
    _ensureCurrentCategoryListed();
    _loadCategories();
  }

  /// A dropdown's value must be one of its items. Covers editing before the
  /// list has loaded, and an item whose category has since been hidden.
  void _ensureCurrentCategoryListed() {
    for (final current in [_category, _secondaryCategory]) {
      if (current != null &&
          current != _noCondition &&
          !_categories.any((c) => c.slug == current)) {
        _categories = [
          ..._categories,
          MarketCategory(slug: current, name: _nameOf(current)),
        ];
      }
    }
  }

  void _prefillFrom(MarketItem item) {
    _category = item.category;
    _secondaryCategory = item.secondaryCategory ?? _noCondition;
    _condition = item.condition ?? _noCondition;
    _titleCtrl.text = item.title;
    _priceCtrl.text = item.price.toStringAsFixed(2);
    _promotionCtrl.text = item.promotion != null
        ? item.promotion!.toStringAsFixed(2)
        : '';
    _descriptionCtrl.text = item.description ?? '';
    _locationCtrl.text = item.location ?? '';
    _contactPhoneCtrl.text = item.contactPhone ?? '';
    _imageUrls.addAll(item.images);
  }

  Future<void> _loadCategories() async {
    try {
      final all = await _repo.fetchCategories();
      if (!mounted) return;
      setState(() {
        _categories = all.where((c) => !c.isCars).toList();
        _ensureCurrentCategoryListed();
      });
    } catch (_) {
      // Keep the category the screen was opened with; saving still works.
    }
  }

  /// Best available name before the category list has loaded.
  String _nameOf(String slug) {
    final initial = widget.initialCategory;
    if (initial != null && initial.slug == slug) return initial.name;
    return slug;
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl,
      _priceCtrl,
      _promotionCtrl,
      _descriptionCtrl,
      _locationCtrl,
      _contactPhoneCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _textOrNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  Map<String, dynamic> _buildPayload() {
    return {
      'category': _category,
      'secondary_category': _secondaryCategory == _noCondition
          ? null
          : _secondaryCategory,
      'title': _titleCtrl.text.trim(),
      'condition': _condition == _noCondition ? null : _condition,
      'price': double.parse(_priceCtrl.text.trim()),
      'promotion': _promotionCtrl.text.trim().isEmpty
          ? null
          : double.tryParse(_promotionCtrl.text.trim()),
      'description': _textOrNull(_descriptionCtrl),
      'location': _textOrNull(_locationCtrl),
      'contact_phone': _textOrNull(_contactPhoneCtrl),
      'images': _imageUrls.isEmpty ? null : _imageUrls.join(','),
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final payload = _buildPayload();
      if (_isEdit) {
        await _repo.updateItem(widget.existing!.id, payload);
      } else {
        await _repo.createItem(payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to save: ${e is PostgrestException ? e.message : e}',
          ),
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
            ListingFormSection(
              title: 'Basic Info',
              children: [
                ListingDropdownField<String>(
                  label: 'Category',
                  value: _category,
                  items: _categories.map((c) => c.slug).toList(),
                  itemLabel: (slug) =>
                      _categories.firstWhere((c) => c.slug == slug).name,
                  required: true,
                  onChanged: (v) => setState(() {
                    _category = v;
                    if (_secondaryCategory == v)
                      _secondaryCategory = _noCondition;
                  }),
                ),
                ListingDropdownField<String>(
                  label: 'Second Category (optional)',
                  value: _secondaryCategory,
                  items: [
                    _noCondition,
                    ..._categories
                        .map((c) => c.slug)
                        .where((slug) => slug != _category),
                  ],
                  itemLabel: (slug) => slug == _noCondition
                      ? 'None'
                      : _categories.firstWhere((c) => c.slug == slug).name,
                  onChanged: (v) =>
                      setState(() => _secondaryCategory = v ?? _noCondition),
                ),
                ListingTextField(
                  label: 'Title',
                  controller: _titleCtrl,
                  required: true,
                  maxLength: 80,
                  hint: 'e.g. Solid oak dining table',
                ),
                ListingDropdownField<String>(
                  label: 'Condition',
                  value: _condition,
                  items: const [_noCondition, ...MarketItemCondition.values],
                  itemLabel: (v) => v == _noCondition
                      ? 'Not specified'
                      : MarketItemCondition.label(v),
                  onChanged: (v) =>
                      setState(() => _condition = v ?? _noCondition),
                ),
              ],
            ),
            ListingFormSection(
              title: 'Pricing',
              children: [
                ListingPriceField(
                  label: 'Price',
                  controller: _priceCtrl,
                  required: true,
                  hint: '0 to give it away',
                ),
                ListingPriceField(
                  label: 'Promotional Price',
                  controller: _promotionCtrl,
                ),
              ],
            ),
            ListingFormSection(
              title: 'Details',
              children: [
                ListingTextField(
                  label: 'Description',
                  controller: _descriptionCtrl,
                  maxLines: 4,
                  hint: 'Size, age, brand, anything a buyer should know',
                ),
                ListingPhotosField(
                  urls: _imageUrls,
                  fileNamePrefix: 'market_photo',
                  onChanged: () => setState(() {}),
                ),
                ListingTextField(
                  label: 'Location',
                  controller: _locationCtrl,
                  hint: 'City or neighborhood',
                ),
                ListingTextField(
                  label: 'Contact Phone',
                  controller: _contactPhoneCtrl,
                  hint: '(555) 123-4567',
                ),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}
