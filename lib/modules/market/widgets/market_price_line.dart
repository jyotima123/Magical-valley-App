import 'package:flutter/material.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/market/market_item.dart';

/// Price, or the promotional price with the original struck through.
class MarketPriceLine extends StatelessWidget {
  final MarketItem item;
  final bool large;

  const MarketPriceLine({super.key, required this.item, this.large = false});

  @override
  Widget build(BuildContext context) {
    final mainSize = large ? 24.0 : 18.0;
    final struckSize = large ? 15.0 : 13.0;
    if (!item.hasPromo) {
      return Text(
        item.displayPrice,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: mainSize,
          fontWeight: FontWeight.w800,
          color: item.isFree ? AppTheme.accentPrimary : AppTheme.black,
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          item.displayPrice,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: struckSize,
            color: Colors.grey.shade400,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        SizedBox(width: large ? 10 : 8),
        Text(
          item.displayPromoPrice,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: mainSize,
            fontWeight: FontWeight.w800,
            color: AppTheme.accentPrimary,
          ),
        ),
      ],
    );
  }
}
