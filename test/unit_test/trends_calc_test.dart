import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/features/trends/presentation/trends_calc.dart';

DateTime _d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  group('streakStats', () {
    final start = _d(2026, 5, 1);
    final today = _d(2026, 5, 10);

    test('all days on track gives the full window', () {
      final onTrack = {for (var i = 0; i <= 9; i++) _d(2026, 5, 1 + i)};
      final s = streakStats(onTrack, start, today);
      expect(s.current, 10);
      expect(s.longest, 10);
    });

    test('a gap breaks the run', () {
      final onTrack = {
        _d(2026, 5, 1),
        _d(2026, 5, 2),
        _d(2026, 5, 3),
        _d(2026, 5, 5),
        _d(2026, 5, 6),
        _d(2026, 5, 7),
        _d(2026, 5, 8),
        _d(2026, 5, 9),
      };
      final s = streakStats(onTrack, start, today);
      expect(s.longest, 5);
      expect(s.current, 0);
    });

    test('current counts the run ending today', () {
      final onTrack = {_d(2026, 5, 8), _d(2026, 5, 9), _d(2026, 5, 10)};
      final s = streakStats(onTrack, start, today);
      expect(s.current, 3);
      expect(s.longest, 3);
    });

    test('empty set gives zeros', () {
      final s = streakStats(<DateTime>{}, start, today);
      expect(s.current, 0);
      expect(s.longest, 0);
    });
  });

  group('weightTrendRate', () {
    test('fewer than two points gives null', () {
      expect(weightTrendRate([(date: _d(2026, 5, 1), kg: 80)]), isNull);
      expect(weightTrendRate(const []), isNull);
    });

    test('steady loss gives a negative weekly rate', () {
      final points = [
        (date: _d(2026, 5, 1), kg: 80.0),
        (date: _d(2026, 5, 8), kg: 79.0),
      ];
      expect(weightTrendRate(points), closeTo(-1.0, 1e-6));
    });

    test('flat trend gives zero', () {
      final points = [
        (date: _d(2026, 5, 1), kg: 80.0),
        (date: _d(2026, 5, 8), kg: 80.0),
      ];
      expect(weightTrendRate(points), closeTo(0, 1e-6));
    });

    test('steady gain gives a positive weekly rate', () {
      final points = [
        (date: _d(2026, 5, 1), kg: 80.0),
        (date: _d(2026, 5, 8), kg: 81.0),
      ];
      expect(weightTrendRate(points), closeTo(1.0, 1e-6));
    });
  });
}
