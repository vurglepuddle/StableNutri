import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class LoggerConfig {
  static StreamSubscription<LogRecord>? _subscription;

  static void intiLogger() {
    Logger.root.level = kDebugMode ? Level.ALL : Level.OFF;
    _subscription ??= Logger.root.onRecord.listen((record) {
      // SDK records can contain request headers, credentials, and bodies.
      // Our food data source reports failures without those payloads.
      if (!kDebugMode ||
          record.loggerName == 'supabase' ||
          record.loggerName.startsWith('supabase.')) {
        return;
      }
      debugPrint(
        '${record.level.name}: ${record.loggerName}: ${record.message}',
      );
    });
  }
}
