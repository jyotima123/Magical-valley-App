import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/vehicle_image.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/market_item.dart';
import 'package:mvc_app/modules/market/widgets/pressable_scale.dart';

/// A category's promoted listings (migration 089), as a horizontal shelf
/// above the normal list. Promoted items stay in the list as well; this is an
/// extra place to be seen, not a separate section.
class PromotedListingsStrip extends StatelessWidget {
  const PromotedListingsStrip({
    super.key,
    required this.items,
    required this.onOpen,
  });

  final List<MarketItem> items;
  final ValueChanged<MarketItem> onOpen;

  static const double _cardWidth = 156;
  static const double _photoHeight = 150;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  size: 18,
                  color: AppTheme.accentPrimary,
                ),
                SizedBox(width: 8),
                Text(
                  'Promoted',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.black,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: _photoHeight + 62,
            // Laid out full width by the caller, so the shelf scrolls edge to
            // edge while its first card lines up with the list below.
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) =>
                  _PromotedCard(item: items[i], onTap: () => onOpen(items[i])),
            ),
          ),
        ],
      ),
    );
  }
}

class _PromotedCard extends StatelessWidget {
  const _PromotedCard({required this.item, required this.onTap});

  final MarketItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = item.firstImageUrl;
    return PressableScale(
      onTap: onTap,
      semanticLabel: '${item.title}, ${item.displayPrice}',
      child: Container(
        width: PromotedListingsStrip._cardWidth,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            url != null
                ? VehicleImage(
                    url: url,
                    width: PromotedListingsStrip._cardWidth,
                    height: PromotedListingsStrip._photoHeight,
                    alignment: item.isInCategory(kPetsCategory)
                        ? Alignment.topCenter
                        : Alignment.center,
                    decodeWidth: 400,
                    placeholder: (_) => _placeholder(),
                  )
                : _placeholder(),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.hasPromo ? item.displayPromoPrice : item.displayPrice,
                    maxLines: 1,
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: PromotedListingsStrip._cardWidth,
      height: PromotedListingsStrip._photoHeight,
      color: const Color(0xFFF0F0F0),
      child: Icon(
        MarketCategory.iconFor(item.category),
        size: 40,
        color: Colors.grey.shade300,
      ),
    );
  }
}
