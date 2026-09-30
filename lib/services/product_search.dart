import 'dart:math' as math;

import 'product_service.dart';

/// A product that matched a search, with the parts of its name to highlight.
class ProductMatch {
  const ProductMatch(this.product, this.highlights, this.score);

  final Product product;

  /// `[start, end)` ranges in [Product.name], sorted and non-overlapping.
  final List<(int, int)> highlights;

  /// Lower is a better match.
  final int score;
}

/// Finds products the way a cashier types: fast, abbreviated and misspelled.
///
/// Every word of [query] has to land on some word of the product's name or
/// its SKU, in any order. A word lands when it is
/// - the start of a word — "san mig" finds San Miguel,
/// - inside a word, from two letters up — "guel",
/// - or close to the start of a word, allowing one typo from three letters
///   and two from six — "san migz", "pilsn", "miguell".
///
/// Squashed-together input also works: "sanmig" finds San Miguel.
///
/// Results come best first: exact and prefix hits before typo hits, and
/// ties in catalog order.
List<ProductMatch> searchProducts(List<Product> products, String query) {
  final tokens = _words(query).map((w) => w.text).toList();
  if (tokens.isEmpty) return const [];
  final squashed = tokens.join();

  final matches = <ProductMatch>[];
  for (final product in products) {
    final match = _match(product, tokens, squashed);
    if (match != null) matches.add(match);
  }
  // List.sort is not stable; the index keeps catalog order within a score.
  final order = {for (final (i, p) in products.indexed) p.id: i};
  matches.sort((a, b) {
    final byScore = a.score.compareTo(b.score);
    return byScore != 0
        ? byScore
        : order[a.product.id]!.compareTo(order[b.product.id]!);
  });
  return matches;
}

class _Word {
  const _Word(this.text, this.start);
  final String text;
  final int start;
}

final _wordPattern = RegExp(r'[\p{L}\p{N}]+', unicode: true);

List<_Word> _words(String text) => [
  for (final m in _wordPattern.allMatches(text.toLowerCase()))
    _Word(m[0]!, m.start),
];

ProductMatch? _match(Product product, List<String> tokens, String squashed) {
  final nameWords = _words(product.name);
  final skuWords = _words(product.sku ?? '');

  var score = 0;
  final highlights = <(int, int)>[];
  var allMatched = true;
  for (final token in tokens) {
    final hit = _bestHit(token, nameWords) ?? _bestHit(token, skuWords);
    if (hit == null) {
      allMatched = false;
      break;
    }
    score += hit.score;
    if (nameWords.contains(hit.word)) highlights.add(hit.range);
  }

  if (!allMatched) {
    // "sanmig": the name with its spaces and punctuation taken out.
    if (tokens.length != 1 || squashed.length < 3) return null;
    final joined = nameWords.map((w) => w.text).join();
    final at = joined.indexOf(squashed);
    if (at < 0) return null;
    return ProductMatch(product, _joinedRange(nameWords, at, squashed), 2);
  }

  // A search that starts where the name starts reads as the better hit.
  if (nameWords.isNotEmpty && !nameWords.first.text.startsWith(tokens.first)) {
    score += 1;
  }
  return ProductMatch(product, _merge(highlights), score);
}

class _Hit {
  const _Hit(this.word, this.range, this.score);
  final _Word word;
  final (int, int) range;
  final int score;
}

_Hit? _bestHit(String token, List<_Word> words) {
  _Hit? best;
  for (final word in words) {
    final hit = _hit(token, word);
    if (hit != null && (best == null || hit.score < best.score)) best = hit;
  }
  return best;
}

/// Scores: 0 whole word, 1 prefix, 3 inside a word, 4+ typo.
_Hit? _hit(String token, _Word word) {
  final text = word.text;
  final start = word.start;
  if (text == token) return _Hit(word, (start, start + text.length), 0);
  if (text.startsWith(token)) {
    return _Hit(word, (start, start + token.length), 1);
  }
  if (token.length >= 2) {
    final at = text.indexOf(token);
    if (at >= 0) {
      return _Hit(word, (start + at, start + at + token.length), 3);
    }
  }

  final allowed = token.length >= 6
      ? 2
      : token.length >= 3
      ? 1
      : 0;
  if (allowed == 0) return null;
  // Compare against the word's opening letters, a letter either way, so a
  // dropped or extra letter still counts: "migz" ~ "migu(el)".
  _Hit? best;
  for (var len = token.length - 1; len <= token.length + 1; len++) {
    if (len < 1 || len > text.length) continue;
    final d = _distance(token, text.substring(0, len));
    if (d <= allowed && (best == null || 4 + d < best.score)) {
      best = _Hit(word, (start, start + len), 4 + d);
    }
  }
  return best;
}

/// Optimal-string-alignment distance: edits, counting a swap of two
/// neighbouring letters ("teh") as one.
int _distance(String a, String b) {
  final d = List.generate(
    a.length + 1,
    (i) =>
        List<int>.generate(b.length + 1, (j) => i == 0 ? j : (j == 0 ? i : 0)),
  );
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      var v = math.min(
        math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
        d[i - 1][j - 1] + cost,
      );
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        v = math.min(v, d[i - 2][j - 2] + 1);
      }
      d[i][j] = v;
    }
  }
  return d[a.length][b.length];
}

/// Maps a match in the words-joined name back to ranges in the real name.
List<(int, int)> _joinedRange(List<_Word> words, int at, String squashed) {
  final ranges = <(int, int)>[];
  var offset = 0;
  final end = at + squashed.length;
  for (final word in words) {
    final wordEnd = offset + word.text.length;
    final from = math.max(at, offset);
    final to = math.min(end, wordEnd);
    if (from < to) {
      ranges.add((word.start + from - offset, word.start + to - offset));
    }
    offset = wordEnd;
  }
  return ranges;
}

List<(int, int)> _merge(List<(int, int)> ranges) {
  final sorted = [...ranges]..sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in sorted) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, math.max(last.$2, r.$2)));
    } else {
      merged.add(r);
    }
  }
  return merged;
}
