import 'package:flutter/foundation.dart';

/// Which shape the Today calorie gauge takes: the linear range bar (the
/// default) or the original ring.
///
/// Purely presentational — both read the same numbers, and neither is the
/// "real" one. Mirrors [EnergyUnitProvider] / [ThemeModeProvider]: seeded from
/// the persisted config at app start and updated from Settings, so the
/// dashboard rebuilds without threading the flag through HomeBloc's state.
class CalorieGaugeProvider extends ChangeNotifier {
  bool usesRangeGauge;

  CalorieGaugeProvider({this.usesRangeGauge = true});

  void updateUsesRangeGauge(bool usesRangeGauge) {
    if (this.usesRangeGauge == usesRangeGauge) return;
    this.usesRangeGauge = usesRangeGauge;
    notifyListeners();
  }
}
