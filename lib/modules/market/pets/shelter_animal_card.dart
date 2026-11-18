import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/market/widgets/fit_toggle_photo.dart';
import 'package:mvc_app/modules/market/widgets/listing_row_card.dart';
import 'package:mvc_app/modules/market/pets/shelter_animal.dart';

/// A shelter animal in the Pets list, laid out like the community listing
/// cards it sits between so the list reads as one.
class ShelterAnimalCard extends StatelessWidget {
  const ShelterAnimalCard({
    super.key,
    required this.animal,
    required this.shelterName,
    this.showWholePhoto = false,
  });

  final ShelterAnimal animal;

  /// Show the whole photo (zoomed out) instead of cropping it to the square.
  final bool showWholePhoto;

  /// Shown when the animal's own record does not name its shelter.
  final String shelterName;

  @override
  Widget build(BuildContext context) {
    final fee = animal.displayFee;
    return ListingRowCard(
      thumbnail: animal.firstPhotoUrl != null
          ? FitTogglePhoto(
              url: animal.firstPhotoUrl!,
              height: kListingThumbSize,
              showWhole: showWholePhoto,
              decodeWidth: 400,
              coverAlignment: Alignment.topCenter,
              placeholder: (_) => _placeholder(),
            )
          : _placeholder(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _Tag(
                'Adopt',
                background: Colors.green.withValues(alpha: 0.12),
                foreground: Colors.green.shade700,
              ),
              if (animal.onHold)
                _Tag(
                  'On hold',
                  background: Colors.orange.withValues(alpha: 0.14),
                  foreground: Colors.orange.shade800,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            animal.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppTheme.black,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            animal.summary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          if (fee != null) ...[
            const SizedBox(height: 4),
            Text(
              'Adoption fee $fee',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.accentPrimary,
              ),
            ),
          ],
          const SizedBox(height: 4),
          ListingLocationLine(animal.shelterName ?? shelterName),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFF0F0F0),
      alignment: Alignment.center,
      child: Icon(Icons.pets, size: 40, color: Colors.grey.shade300),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color background;
  final Color foreground;

  const _Tag(this.label, {required this.background, required this.foreground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}
