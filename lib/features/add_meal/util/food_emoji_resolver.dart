/// Maps a food's head noun (first comma-separated token of the
/// description) to a representative emoji. Rendered as a Text widget so the
/// platform's color emoji font draws it — Apple Color Emoji on iOS, Noto
/// Color Emoji on Android.
///
/// Lookup is name-only — no category fallback. USDA descriptions follow
/// `Head noun, qualifier, qualifier, …`, so the first token is the
/// real identity of the food ("Milk, fluid, nonfat..." → "milk").
/// The only caller applies this to FDC base-food items; OFF products are
/// branded, so they keep their placeholder icon rather than risk a
/// misleading head-noun match.
///
/// Returns `null` when the head noun isn't in the curated map — callers
/// should fall back to their existing iconography. Keeping the map small
/// and curated avoids a long-tail with mismatched emoji ("seaweed" → 🌿
/// looks wrong; we'd rather show no emoji than a misleading one).
String? resolveFoodEmoji(String? name) {
  if (name == null || name.isEmpty) return null;
  final head = name.split(',').first.trim().toLowerCase();
  if (head.isEmpty) return null;
  return _nounToEmoji[head];
}

/// Source of truth: each emoji owns the head nouns it should match.
/// Grouping by emoji makes duplicates obvious at a glance and keeps the
/// noun→emoji direction easy to extend (just append to the right list).
///
/// **Plural and spacing variants are generated automatically** by
/// [_variantsOf] when building [_nounToEmoji]: a regular `+s` plural and,
/// for multi-word nouns, the same forms with spaces collapsed
/// ("olive oil" → also matches "oliveoil" / "oliveoils"). So only list
/// the canonical singular here. Irregular plurals (-ies, -oes, fungus→fungi)
/// must still be listed explicitly because the variant generator only
/// handles regular cases.
const Map<String, List<String>> _emojiToNouns = {
  // dairy + eggs
  '🥛': [
    'milk',
    'cream',
    'buttermilk',
    'almond milk',
    'soy milk',
    'coconut milk',
    'rice milk',
    'oat milk',
  ],
  '🧀': ['cheese'],
  '🍦': ['yogurt', 'yoghurt', 'ice cream', 'frozen yogurt', 'milk dessert'],
  '🧈': ['butter', 'almond butter', 'sesame butter'],
  '🥚': ['egg'],

  // meat
  '🥩': ['beef', 'bison', 'venison', 'goat'],
  '🥓': ['pork', 'bacon'],
  '🍖': ['lamb', 'veal', 'game meat', 'ham'],
  '🍗': ['chicken'],
  '🦃': ['turkey'],
  '🦆': ['duck'],
  '🌭': ['sausage', 'hot dog'],

  // seafood
  '🐟': [
    'fish',
    'salmon',
    'tuna',
    'sea bass',
    'cod',
    'herring',
    'mackerel',
    'sardine',
    'fish oil',
  ],
  '🦐': ['shrimp', 'crustacean'],
  '🦀': ['crab', 'crab meat', 'seafood'],
  '🦞': ['lobster'],
  '🦪': ['mollusk', 'oyster', 'scallop', 'clam'],
  '🦑': ['squid'],
  '🍤': ['fried shrimp', 'tempura'],

  // grains + bread
  '🍞': ['bread'],
  '🥖': ['baguette'],
  '🥯': ['bagel'],
  '🥐': ['croissant'],
  '🍚': ['rice', 'wild rice', 'rice flour'],
  '🍝': ['pasta', 'spaghetti'],
  '🍜': ['noodle', 'ramen'],
  '🥣': ['cereal', 'cereals ready-to-eat', 'oatmeal'],
  '🌾': [
    'wheat flour',
    'oat',
    'bulgur',
    'couscous',
    'quinoa',
    'buckwheat',
    'buckwheat flour',
  ],
  '🥞': ['pancake', 'crepe'],
  '🧇': ['waffle'],
  '🫓': ['tortilla', 'flatbread'],

  // vegetables
  '🥔': ['potato', 'potatoes', 'potato flour'],
  '🍠': ['sweet potato', 'sweet potatoes', 'sweet potato flour'],
  '🌽': ['corn', 'maize', 'corn flour'],
  '🍅': ['tomato', 'tomatoes'],
  '🧅': [
    'onion',
    'shallot',
    'leek',
    'onion powder',
    'onion flake',
    'onion ring',
  ],
  '🧄': ['garlic', 'garlic powder'],
  '🥕': ['carrot'],
  '🥦': ['broccoli'],
  '🥬': ['cabbage', 'lettuce', 'salad green', 'greens', 'celery'],
  '🍃': ['spinach', 'kale', 'rucola', 'arugula', 'collard green'],
  '🥒': ['cucumber', 'pickle', 'zucchini', 'courgette'],
  '🌶️': ['pepper', 'chili'],
  '🍄': ['mushroom', 'fungus', 'fungi', 'truffle'],
  '🍆': ['eggplant', 'aubergine'],
  '🎃': ['squash', 'pumpkin', 'pumpkin flour'],
  '🥑': ['avocado', 'guacamole'],
  '🟢': [
    'pea',
    'pod',
    'edamame',
    'fava bean',
    'soybean',
    'soybean flour',
    'pea flour',
  ],
  '🫘': [
    'bean',
    'red bean',
    'black bean',
    'lima bean',
    'chickpea',
    'mung bean',
    'lentil',
  ],
  '🎍': ['bamboo shoot', 'asparagus'],
  '🌱': ['sprout', 'microgreen'],

  // fruit
  '🍎': ['apple', 'fruit salad'],
  '🍌': ['banana'],
  '🍊': ['orange', 'clementine', 'mandarin'],
  '🍋': ['lemon', 'lime'],
  '🍇': ['grape'],
  '🍓': ['strawberry', 'strawberries', 'raspberry', 'raspberries'],
  '🫐': ['blueberry', 'blueberries', 'blackberry', 'blackberries'],
  '🍒': ['cherry', 'cherries'],
  '🍉': ['watermelon'],
  '🍈': ['melon'],
  '🍍': ['pineapple'],
  '🥭': ['mango'],
  '🍑': ['peach', 'peaches', 'nectarine', 'apricot'],
  '🍐': ['pear'],
  '🥝': ['kiwi', 'kiwifruit'],
  '🥥': ['coconut', 'coconut water', 'coconut flour'],

  // nuts + seeds
  '🥜': ['nut', 'peanut', 'almond', 'walnut'],
  '🌰': [
    'seed',
    'chestnut',
    'chia seed',
    'flaxseed',
    'hemp seed',
    'sesame seed',
    'sunflower seed',
    'pumpkin seed',
  ],

  // sweets
  '🍬': ['candy', 'candies', 'sugar'],
  '🍫': ['chocolate', 'baking chocolate', 'cocoa', 'brownie'],
  '🍪': ['cookie', 'biscuit'],
  '🍰': ['cake', 'dessert', 'flan'],
  '🥧': ['pie', 'egg custard'],
  '🍩': ['donut', 'doughnut'],
  '🧁': ['cupcake', 'muffin'],
  '🍮': ['pudding'],
  '🍯': ['honey', 'syrup'],

  // fats + oils
  '🫒': ['oil', 'olive oil', 'olive'],

  // snacks
  '🍿': ['popcorn'],
  '🥨': ['pretzel', 'cracker'],
  '🍟': ['chip', 'fries', 'french fries', 'potato chip'],

  // composed dishes
  '🍕': ['pizza'],
  '🍔': ['burger', 'hamburger', 'fast food'],
  '🥪': ['sandwich', 'toast', 'french toast'],
  '🌮': ['taco'],
  '🌯': [
    'burrito',
    'wrap',
    'kebab',
    'gyro',
    'shawarma',
    'doner',
    'falafel wrap',
    'döner',
    'dürüm',
    'doner kebab',
  ],
  '🍛': ['curry', 'curry powder', 'butter chicken', 'biriyani'],
  '🧆': ['falafel'],
  '🍣': ['sushi', 'sashimi', 'nigiri', 'maki'],
  '🍙': ['rice ball', 'onigiri'],
  '🍘': ['rice cracker', 'senbei'],
  '🍲': ['soup', 'stew', 'chicken noodle'],
  '🥗': ['salad', 'salad dressing'],
  '🥟': ['dumpling', 'ravioli', 'pierogi'],
  '🍳': ['egg dish', 'omelette', 'frittata', 'quiche', 'fried egg'],

  // beverages
  '☕': ['coffee'],
  '🍵': ['tea'],
  '💧': ['water'],
  '🧃': [
    'juice',
    'orange juice',
    'apple juice',
    'grape juice',
    'grapefruit juice',
    'vegetable juice',
    'lemon juice',
    'lime juice',
    'cherry juice',
    'fruit juice',
    'carrot juice',
    'blackberry juice',
    'blueberry juice',
    'strawberry juice',
    'tomato juice',
    'cranberry juice',
  ],
  '🥤': ['soda', 'milkshake', 'beverage'],
  '🍺': ['beer'],
  '🍷': ['wine'],
  '🍸': ['cocktail'],
  '🥃': ['whiskey'],

  // baby and other
  '🍼': ['infant formula', 'babyfood'],
  '🧬': ['protein', 'protein powder', 'amino acid', 'supplement', 'rennin'],

  // condiments + others
  '🧂': ['salt'],
  '🥫': ['sauce', 'condiment', 'ketchup'],
  '🌿': [
    'spice',
    'cinnamon',
    'nutmeg',
    'clove',
    'cardamom',
    'cumin',
    'coriander',
    'paprika',
    'turmeric',
    'ginger',
  ],
};

/// For each entry in [_emojiToNouns], yield the canonical noun plus its
/// regular `+s` plural; for multi-word nouns, also yield the no-space
/// form and its `+s` plural. This way "egg" auto-matches "eggs",
/// "olive oil" auto-matches "olive oils" / "oliveoil" / "oliveoils".
Iterable<String> _variantsOf(String noun) sync* {
  yield noun;
  yield '${noun}s';
  if (noun.contains(' ')) {
    final flat = noun.replaceAll(' ', '');
    yield flat;
    yield '${flat}s';
  }
}

/// Reverse-lookup table built once at module init. Marked `final` rather
/// than `const` because [_variantsOf] uses `sync*` which isn't
/// const-eligible. Build cost is a single pass at first use.
final Map<String, String> _nounToEmoji = {
  for (final entry in _emojiToNouns.entries)
    for (final noun in entry.value)
      for (final variant in _variantsOf(noun)) variant: entry.key,
};
