import 'package:opennutritracker/core/domain/entity/water_intake_entity.dart';

/// What removing one cup of water does to a day's stored drinks.
///
/// [deleteIds] are dropped outright; when the tapped cup is smaller than the
/// oldest drink it reaches, that drink is rewritten with [reducedMl] at
/// [reducedAt] instead of disappearing.
class WaterTrim {
  const WaterTrim({
    required this.deleteIds,
    this.reducedAt,
    this.reducedMl = 0,
  });

  final List<String> deleteIds;
  final DateTime? reducedAt;
  final int reducedMl;

  bool get isEmpty => deleteIds.isEmpty && reducedAt == null;
}

/// Tapping a full cup removes exactly one cup of water, not "the last thing
/// you logged" — a 500 ml bottle logged through the dialog must not vanish
/// whole when the cups are 250 ml.
///
/// Drinks are consumed newest-first so the most recent mistake is the first
/// thing undone, and the last drink reached is reduced rather than deleted so
/// the day's total lands exactly one cup lower. Asking to remove more than the
/// day holds empties it rather than going negative.
abstract final class WaterTrimCalc {
  static WaterTrim trim(List<WaterIntakeEntity> entries, int amountMl) {
    if (amountMl <= 0 || entries.isEmpty) {
      return const WaterTrim(deleteIds: []);
    }
    final ordered = [...entries]
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final deleteIds = <String>[];
    DateTime? reducedAt;
    var reducedMl = 0;
    var remaining = amountMl;
    for (final entry in ordered.reversed) {
      if (remaining <= 0) break;
      // A non-positive or corrupt entry can't absorb any of the removal, but
      // leaving it behind would strand a row that never clears.
      if (entry.amountMl <= remaining) {
        remaining -= entry.amountMl;
        deleteIds.add(entry.id);
      } else {
        deleteIds.add(entry.id);
        reducedAt = entry.dateTime;
        reducedMl = entry.amountMl - remaining;
        remaining = 0;
      }
    }
    return WaterTrim(
      deleteIds: deleteIds,
      reducedAt: reducedAt,
      reducedMl: reducedMl,
    );
  }
}
