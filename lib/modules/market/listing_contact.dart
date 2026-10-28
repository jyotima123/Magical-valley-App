/// How a listing offers its seller's phone number — the same rules for a car
/// and for anything else in the Market.
///
/// Both switches here are presentation only. Nothing about placing the call
/// changed: the `tel:` handlers are still in place behind them, so putting the
/// button back is a one-line change rather than a rewrite.

/// Whether a listing shows a Call button beside Message Seller.
///
/// Off for now: buyer and seller talk in the app, where the conversation is
/// kept. Flip it to true to bring the button back on both listing screens.
const bool kShowListingCallButton = false;

/// How many digits of a phone number the small line under a listing shows
/// before it trails off.
const int kVisiblePhoneDigits = 6;

/// The seller's number, cut short: the first [kVisiblePhoneDigits] digits as the
/// seller typed them, punctuation and all, then an ellipsis.
///
/// Enough to recognise an area code, not enough to dial — the point is that
/// contact goes through the app. A number with no more digits than that is
/// returned whole rather than given a misleading ellipsis.
String shortenedPhone(String phone) {
  var digits = 0;
  for (var i = 0; i < phone.length; i++) {
    if (_isDigit(phone.codeUnitAt(i))) digits++;
    if (digits == kVisiblePhoneDigits) {
      // Everything after the last shown digit is dropped, so the cut never
      // leaves a dangling bracket or dash before the ellipsis.
      final shown = phone.substring(0, i + 1);
      return i + 1 == phone.length ? shown : '$shown…';
    }
  }
  return phone;
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;
