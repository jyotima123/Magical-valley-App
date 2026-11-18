import 'package:flutter/material.dart';

/// Side of the square thumbnail on listing cards.
const double kListingThumbSize = 120;

/// The shell every listing card in the Cars, Pets and Market lists shares:
/// a square photo on the left and the listing's text on the right.
///
/// The card is at least as tall as the photo; longer text grows it. By
/// default the photo stays a square pinned to the top; with
/// [fillHeight] it stretches to the card's full height instead.
class ListingRowCard extends StatelessWidget {
  const ListingRowCard({
    super.key,
    required this.thumbnail,
    required this.child,
    this.fillHeight = false,
  });

  /// Laid out [kListingThumbSize] wide and, unless [fillHeight], as tall;
  /// it should fill its box.
  final Widget thumbnail;
  final Widget child;

  /// Stretch the photo down the whole card instead of leaving a gap below it
  /// when the text runs taller than the square.
  final bool fillHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
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
      child: fillHeight ? _filled() : _square(),
    );
  }

  Widget get _text => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: child,
      );

  Widget _square() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(dimension: kListingThumbSize, child: thumbnail),
        Expanded(child: _text),
      ],
    );
  }

  /// The text sizes the card; the photo is then pinned to its full height.
  /// A Stack avoids IntrinsicHeight, which network images do not support.
  Widget _filled() {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.only(left: kListingThumbSize),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kListingThumbSize),
            child: _text,
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: kListingThumbSize,
          child: thumbnail,
        ),
      ],
    );
  }
}

/// The red "SOLD" stamp laid over a sold listing's thumbnail.
class SoldThumbStamp extends StatelessWidget {
  const SoldThumbStamp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red.shade600.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'SOLD',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A small pin + place line for the bottom of a listing card.
class ListingLocationLine extends StatelessWidget {
  const ListingLocationLine(this.location, {super.key});

  final String location;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.location_on, size: 12, color: Colors.grey.shade400),
        const SizedBox(width: 2),
        Expanded(
          child: Text(
            location,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 11,
              color: Colors.grey.shade500,
            ),
          ),
        ),
      ],
    );
  }
}
