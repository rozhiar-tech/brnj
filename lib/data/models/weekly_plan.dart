import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/iraqi_week.dart';
import 'user_profile.dart';

enum PlanVisibility { public, followers, private }

enum MealType { lunch, dinner, breakfast, suhoor, iftar }

/// One dish on one day.
///
/// [recipeId] is optional on purpose. Most people won't have written the recipe
/// up, and forcing every entry to be a linked recipe would kill adoption — a
/// typed name like "تمن وقيمة" has to be a first-class entry.
class PlanEntry {
  const PlanEntry({
    required this.title,
    this.recipeId,
    this.mealType = MealType.lunch,
    this.photoUrl,
    this.note,
  });

  final String title;
  final String? recipeId;
  final MealType mealType;
  final String? photoUrl;
  final String? note;

  bool get isLinked => recipeId != null;

  factory PlanEntry.fromMap(Map<String, dynamic> map) => PlanEntry(
    title: map['title'] as String? ?? '',
    recipeId: map['recipeId'] as String?,
    mealType: MealType.values.firstWhere(
      (m) => m.name == map['mealType'],
      orElse: () => MealType.lunch,
    ),
    photoUrl: map['photoUrl'] as String?,
    note: map['note'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'title': title,
    if (recipeId != null) 'recipeId': recipeId,
    'mealType': mealType.name,
    if (photoUrl != null) 'photoUrl': photoUrl,
    if (note != null) 'note': note,
  };

  PlanEntry copyWith({String? title, String? recipeId, MealType? mealType}) =>
      PlanEntry(
        title: title ?? this.title,
        recipeId: recipeId ?? this.recipeId,
        mealType: mealType ?? this.mealType,
        photoUrl: photoUrl,
        note: note,
      );
}

class PlanDay {
  const PlanDay({required this.date, this.entries = const []});

  final DateTime date;
  final List<PlanEntry> entries;

  bool get isEmpty => entries.isEmpty;

  /// Friday is the family meal and gets visual weight in the layout.
  bool get isFamilyDay => date.weekday == DateTime.friday;

  factory PlanDay.fromMap(Map<String, dynamic> map) => PlanDay(
    date: (map['date'] as Timestamp).toDate(),
    entries: (map['entries'] as List? ?? const [])
        .map((e) => PlanEntry.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(growable: false),
  );

  Map<String, dynamic> toMap() => {
    'date': Timestamp.fromDate(date),
    'entries': entries.map((e) => e.toMap()).toList(),
  };

  PlanDay copyWith({List<PlanEntry>? entries}) =>
      PlanDay(date: date, entries: entries ?? this.entries);
}

class PlanStats {
  const PlanStats({
    this.views = 0,
    this.uniqueViewers = 0,
    this.copies = 0,
    this.saves = 0,
    this.comments = 0,
  });

  final int views;
  final int uniqueViewers;

  /// How many people ran "copy this week to mine". The metric that says whether
  /// the feature is working.
  final int copies;
  final int saves;
  final int comments;

  factory PlanStats.fromMap(Map<String, dynamic>? map) => PlanStats(
    views: (map?['views'] as num?)?.toInt() ?? 0,
    uniqueViewers: (map?['uniqueViewers'] as num?)?.toInt() ?? 0,
    copies: (map?['copies'] as num?)?.toInt() ?? 0,
    saves: (map?['saves'] as num?)?.toInt() ?? 0,
    comments: (map?['comments'] as num?)?.toInt() ?? 0,
  );
}

/// A user's week, stored as a single document.
///
/// The whole week lives in one document deliberately: a plan is always read as
/// a unit, so displaying one costs exactly one read and editing one costs one
/// write. The document id is `{uid}_{weekStart}`, which enforces
/// one-plan-per-user-per-week without a query or a transaction.
class WeeklyPlan {
  const WeeklyPlan({
    required this.id,
    required this.owner,
    required this.week,
    required this.days,
    this.title,
    this.note,
    this.tags = const [],
    this.region,
    this.visibility = PlanVisibility.private,
    this.stats = const PlanStats(),
    this.publishedAt,
    this.updatedAt,
  });

  final String id;
  final AuthorStub owner;
  final IraqiWeek week;

  /// Always length 7, index 0 = Saturday.
  final List<PlanDay> days;

  final String? title;
  final String? note;
  final List<String> tags;
  final String? region;

  /// New plans start [PlanVisibility.private]: people need to draft their week
  /// without an audience watching, and publish when they're ready.
  final PlanVisibility visibility;

  final PlanStats stats;
  final DateTime? publishedAt;
  final DateTime? updatedAt;

  bool get isPublished => publishedAt != null && visibility != PlanVisibility.private;

  bool get isEmpty => days.every((d) => d.isEmpty);

  int get dishCount => days.fold(0, (total, d) => total + d.entries.length);

  /// Recipe ids referenced anywhere in the week — the input to the shopping
  /// list, and the only thing that needs fetching beyond the plan document.
  List<String> get linkedRecipeIds => [
    for (final day in days)
      for (final entry in day.entries)
        if (entry.recipeId != null) entry.recipeId!,
  ];

  /// An empty week for [owner], ready to fill in.
  factory WeeklyPlan.empty({required AuthorStub owner, required IraqiWeek week}) =>
      WeeklyPlan(
        id: week.planIdFor(owner.uid),
        owner: owner,
        week: week,
        days: [for (final date in week.days) PlanDay(date: date)],
      );

  factory WeeklyPlan.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final week = IraqiWeek((data['weekStart'] as Timestamp).toDate());
    final rawDays = (data['days'] as List? ?? const [])
        .map((d) => PlanDay.fromMap(Map<String, dynamic>.from(d as Map)))
        .toList();

    // Tolerate a short or missing days array rather than throwing — a plan
    // written by an older client build must still render.
    final days = [
      for (var i = 0; i < 7; i++)
        i < rawDays.length ? rawDays[i] : PlanDay(date: week.days[i]),
    ];

    return WeeklyPlan(
      id: doc.id,
      owner: AuthorStub.fromMap(
        Map<String, dynamic>.from(data['owner'] as Map? ?? const {}),
      ),
      week: week,
      days: days,
      title: data['title'] as String?,
      note: data['note'] as String?,
      tags: (data['tags'] as List?)?.cast<String>() ?? const [],
      region: data['region'] as String?,
      visibility: PlanVisibility.values.firstWhere(
        (v) => v.name == data['visibility'],
        orElse: () => PlanVisibility.private,
      ),
      stats: PlanStats.fromMap(data['stats'] as Map<String, dynamic>?),
      publishedAt: (data['publishedAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// `stats` is absent: it is Function-owned. Writing it from here would be
  /// rejected by the security rules, which is the point.
  Map<String, dynamic> toMap({bool publishing = false}) => {
    'owner': owner.toMap(),
    'weekStart': Timestamp.fromDate(week.start),
    'weekEnd': Timestamp.fromDate(week.end),
    'days': days.map((d) => d.toMap()).toList(),
    if (title != null) 'title': title,
    if (note != null) 'note': note,
    'tags': tags,
    if (region != null) 'region': region,
    'visibility': visibility.name,
    'dishCount': dishCount,
    'updatedAt': FieldValue.serverTimestamp(),
    if (publishing) 'publishedAt': FieldValue.serverTimestamp(),
  };

  WeeklyPlan copyWith({
    List<PlanDay>? days,
    String? title,
    String? note,
    List<String>? tags,
    String? region,
    PlanVisibility? visibility,
  }) => WeeklyPlan(
    id: id,
    owner: owner,
    week: week,
    days: days ?? this.days,
    title: title ?? this.title,
    note: note ?? this.note,
    tags: tags ?? this.tags,
    region: region ?? this.region,
    visibility: visibility ?? this.visibility,
    stats: stats,
    publishedAt: publishedAt,
    updatedAt: updatedAt,
  );

  /// Replaces the entries on one day. [dayIndex] 0 = Saturday.
  WeeklyPlan withDayEntries(int dayIndex, List<PlanEntry> entries) {
    final updated = [...days];
    updated[dayIndex] = updated[dayIndex].copyWith(entries: entries);
    return copyWith(days: updated);
  }

  /// "Copy this week to mine" — clones every entry onto [target] for [newOwner],
  /// dropping the original's stats, visibility, and publish state. This is the
  /// action the whole browse-other-people's-weeks feature exists to produce.
  WeeklyPlan copyForUser({required AuthorStub newOwner, required IraqiWeek target}) {
    final targetDays = target.days;
    return WeeklyPlan(
      id: target.planIdFor(newOwner.uid),
      owner: newOwner,
      week: target,
      days: [
        for (var i = 0; i < 7; i++)
          PlanDay(date: targetDays[i], entries: days[i].entries),
      ],
      title: title,
      note: note,
      tags: tags,
      region: region,
    );
  }
}
