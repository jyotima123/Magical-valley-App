import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Form building blocks shared by the New Listing screens of every Market
// category: cars (AddVehicleScreen) and generic items (AddMarketItemScreen).

/// Picks photos, uploads them, and shows them as a removable strip.
///
/// Edits [urls] in place and calls [onChanged] after each change, so the
/// owning form only has to rebuild. Photos land in storage as they are picked;
/// the form saves the resulting URLs with the listing.
class ListingPhotosField extends StatefulWidget {
  final List<String> urls;
  final VoidCallback onChanged;

  /// Start of each uploaded file's name, e.g. `vehicle_photo`.
  final String fileNamePrefix;

  const ListingPhotosField({
    super.key,
    required this.urls,
    required this.onChanged,
    required this.fileNamePrefix,
  });

  @override
  State<ListingPhotosField> createState() => _ListingPhotosFieldState();
}

class _ListingPhotosFieldState extends State<ListingPhotosField> {
  bool _isUploadingPhoto = false;

  Future<void> _pickAndUploadPhotos() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;

    setState(() => _isUploadingPhoto = true);

    for (final xFile in picked) {
      final Uint8List bytes = await xFile.readAsBytes();
      final userId = Supabase.instance.client.auth.currentUser?.id ?? 'unknown';

      final result = await SupabaseApiService.instance.uploadGenericFile(
        fileBytes: bytes,
        fileName:
            '${widget.fileNamePrefix}_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      if (!result.isSuccess || result.data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.error ?? 'Failed to upload photo'),
              backgroundColor: Colors.red,
            ),
          );
        }
        continue;
      }

      widget.urls.add(result.data as String);
      if (mounted) widget.onChanged();
    }

    if (mounted) setState(() => _isUploadingPhoto = false);
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Photos',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: Colors.grey.shade600,
                ),
              ),
              if (urls.isNotEmpty) ...[
                const SizedBox(width: 6),
                Text(
                  '(${urls.length})',
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentPrimary,
                  ),
                ),
              ],
              const Spacer(),
              if (_isUploadingPhoto)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accentPrimary,
                  ),
                )
              else
                TextButton.icon(
                  onPressed: _pickAndUploadPhotos,
                  icon: const Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                  ),
                  label: const Text('Add'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentPrimary,
                    padding: EdgeInsets.zero,
                    textStyle: const TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (urls.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.photo_library_outlined,
                    size: 36,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'No photos added',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: urls.length,
                itemBuilder: (context, index) {
                  final url = urls[index];
                  return Container(
                    width: 90,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: Colors.grey.shade200,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          VehicleImage(url: url, fit: BoxFit.cover),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () {
                                urls.removeAt(index);
                                widget.onChanged();
                              },
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class ListingFormSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const ListingFormSection({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.accentPrimary,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            children: children.indexed
                .map(
                  (e) => Column(
                    children: [
                      e.$2,
                      if (e.$1 < children.length - 1)
                        Divider(
                          height: 1,
                          indent: 16,
                          endIndent: 16,
                          color: Colors.grey.shade100,
                        ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class ListingTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool required;
  final String? hint;
  final int maxLines;
  final int? maxLength;

  const ListingTextField({
    super.key,
    required this.label,
    required this.controller,
    this.required = false,
    this.hint,
    this.maxLines = 1,
    this.maxLength,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        maxLength: maxLength,
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          filled: true,
          fillColor: Colors.transparent,
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          counterText: '',
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }
}

class ListingNumberField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool required;
  final String? hint;
  final int? min;
  final int? max;

  const ListingNumberField({
    super.key,
    required this.label,
    required this.controller,
    this.required = false,
    this.hint,
    this.min,
    this.max,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextFormField(
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          filled: true,
          fillColor: Colors.transparent,
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) return 'Required';
          if (v != null && v.isNotEmpty) {
            final n = int.tryParse(v);
            if (n == null) return 'Invalid number';
            if (min != null && n < min!) return 'Min $min';
            if (max != null && n > max!) return 'Max $max';
          }
          return null;
        },
      ),
    );
  }
}

class ListingPriceField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool required;
  final String? hint;

  const ListingPriceField({
    super.key,
    required this.label,
    required this.controller,
    this.required = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
        ],
        style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
          prefixText: '\$ ',
          prefixStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            color: AppTheme.black,
          ),
          filled: true,
          fillColor: Colors.transparent,
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        validator: (v) {
          if (required && (v == null || v.trim().isEmpty)) return 'Required';
          if (v != null && v.isNotEmpty) {
            final n = double.tryParse(v);
            if (n == null) return 'Invalid price';
            if (n < 0) return 'Must be positive';
          }
          return null;
        },
      ),
    );
  }
}

class ListingDropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) itemLabel;
  final ValueChanged<T?> onChanged;
  final bool required;

  const ListingDropdownField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonFormField<T>(
        value: value,
        isExpanded: true,
        icon: Icon(Icons.expand_more, color: Colors.grey.shade500, size: 20),
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          filled: true,
          fillColor: Colors.transparent,
          labelStyle: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          color: AppTheme.black,
        ),
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
                value: item,
                child: Text(itemLabel(item)),
              ),
            )
            .toList(),
        onChanged: onChanged,
        validator: required ? (v) => v == null ? 'Required' : null : null,
      ),
    );
  }
}
