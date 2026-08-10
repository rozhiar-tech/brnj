/// Week arithmetic for weekly plans.
///
/// Iraq's week runs Saturday → Friday, with Friday as the big family meal.
/// Dart's [DateTime.weekday] is ISO (Monday = 1 … Sunday = 7), so every
/// calculation here converts. Getting this wrong makes the whole plan feature
/// feel foreign, which is why it lives in one place instead of being inlined.
library;

/// Saturday, in [DateTime.weekday] terms.
const int _saturday = DateTime.saturday; // 6

class IraqiWeek {
  /// [start] is always a Saturday at local midnight.
  IraqiWeek(DateTime start) : start = _dateOnly(start) {
    assert(this.start.weekday == _saturday, 'Week must start on a Saturday');
  }

  /// The week containing [date].
  factory IraqiWeek.containing(DateTime date) {
    final d = _dateOnly(date);
    // Days since the most recent Saturday: Sat→0, Sun→1, … Fri→6.
    final offset = (d.weekday - _saturday + 7) % 7;
    return IraqiWeek(d.subtract(Duration(days: offset)));
  }

  factory IraqiWeek.current() => IraqiWeek.containing(DateTime.now());

  /// Parses the `yyyy-MM-dd` form used in plan document ids.
  factory IraqiWeek.fromId(String weekStartIso) =>
      IraqiWeek(DateTime.parse(weekStartIso));

  final DateTime start;

  DateTime get end => start.add(const Duration(days: 6));

  /// The seven days, index 0 = Saturday.
  List<DateTime> get days =>
      List.generate(7, (i) => start.add(Duration(days: i)), growable: false);

  IraqiWeek get next => IraqiWeek(start.add(const Duration(days: 7)));
  IraqiWeek get previous => IraqiWeek(start.subtract(const Duration(days: 7)));

  bool get isCurrent => this == IraqiWeek.current();

  bool contains(DateTime date) {
    final d = _dateOnly(date);
    return !d.isBefore(start) && !d.isAfter(end);
  }

  /// Index of [date] within the week, or null if it falls outside.
  int? indexOf(DateTime date) {
    if (!contains(date)) return null;
    return _dateOnly(date).difference(start).inDays;
  }

  /// `2026-08-15` — stable, sortable, and the second half of a plan's
  /// document id (`{uid}_{weekStart}`), which is what makes one-plan-per-user-
  /// per-week enforceable without a query.
  String get id => _iso(start);

  /// The plan document id for a given user's week.
  String planIdFor(String uid) => '${uid}_$id';

  @override
  bool operator ==(Object other) => other is IraqiWeek && other.start == start;

  @override
  int get hashCode => start.hashCode;

  @override
  String toString() => 'IraqiWeek(${_iso(start)} → ${_iso(end)})';
}

/// Index 0 = Saturday, matching [IraqiWeek.days], mapped to the l10n keys.
const iraqiWeekdayKeys = <String>[
  'weekdaySaturday',
  'weekdaySunday',
  'weekdayMonday',
  'weekdayTuesday',
  'weekdayWednesday',
  'weekdayThursday',
  'weekdayFriday',
];

/// Friday gets visual weight in the plan layout — it's the family meal.
bool isFamilyDay(DateTime date) => date.weekday == DateTime.friday;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
