import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/iraqi_week.dart';
import '../models/social.dart';
import '../models/user_profile.dart';
import '../models/weekly_plan.dart';

/// Weekly plans.
///
/// A plan is one document per user per week, keyed `{uid}_{weekStart}`. That
/// id is doing real work: it makes one-plan-per-user-per-week true by
/// construction, so there's no query to check for an existing plan and no
/// transaction to race. It also means [watchMyWeek] is a document listener
/// rather than a query, which is both cheaper and instant.
class PlanRepository {
  PlanRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _plans =>
      _firestore.collection('plans');

  /// A person's own week. Emits an unsaved empty plan when none exists yet, so
  /// the editor always has something to render — the first write happens when
  /// they add a dish, not when they open the screen.
  Stream<WeeklyPlan> watchMyWeek({
    required AuthorStub owner,
    required IraqiWeek week,
  }) {
    return _plans.doc(week.planIdFor(owner.uid)).snapshots().map((doc) {
      if (!doc.exists) return WeeklyPlan.empty(owner: owner, week: week);
      return WeeklyPlan.fromDoc(doc);
    });
  }

  Future<WeeklyPlan?> getPlan(String planId) async {
    final doc = await _plans.doc(planId).get();
    return doc.exists ? WeeklyPlan.fromDoc(doc) : null;
  }

  Stream<WeeklyPlan?> watchPlan(String planId) => _plans
      .doc(planId)
      .snapshots()
      .map((doc) => doc.exists ? WeeklyPlan.fromDoc(doc) : null);

  /// Writes the week. `merge: true` so a plan created by an older client build
  /// doesn't lose fields this one doesn't know about.
  Future<void> save(WeeklyPlan plan) async {
    await _plans.doc(plan.id).set(plan.toMap(), SetOptions(merge: true));
  }

  /// Publishing is separate from saving because drafting is private by design.
  /// People need to lay out their week without an audience watching, then
  /// decide to show it.
  Future<void> publish(
    WeeklyPlan plan, {
    PlanVisibility visibility = PlanVisibility.public,
  }) async {
    final published = plan.copyWith(visibility: visibility);
    await _plans
        .doc(plan.id)
        .set(published.toMap(publishing: true), SetOptions(merge: true));
  }

  Future<void> unpublish(WeeklyPlan plan) async {
    await _plans.doc(plan.id).update({
      'visibility': PlanVisibility.private.name,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// "This week in Iraqi kitchens" — the browse rail.
  ///
  /// Ordered by copies rather than views: copying a week is the action that
  /// says it was actually useful, and unlike views it can't be inflated by
  /// scrolling past. Verified plans surface through [verifiedOnly] rather than
  /// a score multiplier, so the ordering stays legible.
  Query<Map<String, dynamic>> publicWeekQuery({
    required IraqiWeek week,
    String? tag,
    String? region,
    int limit = 20,
  }) {
    Query<Map<String, dynamic>> query = _plans
        .where('visibility', isEqualTo: PlanVisibility.public.name)
        .where('weekStart', isEqualTo: Timestamp.fromDate(week.start));

    if (tag != null) query = query.where('tags', arrayContains: tag);
    if (region != null) query = query.where('region', isEqualTo: region);

    return query.orderBy('stats.copies', descending: true).limit(limit);
  }

  Stream<List<WeeklyPlan>> watchPublicWeek({
    required IraqiWeek week,
    String? tag,
    String? region,
    int limit = 20,
  }) {
    return publicWeekQuery(week: week, tag: tag, region: region, limit: limit)
        .snapshots()
        .map((snap) => snap.docs.map(WeeklyPlan.fromDoc).toList());
  }

  /// Someone's plan archive, for their profile.
  Stream<List<WeeklyPlan>> watchUserPlans(String uid, {int limit = 12}) {
    return _plans
        .where('owner.uid', isEqualTo: uid)
        .orderBy('weekStart', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(WeeklyPlan.fromDoc).toList());
  }

  /// "Copy this week to mine" — the action the whole browse feature exists to
  /// produce, and the metric worth watching.
  ///
  /// Copies into [target] (defaults to the coming week, not the current one:
  /// copying someone's Monday when it's already Thursday helps nobody). The
  /// copy lands private so the person can edit before anyone sees it.
  ///
  /// The `stats.copies` increment is written here, but the security rules
  /// reject client writes to `stats` — so this is a request the aggregation
  /// Function honours, not a direct write. Until that Function exists the
  /// counter stays at zero rather than being wrong.
  Future<WeeklyPlan> copyWeek({
    required WeeklyPlan source,
    required AuthorStub newOwner,
    IraqiWeek? target,
  }) async {
    final destination = target ?? IraqiWeek.current().next;
    final copy = source.copyForUser(newOwner: newOwner, target: destination);

    await _plans.doc(copy.id).set(copy.toMap(), SetOptions(merge: true));

    await _firestore.collection('viewEvents').add({
      'uid': newOwner.uid,
      'targetType': 'plan',
      'targetId': source.id,
      'action': 'copy',
      'at': FieldValue.serverTimestamp(),
    });

    return copy;
  }

  // --- comments ------------------------------------------------------------

  /// A week gets a conversation too. Same shape as a recipe thread, oldest
  /// first, because "why rice twice?" and its answer only make sense in order.
  Stream<List<Comment>> watchComments(String planId, {int limit = 100}) => _plans
      .doc(planId)
      .collection('comments')
      .orderBy('createdAt')
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(Comment.fromDoc).toList());

  Future<void> addComment({
    required String planId,
    required AuthorStub author,
    required String text,
  }) => _plans
      .doc(planId)
      .collection('comments')
      .add(Comment(id: '', author: author, text: text).toMap());

  Future<void> deleteComment({
    required String planId,
    required String commentId,
  }) => _plans.doc(planId).collection('comments').doc(commentId).delete();

  Future<void> delete(String planId) => _plans.doc(planId).delete();
}
