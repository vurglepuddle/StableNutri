// Pure helpers behind the Trends cards — kept Flutter-free so they can be
// unit-tested directly. The presentation layer decides what's "on track"
// (it needs theme colours) and hands the resulting date set in here.

/// Current and longest run of on-track days within [windowStart]..[today]
/// (both date-only, inclusive). A day not present in [onTrackDays] — whether
/// off-track or simply untracked — breaks the run. [current] counts the run
/// ending at [today]; if today isn't on track it's 0.
({int current, int longest}) streakStats(
  Set<DateTime> onTrackDays,
  DateTime windowStart,
  DateTime today,
) {
  final total = today.difference(windowStart).inDays;
  if (total < 0) return (current: 0, longest: 0);

  var longest = 0;
  var run = 0;
  for (var i = 0; i <= total; i++) {
    final day = DateTime(
      windowStart.year,
      windowStart.month,
      windowStart.day + i,
    );
    if (onTrackDays.contains(day)) {
      run++;
      if (run > longest) longest = run;
    } else {
      run = 0;
    }
  }

  var current = 0;
  for (var i = 0; i <= total; i++) {
    final day = DateTime(today.year, today.month, today.day - i);
    if (onTrackDays.contains(day)) {
      current++;
    } else {
      break;
    }
  }

  return (current: current, longest: longest);
}

/// Linear trend through weight [points] (sorted ascending by date), returned
/// as a neutral weekly rate of change. Stable presents the configured
/// corridor rather than predicting a date for reaching a single target.
double? weightTrendRate(List<({DateTime date, double kg})> points) {
  if (points.length < 2) return null;

  final first = points.first.date;
  final xs = [
    for (final p in points) p.date.difference(first).inDays.toDouble(),
  ];
  final ys = [for (final p in points) p.kg];
  final n = points.length;
  final meanX = xs.reduce((a, b) => a + b) / n;
  final meanY = ys.reduce((a, b) => a + b) / n;

  var numerator = 0.0;
  var denominator = 0.0;
  for (var i = 0; i < n; i++) {
    numerator += (xs[i] - meanX) * (ys[i] - meanY);
    denominator += (xs[i] - meanX) * (xs[i] - meanX);
  }
  final slopePerDay = denominator == 0 ? 0.0 : numerator / denominator;
  final ratePerWeek = slopePerDay * 7;

  return ratePerWeek;
}
