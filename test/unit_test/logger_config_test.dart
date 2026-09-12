import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/logger_config.dart';

void main() {
  test(
    'SDK credentials and search bodies are not printed; app errors remain useful',
    () {
      final originalPrint = debugPrint;
      final originalLevel = Logger.root.level;
      final printed = <String?>[];
      debugPrint = (String? message, {int? wrapWidth}) => printed.add(message);
      addTearDown(() {
        debugPrint = originalPrint;
        Logger.root.level = originalLevel;
      });

      // Reinitialization must not add a duplicate printer.
      LoggerConfig.intiLogger();
      LoggerConfig.intiLogger();
      Logger('supabase.auth').finest('Authorization: synthetic-secret');
      Logger('supabase.postgrest').fine('POST body: synthetic-food-search');
      Logger('supabase.realtime').warning('headers: synthetic-secret');
      Logger('supabase').severe('synthetic-secret');
      Logger('SpFoodDataSource').warning('Food backend search failed.');

      expect(printed, [
        'WARNING: SpFoodDataSource: Food backend search failed.',
      ]);
    },
  );
}
