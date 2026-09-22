/// Adult BMI reference range, expressed as mass for a given height.
/// https://www.cdc.gov/bmi/adult-calculator/bmi-categories.html
class HealthyWeightRange {
  final double minKg;
  final double maxKg;

  const HealthyWeightRange({required this.minKg, required this.maxKg});

  factory HealthyWeightRange.forHeightCm(double heightCm) {
    if (!heightCm.isFinite || heightCm <= 0) {
      throw ArgumentError.value(heightCm, 'heightCm');
    }
    final squaredMetres = (heightCm / 100) * (heightCm / 100);
    return HealthyWeightRange(
      minKg: 18.5 * squaredMetres,
      maxKg: 25 * squaredMetres,
    );
  }

  bool contains(double kg) => kg >= minKg && kg < maxKg;
  double get midpointKg => (minKg + maxKg) / 2;
  double suggestionFor(double kg) => contains(kg) ? kg : midpointKg;
}
