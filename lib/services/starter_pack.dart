/// The Pinoy Sari-Sari Starter Pack: a ready-made catalog so a new store
/// doesn't open on an empty list and 90-odd items of typing.
///
/// What's in it follows where sari-sari money actually goes — detergents,
/// powdered coffee, shampoo, canned fish and instant noodles lead by sales
/// value, so those categories carry the most lines.
///
/// Prices are starting points, not quoted figures: every store prices to its
/// own suki and supplier, and the owner edits them in the catalog. Buy
/// prices sit a little under sell so Analytics has a margin to work with
/// from day one.
///
/// Stock is 0 for every item on purpose. The pack gives the store its
/// catalog; the owner counts their own shelf through Update Stock. Seeding
/// invented counts would put wrong numbers into Analytics immediately.
///
/// Low-stock alerts start off for the same reason: an item the store hasn't
/// stocked yet isn't something to restock. Updating a product's stock is the
/// moment to turn its alerts on.
library;

import 'product_repository.dart';
import 'product_service.dart';

/// Where the bundled category artwork lives.
const _art = 'asset:assets/images/starter';

/// Categories the pack files its items under, each with its illustration.
/// A product with no photo of its own shows its category's drawing until
/// the owner takes a real one.
enum StarterCategory {
  coffee('Coffee & Milk', 'coffee'),
  drinks('Drinks', 'drinks'),
  noodles('Noodles', 'noodles'),
  canned('Canned Goods', 'canned'),
  snacks('Snacks', 'snacks'),
  pantry('Pantry', 'pantry'),
  laundry('Laundry', 'laundry'),
  cleaning('Cleaning', 'cleaning'),
  care('Personal Care', 'care');

  const StarterCategory(this.label, this._art);

  /// The category chip the product is filed under.
  final String label;

  /// The basename of this category's bundled drawing.
  final String _art;
}

/// Pesos to centavos, as the rest of the app counts money.
int _p(num pesos) => (pesos * 100).round();

ProductDraft _item(
  String name,
  StarterCategory category, {
  String? size,
  required num buy,
  required num sell,
}) => ProductDraft(
  name: name,
  size: size,
  categories: [category.label],
  buyCentavos: _p(buy),
  sellCentavos: _p(sell),
  // Off until the owner actually carries the item: every line lands at zero
  // stock, and ninety-odd of them raising alerts at once would bury the
  // handful that really need restocking.
  stockAlerts: false,
  imageUrl: '$_art/${category._art}.webp',
);

/// Every product the pack adds, in the order they land in the catalog.
final List<ProductDraft> starterPack = [
  // ---- Coffee & Milk — second-biggest category by sales value ----
  _item(
    'Kopiko Blanca 3-in-1',
    StarterCategory.coffee,
    size: '25g',
    buy: 10,
    sell: 12,
  ),
  _item(
    'Nescafé Classic Stick',
    StarterCategory.coffee,
    size: '2g',
    buy: 5.5,
    sell: 7,
  ),
  _item(
    'Great Taste White',
    StarterCategory.coffee,
    size: '25g',
    buy: 10,
    sell: 12,
  ),
  _item(
    'Milo Activ-Go',
    StarterCategory.coffee,
    size: '22g',
    buy: 10,
    sell: 12,
  ),
  _item(
    'Bear Brand Powdered Milk',
    StarterCategory.coffee,
    size: '33g',
    buy: 12.5,
    sell: 15,
  ),
  _item('Tang Orange', StarterCategory.coffee, size: '25g', buy: 10, sell: 12),
  _item(
    "Eight O'Clock Juice Drink",
    StarterCategory.coffee,
    size: '25g',
    buy: 8,
    sell: 10,
  ),

  // ---- Drinks ----
  _item('Coke Mismo', StarterCategory.drinks, size: '290ml', buy: 18, sell: 22),
  _item('Coke Sakto', StarterCategory.drinks, size: '200ml', buy: 12, sell: 15),
  _item(
    'Sprite Mismo',
    StarterCategory.drinks,
    size: '290ml',
    buy: 18,
    sell: 22,
  ),
  _item(
    'Royal Tru-Orange',
    StarterCategory.drinks,
    size: '290ml',
    buy: 18,
    sell: 22,
  ),
  _item(
    'Mountain Dew',
    StarterCategory.drinks,
    size: '290ml',
    buy: 18,
    sell: 22,
  ),
  _item(
    'C2 Green Tea Apple',
    StarterCategory.drinks,
    size: '230ml',
    buy: 16,
    sell: 20,
  ),
  _item(
    'Zesto Orange',
    StarterCategory.drinks,
    size: '200ml',
    buy: 9.5,
    sell: 12,
  ),
  _item(
    'Cobra Energy Drink',
    StarterCategory.drinks,
    size: '240ml',
    buy: 21,
    sell: 25,
  ),
  _item(
    'Gatorade Blue Bolt',
    StarterCategory.drinks,
    size: '500ml',
    buy: 38,
    sell: 45,
  ),
  _item(
    'Absolute Distilled Water',
    StarterCategory.drinks,
    size: '500ml',
    buy: 12,
    sell: 15,
  ),

  // ---- Noodles — the fastest-growing category ----
  _item(
    'Lucky Me Pancit Canton Original',
    StarterCategory.noodles,
    size: '60g',
    buy: 15,
    sell: 18,
  ),
  _item(
    'Lucky Me Pancit Canton Chilimansi',
    StarterCategory.noodles,
    size: '60g',
    buy: 15,
    sell: 18,
  ),
  _item(
    'Lucky Me Beef Mami',
    StarterCategory.noodles,
    size: '55g',
    buy: 12.5,
    sell: 15,
  ),
  _item(
    'Payless Xtra Big Pancit Canton',
    StarterCategory.noodles,
    size: '70g',
    buy: 14,
    sell: 17,
  ),
  _item(
    'Nissin Cup Noodles Seafood',
    StarterCategory.noodles,
    size: '60g',
    buy: 27,
    sell: 32,
  ),

  // ---- Canned Goods ----
  _item(
    '555 Sardines Tomato Sauce',
    StarterCategory.canned,
    size: '155g',
    buy: 24,
    sell: 28,
  ),
  _item(
    'Ligo Sardines Green',
    StarterCategory.canned,
    size: '155g',
    buy: 25,
    sell: 30,
  ),
  _item(
    'Century Tuna Flakes in Oil',
    StarterCategory.canned,
    size: '155g',
    buy: 36,
    sell: 42,
  ),
  _item(
    'Argentina Corned Beef',
    StarterCategory.canned,
    size: '150g',
    buy: 32,
    sell: 38,
  ),
  _item(
    'CDO Karne Norte',
    StarterCategory.canned,
    size: '150g',
    buy: 27,
    sell: 32,
  ),
  _item(
    'Purefoods Vienna Sausage',
    StarterCategory.canned,
    size: '130g',
    buy: 30,
    sell: 35,
  ),
  _item(
    'Spam Luncheon Meat',
    StarterCategory.canned,
    size: '340g',
    buy: 160,
    sell: 180,
  ),

  // ---- Snacks ----
  _item(
    'Piattos Cheese',
    StarterCategory.snacks,
    size: '40g',
    buy: 17,
    sell: 20,
  ),
  _item(
    'Nova Country Cheddar',
    StarterCategory.snacks,
    size: '40g',
    buy: 17,
    sell: 20,
  ),
  _item(
    'V-Cut Spicy BBQ',
    StarterCategory.snacks,
    size: '27g',
    buy: 12.5,
    sell: 15,
  ),
  _item('Chippy BBQ', StarterCategory.snacks, size: '27g', buy: 12.5, sell: 15),
  _item(
    'Oishi Prawn Crackers',
    StarterCategory.snacks,
    size: '24g',
    buy: 10,
    sell: 12,
  ),
  _item(
    'Boy Bawang Cornick Garlic',
    StarterCategory.snacks,
    size: '100g',
    buy: 21,
    sell: 25,
  ),
  _item(
    'Rebisco Crackers',
    StarterCategory.snacks,
    size: '32g',
    buy: 6.5,
    sell: 8,
  ),
  _item(
    'Skyflakes Crackers',
    StarterCategory.snacks,
    size: '25g',
    buy: 6.5,
    sell: 8,
  ),
  _item('Fita Crackers', StarterCategory.snacks, size: '30g', buy: 8, sell: 10),
  _item('Hansel Mocha', StarterCategory.snacks, size: '31g', buy: 6.5, sell: 8),
  _item(
    'Cream-O Vanilla',
    StarterCategory.snacks,
    size: '30g',
    buy: 8,
    sell: 10,
  ),
  _item('Mentos Mint', StarterCategory.snacks, size: 'roll', buy: 10, sell: 12),
  _item('Maxx Candy', StarterCategory.snacks, size: 'pc', buy: 1.5, sell: 2),

  // ---- Pantry ----
  _item(
    'Maggi Magic Sarap',
    StarterCategory.pantry,
    size: '8g',
    buy: 5,
    sell: 6,
  ),
  _item(
    'Knorr Sinigang Mix Sampaloc',
    StarterCategory.pantry,
    size: '44g',
    buy: 12.5,
    sell: 15,
  ),
  _item(
    'Ajinomoto Umami Seasoning',
    StarterCategory.pantry,
    size: '11g',
    buy: 4,
    sell: 5,
  ),
  _item(
    'Silver Swan Soy Sauce',
    StarterCategory.pantry,
    size: '200ml',
    buy: 21,
    sell: 25,
  ),
  _item(
    'Datu Puti Vinegar',
    StarterCategory.pantry,
    size: '200ml',
    buy: 18.5,
    sell: 22,
  ),
  _item(
    'UFC Banana Ketchup',
    StarterCategory.pantry,
    size: '200g',
    buy: 27,
    sell: 32,
  ),
  _item(
    'Baguio Cooking Oil',
    StarterCategory.pantry,
    size: '100ml',
    buy: 21,
    sell: 25,
  ),
  _item(
    'White Sugar',
    StarterCategory.pantry,
    size: '1/4 kg',
    buy: 16,
    sell: 20,
  ),
  _item(
    'Rice (Sinandomeng)',
    StarterCategory.pantry,
    size: '1kg',
    buy: 48,
    sell: 55,
  ),
  _item('Egg', StarterCategory.pantry, size: 'pc', buy: 8.5, sell: 10),

  // ---- Laundry — the biggest category by sales value ----
  _item(
    'Surf Powder Cherry Blossom',
    StarterCategory.laundry,
    size: '66g',
    buy: 8,
    sell: 10,
  ),
  _item(
    'Surf Powder Rose',
    StarterCategory.laundry,
    size: '66g',
    buy: 8,
    sell: 10,
  ),
  _item(
    'Tide Powder Original',
    StarterCategory.laundry,
    size: '66g',
    buy: 11,
    sell: 13,
  ),
  _item(
    'Tide Powder Perfect Clean',
    StarterCategory.laundry,
    size: '66g',
    buy: 11,
    sell: 13,
  ),
  _item(
    'Ariel Powder Sunrise Fresh',
    StarterCategory.laundry,
    size: '66g',
    buy: 12.5,
    sell: 15,
  ),
  _item(
    'Breeze Powder',
    StarterCategory.laundry,
    size: '60g',
    buy: 8,
    sell: 10,
  ),
  _item(
    'Wings Powder',
    StarterCategory.laundry,
    size: '90g',
    buy: 6.5,
    sell: 8,
  ),
  _item(
    'Champion Powder',
    StarterCategory.laundry,
    size: '70g',
    buy: 7.5,
    sell: 9,
  ),
  _item(
    'Pride Powder',
    StarterCategory.laundry,
    size: '65g',
    buy: 7.5,
    sell: 9,
  ),
  _item('Calla Powder', StarterCategory.laundry, size: '65g', buy: 8, sell: 10),
  _item(
    'Perla Laundry Bar',
    StarterCategory.laundry,
    size: '90g',
    buy: 12.5,
    sell: 15,
  ),
  _item('Tide Bar', StarterCategory.laundry, size: '125g', buy: 17, sell: 20),
  _item('Surf Bar', StarterCategory.laundry, size: '380g', buy: 27, sell: 32),
  _item('Wings Bar', StarterCategory.laundry, size: '380g', buy: 21, sell: 25),
  _item(
    'Champion Detergent Bar',
    StarterCategory.laundry,
    size: '380g',
    buy: 25,
    sell: 30,
  ),
  _item(
    'Ariel Liquid Sachet',
    StarterCategory.laundry,
    size: '30ml',
    buy: 12.5,
    sell: 15,
  ),
  _item(
    'Surf Liquid Sachet',
    StarterCategory.laundry,
    size: '30ml',
    buy: 10,
    sell: 12,
  ),
  _item(
    'Breeze Liquid Sachet',
    StarterCategory.laundry,
    size: '30ml',
    buy: 10,
    sell: 12,
  ),
  _item(
    'Downy Antibac',
    StarterCategory.laundry,
    size: '25ml',
    buy: 7.5,
    sell: 9,
  ),
  _item(
    'Downy Sunrise Fresh',
    StarterCategory.laundry,
    size: '25ml',
    buy: 7.5,
    sell: 9,
  ),
  _item(
    'Downy Passion',
    StarterCategory.laundry,
    size: '25ml',
    buy: 7.5,
    sell: 9,
  ),
  _item(
    'Surf Fabric Conditioner',
    StarterCategory.laundry,
    size: '25ml',
    buy: 6.5,
    sell: 8,
  ),
  _item(
    'Del Fabric Conditioner',
    StarterCategory.laundry,
    size: '25ml',
    buy: 5.5,
    sell: 7,
  ),
  _item(
    'Champion Fabcon',
    StarterCategory.laundry,
    size: '25ml',
    buy: 5.5,
    sell: 7,
  ),
  _item(
    'Zonrox Original',
    StarterCategory.laundry,
    size: '100ml',
    buy: 12.5,
    sell: 15,
  ),
  _item(
    'Zonrox Original',
    StarterCategory.laundry,
    size: '250ml',
    buy: 25,
    sell: 30,
  ),
  _item(
    'Zonrox Color Safe',
    StarterCategory.laundry,
    size: '100ml',
    buy: 15,
    sell: 18,
  ),

  // ---- Cleaning ----
  _item(
    'Joy Antibac Dishwashing',
    StarterCategory.cleaning,
    size: '45ml',
    buy: 7.5,
    sell: 9,
  ),
  _item(
    'Joy Lemon Dishwashing',
    StarterCategory.cleaning,
    size: '100ml',
    buy: 30,
    sell: 35,
  ),
  _item(
    'Smart Dishwashing Liquid',
    StarterCategory.cleaning,
    size: '45ml',
    buy: 5.5,
    sell: 7,
  ),
  _item(
    'Axion Dishwashing Paste',
    StarterCategory.cleaning,
    size: '190g',
    buy: 30,
    sell: 35,
  ),
  _item(
    'Dishwashing Sponge',
    StarterCategory.cleaning,
    size: 'pc',
    buy: 7.5,
    sell: 10,
  ),
  _item(
    'Scotch-Brite Scouring Pad',
    StarterCategory.cleaning,
    size: 'pc',
    buy: 12,
    sell: 15,
  ),
  _item(
    'Domex Toilet Cleaner',
    StarterCategory.cleaning,
    size: '90ml',
    buy: 21,
    sell: 25,
  ),
  _item(
    'Baygon Multi-Insect Spray',
    StarterCategory.cleaning,
    size: '250ml',
    buy: 132,
    sell: 150,
  ),
  _item(
    'Katol Mosquito Coil',
    StarterCategory.cleaning,
    size: 'pack',
    buy: 10,
    sell: 12,
  ),
  _item(
    'Albatross Deodorizer',
    StarterCategory.cleaning,
    size: 'pc',
    buy: 21,
    sell: 25,
  ),
  _item('Candle', StarterCategory.cleaning, size: 'pc', buy: 8, sell: 10),
  _item('Trash Bag', StarterCategory.cleaning, size: 'pc', buy: 12, sell: 15),

  // ---- Personal Care — shampoo is third by sales value ----
  _item(
    'Safeguard Classic White',
    StarterCategory.care,
    size: '60g',
    buy: 25,
    sell: 30,
  ),
  _item(
    'Palmolive Shampoo',
    StarterCategory.care,
    size: '12ml',
    buy: 6.5,
    sell: 8,
  ),
  _item(
    'Sunsilk Shampoo',
    StarterCategory.care,
    size: '12ml',
    buy: 6.5,
    sell: 8,
  ),
  _item(
    'Head & Shoulders Shampoo',
    StarterCategory.care,
    size: '12ml',
    buy: 8,
    sell: 10,
  ),
  _item(
    'Colgate Toothpaste',
    StarterCategory.care,
    size: '25g',
    buy: 21,
    sell: 25,
  ),
  _item(
    'Closeup Toothpaste',
    StarterCategory.care,
    size: '25g',
    buy: 21,
    sell: 25,
  ),
  _item(
    'Rexona Roll-on',
    StarterCategory.care,
    size: '25ml',
    buy: 38,
    sell: 45,
  ),
  _item('Modess Napkin', StarterCategory.care, size: '8s', buy: 30, sell: 35),
  _item('Cotton Buds', StarterCategory.care, size: 'pack', buy: 12, sell: 15),
];

/// The categories the pack files products under, for the form's chips.
final List<String> starterCategories = [
  for (final category in StarterCategory.values) category.label,
];

/// Fills a brand-new store's catalog with the pack.
///
/// The store has no products yet, so nothing is skipped and the repository
/// never needs its listeners: it is used only to write, and closed again
/// straight after. Writes are queued by Firestore, so this finishes with no
/// connection and reaches the server later.
Future<void> seedStarterPack(String storeId) async {
  final products = ProductRepository.forStore(storeId);
  try {
    await products.addAllMissing(starterPack);
  } finally {
    await products.dispose();
  }
}
