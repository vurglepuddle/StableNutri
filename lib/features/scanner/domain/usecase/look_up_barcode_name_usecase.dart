import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/scanner/data/barcode_list_data_source.dart';

/// Names a barcode that no food source could resolve, so the not-found screen
/// can say what the product probably is and seed the new food with it.
///
/// Runs only after Open Food Facts has come back empty, and only while the
/// user leaves barcode-list.ru switched on in Settings → Food databases.
class LookUpBarcodeNameUseCase {
  final BarcodeListDataSource _barcodeListDataSource;
  final GetConfigUsecase _getConfigUsecase;

  LookUpBarcodeNameUseCase(this._barcodeListDataSource, this._getConfigUsecase);

  Future<BarcodeListResult?> lookUp(String barcode) async {
    final config = await _getConfigUsecase.getConfig();
    if (!config.isFoodSourceEnabled(BarcodeListDataSource.sourceCode)) {
      return null;
    }
    return _barcodeListDataSource.lookUp(barcode);
  }
}
