import 'package:brnj/core/iraqi_week.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IraqiWeek', () {
    test('a Saturday is the start of its own week', () {
      final saturday = DateTime(2026, 8, 15); // Saturday
      expect(saturday.weekday, DateTime.saturday);
      expect(IraqiWeek.containing(saturday).start, saturday);
    });

    test('every day maps back to the preceding Saturday', () {
      // 2026-08-15 is a Saturday; the week runs to Friday 2026-08-21.
      final expected = DateTime(2026, 8, 15);
      for (var offset = 0; offset < 7; offset++) {
        final date = expected.add(Duration(days: offset));
        expect(
          IraqiWeek.containing(date).start,
          expected,
          reason: 'failed for ${date.weekday}',
        );
      }
    });

    test('a Sunday belongs to the week that started the day before', () {
      // The classic bug: an ISO-week implementation would push Sunday back six
      // days into the previous week.
      final sunday = DateTime(2026, 8, 16);
      expect(sunday.weekday, DateTime.sunday);
      expect(IraqiWeek.containing(sunday).start, DateTime(2026, 8, 15));
    });

    test('the week ends on Friday', () {
      final week = IraqiWeek.containing(DateTime(2026, 8, 17));
      expect(week.end, DateTime(2026, 8, 21));
      expect(week.end.weekday, DateTime.friday);
      expect(isFamilyDay(week.end), isTrue);
    });

    test('days are seven, Saturday first', () {
      final days = IraqiWeek.containing(DateTime(2026, 8, 17)).days;
      expect(days.length, 7);
      expect(days.first.weekday, DateTime.saturday);
      expect(days.last.weekday, DateTime.friday);
      expect(iraqiWeekdayKeys.length, 7);
      expect(iraqiWeekdayKeys.first, 'weekdaySaturday');
    });

    test('indexOf places a date within the week', () {
      final week = IraqiWeek.containing(DateTime(2026, 8, 15));
      expect(week.indexOf(DateTime(2026, 8, 15)), 0);
      expect(week.indexOf(DateTime(2026, 8, 21)), 6);
      expect(week.indexOf(DateTime(2026, 8, 22)), isNull);
    });

    test('next and previous stay on Saturdays', () {
      final week = IraqiWeek.containing(DateTime(2026, 8, 17));
      expect(week.next.start, DateTime(2026, 8, 22));
      expect(week.previous.start, DateTime(2026, 8, 8));
      expect(week.next.start.weekday, DateTime.saturday);
    });

    test('crosses a month and a year boundary correctly', () {
      expect(IraqiWeek.containing(DateTime(2027, 1, 1)).start, DateTime(2026, 12, 26));
      expect(IraqiWeek.containing(DateTime(2026, 9, 1)).start, DateTime(2026, 8, 29));
    });

    test('id and planIdFor produce the stable document id', () {
      final week = IraqiWeek.containing(DateTime(2026, 8, 17));
      expect(week.id, '2026-08-15');
      expect(week.planIdFor('abc123'), 'abc123_2026-08-15');
      // Round-trips, which is what lets a deep link resolve a week.
      expect(IraqiWeek.fromId(week.id), week);
    });

    test('ignores the time of day', () {
      final morning = IraqiWeek.containing(DateTime(2026, 8, 17, 6, 30));
      final night = IraqiWeek.containing(DateTime(2026, 8, 17, 23, 59));
      expect(morning, night);
    });
  });
}
