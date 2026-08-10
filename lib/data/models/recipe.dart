import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/search_text.dart';
import 'user_profile.dart';

enum RecipeStatus { draft, published, hidden }

enum Difficulty { easy, medium, hard }

enum CostBand { cheap, medium, occasion }

/// The regions Iraqi cooks actually argue about. This is a first-class tag, not
/// a nice-to-have: whose kubba, whose pacha, dolma with دبس رمان or without.
enum Region {
  baghdadi,
  mosuli,
  basrawi,
  anbari,
  kurdishErbil,
  kurdishSulaymaniyah,
  kurdishDuhok,
  turkmenKirkuk,
  general,
}

/// Local measures sit alongside metric. [grams] is the canonical value used for
/// scaling and shopping-list merging; the user still sees the unit they typed.
enum Unit {
  istikan(grams: 100), // استكان — the tea glass, ~100ml
  finjan(grams: 60), // فنجان
  cup(grams: 240), // كوب
  tablespoon(grams: 15),
  teaspoon(grams: 5),
  gram(grams: 1),
  kilo(grams: 1000),
  ml(grams: 1),
  litre(grams: 1000),
  piece(grams: 0), // 0 = doesn't convert; never merge these
  pinch(grams: 0),
  toTaste(grams: 0);

  const Unit({required this.grams});

  /// Approximate mass of one unit, or 0 when it has no sensible conversion.
  final double grams;

  bool get isConvertible => grams > 0;
}

class Ingredient {
  const Ingredient({
    required this.item,
    this.quantity,
    this.unit = Unit.toTaste,
    this.group,
    this.note,
    this.itemId,
    this.hardToFind = false,
  });

  final String item;
  final double? quantity;
  final Unit unit;

  /// "for the filling" / "for the sauce" — ingredients are grouped in the UI.
  final String? group;

  /// Substitution advice: "no mascarpone → قيمر works". Recipes calling for
  /// things you can't buy in Iraq are useless, so this is prominent, not hidden.
  final String? note;

  /// Links to `ingredients/{id}` so shopping lists can merge and substitutions
  /// can be suggested. Null while the author is typing something unrecognised.
  final String? itemId;

  final bool hardToFind;

  double? get canonicalGrams =>
      (quantity != null && unit.isConvertible) ? quantity! * unit.grams : null;

  /// Scales for a different number of servings. Salt, spice, and leavening are
  /// deliberately *not* handled here — those don't scale linearly and the UI
  /// warns about them instead of silently getting them wrong.
  Ingredient scaled(double factor) => quantity == null
      ? this
      : Ingredient(
          item: item,
          quantity: quantity! * factor,
          unit: unit,
          group: group,
          note: note,
          itemId: itemId,
          hardToFind: hardToFind,
        );

  factory Ingredient.fromMap(Map<String, dynamic> map) => Ingredient(
    item: map['item'] as String? ?? '',
    quantity: (map['quantity'] as num?)?.toDouble(),
    unit: Unit.values.firstWhere(
      (u) => u.name == map['unit'],
      orElse: () => Unit.toTaste,
    ),
    group: map['group'] as String?,
    note: map['note'] as String?,
    itemId: map['itemId'] as String?,
    hardToFind: map['hardToFind'] as bool? ?? false,
  );

  Map<String, dynamic> toMap() => {
    'item': item,
    if (quantity != null) 'quantity': quantity,
    'unit': unit.name,
    if (group != null) 'group': group,
    if (note != null) 'note': note,
    if (itemId != null) 'itemId': itemId,
    if (hardToFind) 'hardToFind': true,
    if (canonicalGrams != null) 'canonicalGrams': canonicalGrams,
  };
}

class RecipeStep {
  const RecipeStep({
    required this.text,
    this.imageUrl,
    this.audioUrl,
    this.timerSeconds,
  });

  final String text;
  final String? imageUrl;

  /// Voice narration. Typing Arabic and especially Kurdish on a phone is slow,
  /// and the best contributors are often people who won't do it — so any step
  /// can be spoken instead of written.
  final String? audioUrl;

  /// Drives an inline countdown chip in cook mode.
  final int? timerSeconds;

  factory RecipeStep.fromMap(Map<String, dynamic> map) => RecipeStep(
    text: map['text'] as String? ?? '',
    imageUrl: map['imageUrl'] as String?,
    audioUrl: map['audioUrl'] as String?,
    timerSeconds: (map['timerSeconds'] as num?)?.toInt(),
  );

  Map<String, dynamic> toMap() => {
    'text': text,
    if (imageUrl != null) 'imageUrl': imageUrl,
    if (audioUrl != null) 'audioUrl': audioUrl,
    if (timerSeconds != null) 'timerSeconds': timerSeconds,
  };
}

class RecipeStats {
  const RecipeStats({
    this.views = 0,
    this.uniqueViewers = 0,
    this.likes = 0,
    this.saves = 0,
    this.cooked = 0,
    this.comments = 0,
  });

  final int views;
  final int uniqueViewers;
  final int likes;
  final int saves;

  /// "I cooked this" — the strongest signal in the app, and weighted highest
  /// in ranking. A save is intent; cooked is proof.
  final int cooked;
  final int comments;

  factory RecipeStats.fromMap(Map<String, dynamic>? map) => RecipeStats(
    views: (map?['views'] as num?)?.toInt() ?? 0,
    uniqueViewers: (map?['uniqueViewers'] as num?)?.toInt() ?? 0,
    likes: (map?['likes'] as num?)?.toInt() ?? 0,
    saves: (map?['saves'] as num?)?.toInt() ?? 0,
    cooked: (map?['cooked'] as num?)?.toInt() ?? 0,
    comments: (map?['comments'] as num?)?.toInt() ?? 0,
  );
}

class Recipe {
  const Recipe({
    required this.id,
    required this.author,
    required this.title,
    required this.language,
    this.description,
    this.coverUrl,
    this.gallery = const [],
    this.region = Region.general,
    this.tags = const [],
    this.occasions = const [],
    this.difficulty = Difficulty.easy,
    this.costBand = CostBand.medium,
    this.prepMinutes = 0,
    this.cookMinutes = 0,
    this.servings = 4,
    this.ingredients = const [],
    this.steps = const [],
    this.status = RecipeStatus.draft,
    this.stats = const RecipeStats(),
    this.score = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final AuthorStub author;
  final String title;

  /// Content language, separate from the reader's UI language. Someone may
  /// want a Kurdish interface and Arabic recipes, or the reverse.
  final String language;

  final String? description;
  final String? coverUrl;
  final List<String> gallery;
  final Region region;
  final List<String> tags;
  final List<String> occasions;
  final Difficulty difficulty;
  final CostBand costBand;
  final int prepMinutes;
  final int cookMinutes;
  final int servings;
  final List<Ingredient> ingredients;
  final List<RecipeStep> steps;
  final RecipeStatus status;
  final RecipeStats stats;

  /// Ranking score, written only by the scheduled Function. See the plan's
  /// ranking section: freshness × (engagement + qualityFloor) × authorMultiplier.
  final double score;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get totalMinutes => prepMinutes + cookMinutes;

  /// Ingredients rescaled for [targetServings]. Iraqi hospitality means
  /// cooking for twenty is normal, not an edge case.
  List<Ingredient> ingredientsFor(int targetServings) {
    if (servings <= 0 || targetServings == servings) return ingredients;
    final factor = targetServings / servings;
    return ingredients.map((i) => i.scaled(factor)).toList(growable: false);
  }

  /// Things that don't scale linearly. The UI shows this as a warning rather
  /// than silently multiplying and producing something inedible.
  bool get hasNonLinearScaling =>
      ingredients.any((i) => !i.unit.isConvertible) || cookMinutes > 60;

  factory Recipe.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    return Recipe(
      id: doc.id,
      author: AuthorStub.fromMap(
        Map<String, dynamic>.from(data['author'] as Map? ?? const {}),
      ),
      title: data['title'] as String? ?? '',
      language: data['language'] as String? ?? 'ar',
      description: data['description'] as String?,
      coverUrl: data['coverUrl'] as String?,
      gallery: (data['gallery'] as List?)?.cast<String>() ?? const [],
      region: Region.values.firstWhere(
        (r) => r.name == data['region'],
        orElse: () => Region.general,
      ),
      tags: (data['tags'] as List?)?.cast<String>() ?? const [],
      occasions: (data['occasions'] as List?)?.cast<String>() ?? const [],
      difficulty: Difficulty.values.firstWhere(
        (d) => d.name == data['difficulty'],
        orElse: () => Difficulty.easy,
      ),
      costBand: CostBand.values.firstWhere(
        (c) => c.name == data['costBand'],
        orElse: () => CostBand.medium,
      ),
      prepMinutes: (data['prepMinutes'] as num?)?.toInt() ?? 0,
      cookMinutes: (data['cookMinutes'] as num?)?.toInt() ?? 0,
      servings: (data['servings'] as num?)?.toInt() ?? 4,
      ingredients: (data['ingredients'] as List? ?? const [])
          .map((i) => Ingredient.fromMap(Map<String, dynamic>.from(i as Map)))
          .toList(growable: false),
      steps: (data['steps'] as List? ?? const [])
          .map((s) => RecipeStep.fromMap(Map<String, dynamic>.from(s as Map)))
          .toList(growable: false),
      status: RecipeStatus.values.firstWhere(
        (s) => s.name == data['status'],
        orElse: () => RecipeStatus.draft,
      ),
      stats: RecipeStats.fromMap(data['stats'] as Map<String, dynamic>?),
      score: (data['score'] as num?)?.toDouble() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// `stats` and `score` are absent: both are Function-owned, and the security
  /// rules reject a client write that touches either.
  Map<String, dynamic> toMap() => {
    'author': author.toMap(),
    'title': title,
    'language': language,
    if (description != null) 'description': description,
    if (coverUrl != null) 'coverUrl': coverUrl,
    'gallery': gallery,
    'region': region.name,
    'tags': tags,
    'occasions': occasions,
    'difficulty': difficulty.name,
    'costBand': costBand.name,
    'prepMinutes': prepMinutes,
    'cookMinutes': cookMinutes,
    'servings': servings,
    'ingredients': ingredients.map((i) => i.toMap()).toList(),
    'steps': steps.map((s) => s.toMap()).toList(),
    'status': status.name,
    'keywords': keywords,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  /// Search tokens, computed at write time with the same normaliser the query
  /// side uses. Built from title, description, tags, and ingredient names, so
  /// "دولمة" and "باذنجان" both find the same recipe.
  List<String> get keywords => searchKeywords(
    [
      title,
      description ?? '',
      ...tags,
      ...ingredients.map((i) => i.item),
    ].join(' '),
    script: scriptForLanguage(language),
  );

  Recipe copyWith({
    String? title,
    String? description,
    String? coverUrl,
    List<Ingredient>? ingredients,
    List<RecipeStep>? steps,
    RecipeStatus? status,
    int? servings,
  }) => Recipe(
    id: id,
    author: author,
    title: title ?? this.title,
    language: language,
    description: description ?? this.description,
    coverUrl: coverUrl ?? this.coverUrl,
    gallery: gallery,
    region: region,
    tags: tags,
    occasions: occasions,
    difficulty: difficulty,
    costBand: costBand,
    prepMinutes: prepMinutes,
    cookMinutes: cookMinutes,
    servings: servings ?? this.servings,
    ingredients: ingredients ?? this.ingredients,
    steps: steps ?? this.steps,
    status: status ?? this.status,
    stats: stats,
    score: score,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
