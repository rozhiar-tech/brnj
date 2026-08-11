import 'package:brnj/core/iraqi_week.dart';
import 'package:brnj/data/models/user_profile.dart';
import 'package:brnj/data/models/weekly_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const owner = AuthorStub(uid: 'u1', name: 'أم علي', verified: true);
  const other = AuthorStub(uid: 'u2', name: 'ژیان');

  final week = IraqiWeek.containing(DateTime(2026, 8, 17)); // starts Sat 15th

  WeeklyPlan filledWeek() {
    var plan = WeeklyPlan.empty(owner: owner, week: week);
    plan = plan.withDayEntries(0, const [
      PlanEntry(title: 'دولمة', recipeId: 'r1'),
    ]);
    plan = plan.withDayEntries(6, const [
      PlanEntry(title: 'تمن وقيمة', recipeId: 'r2'),
      PlanEntry(title: 'شوربة', mealType: MealType.dinner),
    ]);
    return plan;
  }

  group('WeeklyPlan.empty', () {
    test('has seven days starting on the Saturday', () {
      final plan = WeeklyPlan.empty(owner: owner, week: week);
      expect(plan.days.length, 7);
      expect(plan.days.first.date, DateTime(2026, 8, 15));
      expect(plan.days.first.date.weekday, DateTime.saturday);
      expect(plan.days.last.isFamilyDay, isTrue); // Friday
      expect(plan.isEmpty, isTrue);
    });

    test('takes the deterministic {uid}_{weekStart} id', () {
      final plan = WeeklyPlan.empty(owner: owner, week: week);
      expect(plan.id, 'u1_2026-08-15');
    });

    test('starts private so drafting is unobserved', () {
      final plan = WeeklyPlan.empty(owner: owner, week: week);
      expect(plan.visibility, PlanVisibility.private);
      expect(plan.isPublished, isFalse);
    });
  });

  group('editing', () {
    test('withDayEntries replaces only that day', () {
      final plan = filledWeek();
      expect(plan.days[0].entries.single.title, 'دولمة');
      expect(plan.days[6].entries.length, 2);
      expect(plan.days[3].isEmpty, isTrue);
      expect(plan.dishCount, 3);
      expect(plan.isEmpty, isFalse);
    });

    test('linkedRecipeIds collects only the linked entries', () {
      // Free-text entries are first-class — most people will not have written
      // the recipe up — so they must not appear in the shopping-list input.
      expect(filledWeek().linkedRecipeIds, ['r1', 'r2']);
    });
  });

  group('copyForUser', () {
    test('re-dates every entry onto the target week', () {
      final target = week.next;
      final copy = filledWeek().copyForUser(newOwner: other, target: target);

      expect(copy.days.first.date, DateTime(2026, 8, 22));
      expect(copy.days.first.date.weekday, DateTime.saturday);
      expect(copy.days[0].entries.single.title, 'دولمة');
      expect(copy.days[6].entries.length, 2);
      expect(copy.dishCount, 3);
    });

    test('transfers ownership and the id', () {
      final copy = filledWeek().copyForUser(newOwner: other, target: week.next);
      expect(copy.owner.uid, 'u2');
      expect(copy.id, 'u2_2026-08-22');
    });

    test('drops the source stats and publish state', () {
      // A copied week is the copier's private draft, not a republication of
      // someone else's numbers.
      final source = WeeklyPlan(
        id: 'u1_2026-08-15',
        owner: owner,
        week: week,
        days: filledWeek().days,
        visibility: PlanVisibility.public,
        stats: const PlanStats(views: 900, copies: 42),
        publishedAt: DateTime(2026, 8, 14),
      );

      final copy = source.copyForUser(newOwner: other, target: week.next);
      expect(copy.stats.copies, 0);
      expect(copy.stats.views, 0);
      expect(copy.publishedAt, isNull);
      expect(copy.visibility, PlanVisibility.private);
      expect(copy.isPublished, isFalse);
    });

    test('carries the title and tags, which are what made it worth copying', () {
      final source = filledWeek().copyWith(
        title: 'أسبوع اقتصادي',
        tags: ['اقتصادي', 'رمضان'],
      );
      final copy = source.copyForUser(newOwner: other, target: week.next);
      expect(copy.title, 'أسبوع اقتصادي');
      expect(copy.tags, ['اقتصادي', 'رمضان']);
    });
  });
}
