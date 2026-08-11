import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/search_text.dart';
import '../models/recipe.dart';

class RecipeRepository {
  RecipeRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _recipes =>
      _firestore.collection('recipes');

  static const _pageSize = 20;

  // --- reading -------------------------------------------------------------

  Stream<Recipe?> watchRecipe(String id) => _recipes
      .doc(id)
      .snapshots()
      .map((doc) => doc.exists ? Recipe.fromDoc(doc) : null);

  /// Discover: ranked. The verified boost lives inside `score`, computed by the
  /// nightly Function, so this stays a single indexed query.
  ///
  /// Density capping — no more than one verified item every three or four
  /// slots — happens when the feed is assembled, not here. Doing it in the
  /// query would mean over-fetching and paying reads for what you discard.
  Future<List<Recipe>> discoverPage({DocumentSnapshot? startAfter}) {
    Query<Map<String, dynamic>> query = _recipes
        .where('status', isEqualTo: RecipeStatus.published.name)
        .orderBy('score', descending: true)
        .limit(_pageSize);

    if (startAfter != null) query = query.startAfterDocument(startAfter);
    return query.get().then((s) => s.docs.map(Recipe.fromDoc).toList());
  }

  /// Following: strictly chronological, no ranking, no boost, no exceptions.
  /// If people can't trust that following someone means seeing their posts,
  /// following stops meaning anything.
  ///
  /// `whereIn` caps at 30, so callers page through the follow list in chunks.
  Future<List<Recipe>> followingPage({
    required List<String> authorIds,
    DocumentSnapshot? startAfter,
  }) {
    if (authorIds.isEmpty) return Future.value(const []);

    Query<Map<String, dynamic>> query = _recipes
        .where('status', isEqualTo: RecipeStatus.published.name)
        .where('author.uid', whereIn: authorIds.take(30).toList())
        .orderBy('createdAt', descending: true)
        .limit(_pageSize);

    if (startAfter != null) query = query.startAfterDocument(startAfter);
    return query.get().then((s) => s.docs.map(Recipe.fromDoc).toList());
  }

  /// Keyword search over the denormalised `keywords` array.
  ///
  /// The query is normalised with the same function that built the stored
  /// tokens — that shared normalisation is the entire reason this works
  /// without a search service. See [searchQueryTokens].
  Future<List<Recipe>> search(
    String query, {
    String language = 'ar',
    Region? region,
    int limit = 30,
  }) async {
    final tokens = searchQueryTokens(query, script: scriptForLanguage(language));
    if (tokens.isEmpty) return const [];

    Query<Map<String, dynamic>> q = _recipes
        .where('status', isEqualTo: RecipeStatus.published.name)
        .where('keywords', arrayContainsAny: tokens);

    if (region != null) q = q.where('region', isEqualTo: region.name);

    final snapshot = await q.orderBy('score', descending: true).limit(limit).get();
    return snapshot.docs.map(Recipe.fromDoc).toList();
  }

  /// Seasonal hubs — Ramadan iftar, Eid sweets, Ashura, Newroz. Curated by
  /// hand and switched from Remote Config; the biggest retention lever there is.
  Future<List<Recipe>> byOccasion(String occasion, {int limit = 30}) async {
    final snapshot = await _recipes
        .where('status', isEqualTo: RecipeStatus.published.name)
        .where('occasions', arrayContains: occasion)
        .orderBy('score', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs.map(Recipe.fromDoc).toList();
  }

  /// Everything a person has written, drafts included when they're the author.
  Stream<List<Recipe>> watchUserRecipes(String uid, {bool includeDrafts = false}) {
    Query<Map<String, dynamic>> query = _recipes.where('author.uid', isEqualTo: uid);
    if (!includeDrafts) {
      query = query.where('status', isEqualTo: RecipeStatus.published.name);
    }
    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(Recipe.fromDoc).toList());
  }

  /// Resolves the recipes linked from a weekly plan — the input to the
  /// shopping list. `whereIn` caps at 30, which is well past a plausible week.
  Future<List<Recipe>> byIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final snapshot = await _recipes
        .where(FieldPath.documentId, whereIn: ids.take(30).toList())
        .get();
    return snapshot.docs.map(Recipe.fromDoc).toList();
  }

  // --- writing -------------------------------------------------------------

  /// Creates a draft and returns its id, so the composer can save after every
  /// field without the user having to think about it.
  Future<String> createDraft(Recipe recipe) async {
    final doc = _recipes.doc();
    await doc.set({
      ...recipe.toMap(),
      'status': RecipeStatus.draft.name,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Future<void> update(Recipe recipe) =>
      _recipes.doc(recipe.id).set(recipe.toMap(), SetOptions(merge: true));

  Future<void> publish(Recipe recipe) => _recipes.doc(recipe.id).set({
    ...recipe.toMap(),
    'status': RecipeStatus.published.name,
    'publishedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  Future<void> delete(String id) => _recipes.doc(id).delete();

  // --- interactions --------------------------------------------------------
  //
  // The like/save/cooked documents *are* the record — "who liked this" is a
  // paginated query over them, at no extra storage cost. Only the counters are
  // Function-owned, because a client that can write its own like count will.

  Future<void> setLiked({
    required String recipeId,
    required String uid,
    required bool liked,
  }) {
    final doc = _recipes.doc(recipeId).collection('likes').doc(uid);
    return liked
        ? doc.set({'at': FieldValue.serverTimestamp()})
        : doc.delete();
  }

  Stream<bool> watchLiked({required String recipeId, required String uid}) =>
      _recipes
          .doc(recipeId)
          .collection('likes')
          .doc(uid)
          .snapshots()
          .map((d) => d.exists);

  /// Saves live under the user, not the recipe: "my saved recipes" is the
  /// query that actually gets run, and it should cost one read.
  Future<void> setSaved({
    required String recipeId,
    required String uid,
    required bool saved,
  }) {
    final doc = _firestore
        .collection('users')
        .doc(uid)
        .collection('saved')
        .doc(recipeId);
    return saved
        ? doc.set({'at': FieldValue.serverTimestamp()})
        : doc.delete();
  }

  Stream<List<String>> watchSavedIds(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('saved')
      .orderBy('at', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => d.id).toList());

  /// "I cooked this" — proof rather than intent, and weighted highest in
  /// ranking because of it.
  Future<void> markCooked({
    required String recipeId,
    required String uid,
    String? photoUrl,
    String? note,
  }) {
    return _recipes.doc(recipeId).collection('cooked').doc(uid).set({
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (note != null) 'note': note,
      'at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
