/// Compact display only. Classification and persistence use precise values.
abstract final class DashboardEnergyFormat {
  static int rounded(double value) => (value / 10).round() * 10;

  static String text(double value) {
    if (value > 0 && value < 5) return '<10';
    return rounded(value).toString();
  }
}
