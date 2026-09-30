import 'dart:math' as math;

/// Builds readable SKUs like `DRK-SMP330-7Q`: main category, name initials
/// plus size, and a two-character tag.
///
/// The tag is random rather than a running number: two phones adding
/// products offline would hand out the same next number, and preventing that
/// needs a transaction, which cannot run offline. A random tag collides
/// rarely; [generateSku] re-rolls on a collision with the SKUs this device
/// knows about, and the sync to come can flag the rest.
///
/// A SKU is fixed once a product is saved — renaming a product or changing
/// its categories leaves it alone, so a code people have learned stays put.

/// Short, fixed codes for the default categories. Others take their first
/// three letters.
const _categoryCodes = {
  'snacks': 'SNK',
  'drinks': 'DRK',
  'pantry': 'PNT',
  'canned goods': 'CAN',
  'household': 'HSH',
};

/// Size words that shrink to one letter.
const _sizeWords = {
  'small': 'S',
  'medium': 'M',
  'regular': 'R',
  'large': 'L',
  'jumbo': 'J',
  'family': 'F',
};

/// Units kept next to the number, where dropping them would mislead: 1.5L
/// is not 1.5 of anything small. Small units (ml, g, pcs) are dropped.
const _keptUnits = {'l': 'L', 'kg': 'KG'};

/// No 0/O or 1/I: a tag gets read aloud and retyped.
const _tagAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

final _alnum = RegExp(r'[A-Za-z0-9]+');

/// The SKU for a product, or null while there is no name to build it from.
///
/// [tag] fixes the random part (for tests, and so a form's preview doesn't
/// change on every keystroke); [taken] are SKUs already in use, compared
/// ignoring case — a clash re-rolls the tag.
String? generateSku({
  required String name,
  String? size,
  String? mainCategory,
  String? tag,
  Set<String> taken = const {},
  math.Random? random,
}) {
  final initials = _nameCode(name);
  if (initials.isEmpty) return null;
  final base = '${_categoryCode(mainCategory)}-$initials${_sizeCode(size)}';

  final rng = random ?? math.Random.secure();
  final takenUpper = {for (final t in taken) t.toUpperCase()};
  var candidate = '$base-${tag ?? randomSkuTag(rng)}';
  // 32² tags per base; give up re-rolling long before that could matter.
  for (var i = 0; i < 50 && takenUpper.contains(candidate); i++) {
    candidate = '$base-${randomSkuTag(rng)}';
  }
  return candidate;
}

String randomSkuTag([math.Random? random]) {
  final rng = random ?? math.Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < 2; i++)
      _tagAlphabet.codeUnitAt(rng.nextInt(_tagAlphabet.length)),
  ]);
}

/// Uppercase with no spaces: how any SKU, typed or generated, is stored.
String normalizeSku(String sku) =>
    sku.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

String _categoryCode(String? category) {
  if (category == null || category.trim().isEmpty) return 'GEN';
  final known = _categoryCodes[category.trim().toLowerCase()];
  if (known != null) return known;
  final letters = _alnum.allMatches(category).map((m) => m[0]).join();
  return letters.substring(0, math.min(3, letters.length)).toUpperCase();
}

/// One word: its first three letters ("Coke" → COK). More: the first letter
/// of up to three words ("San Miguel Pale Pilsen" → SMP).
String _nameCode(String name) {
  final words = [for (final m in _alnum.allMatches(name)) m[0]!];
  if (words.isEmpty) return '';
  if (words.length == 1) {
    final w = words.single;
    return w.substring(0, math.min(3, w.length)).toUpperCase();
  }
  return words.take(3).map((w) => w[0]).join().toUpperCase();
}

final _measure = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-zA-Z]*)');

/// `330ml` → 330, `1.5L` → 1.5L, `Large` → L, `Sweet` → SWE, none → ''.
String _sizeCode(String? size) {
  if (size == null || size.trim().isEmpty) return '';
  final text = size.trim();

  final measure = _measure.firstMatch(text);
  if (measure != null) {
    final unit = _keptUnits[measure[2]!.toLowerCase()] ?? '';
    return '${measure[1]}$unit';
  }

  final first = _alnum.firstMatch(text)?[0];
  if (first == null) return '';
  return _sizeWords[first.toLowerCase()] ??
      first.substring(0, math.min(3, first.length)).toUpperCase();
}
