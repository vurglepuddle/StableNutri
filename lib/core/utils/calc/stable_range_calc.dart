enum StableRangeStatus { below, within, above }

class StableRangeResult {
  final StableRangeStatus status;
  final double distanceToRange;

  const StableRangeResult({
    required this.status,
    required this.distanceToRange,
  });
}

/// Pure range semantics shared by intake and weight-corridor presentation.
/// Bounds are inclusive; equality is intentionally valid so upgraded profiles
/// can preserve their legacy point target until the user chooses a real range.
class StableRangeCalc {
  const StableRangeCalc._();

  static StableRangeResult classify({
    required double value,
    required double lower,
    required double upper,
  }) {
    assert(value.isFinite, 'value must be finite');
    assert(lower.isFinite, 'lower must be finite');
    assert(upper.isFinite, 'upper must be finite');
    assert(lower <= upper, 'lower must not exceed upper');

    if (value < lower) {
      return StableRangeResult(
        status: StableRangeStatus.below,
        distanceToRange: lower - value,
      );
    }
    if (value > upper) {
      return StableRangeResult(
        status: StableRangeStatus.above,
        distanceToRange: value - upper,
      );
    }
    return const StableRangeResult(
      status: StableRangeStatus.within,
      distanceToRange: 0,
    );
  }

  /// Progress toward the upper edge, used by the Today gauge. Values before
  /// zero and beyond the upper edge are clamped so the UI remains stable.
  static double progressTowardUpper({
    required double value,
    required double upper,
  }) {
    assert(value.isFinite, 'value must be finite');
    assert(upper.isFinite && upper > 0, 'upper must be finite and positive');
    return (value / upper).clamp(0.0, 1.0).toDouble();
  }
}
