import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/food_backend.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late GetIt services;

  setUp(() => services = GetIt.asNewInstance());
  tearDown(() => services.reset());

  test(
    'missing, example, and malformed configuration leave the backend absent',
    () {
      for (final (url, key) in [
        ('', ''),
        ('PROJECT_URL', 'ANON_KEY'),
        ('https://backend.invalid', 'ANON_KEY'),
        ('https://backend.invalid', '  '),
        ('https://PROJECT_URL', 'synthetic-key'),
        ('not a URL', 'synthetic-key'),
        ('file:///tmp/backend', 'synthetic-key'),
        ('https://', 'synthetic-key'),
      ]) {
        registerFoodBackend(services, url: url, anonKey: key);
        expect(services.isRegistered<SupabaseClient>(), isFalse);
      }
    },
  );

  test('configured backend is lazy and starts no auth refresh loop', () async {
    final previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    final records = <LogRecord>[];
    final subscription = Logger.root.onRecord.listen(records.add);
    addTearDown(() async {
      await subscription.cancel();
      Logger.root.level = previousLevel;
    });

    registerFoodBackend(
      services,
      url: ' http://localhost:54321/ ',
      anonKey: 'synthetic-key',
    );
    expect(services.isRegistered<SupabaseClient>(), isTrue);
    expect(records, isEmpty, reason: 'Registration must not construct the SDK');

    final client = services<SupabaseClient>();
    expect(client.auth.currentSession, isNull);
    expect(
      records
          .where((record) => record.loggerName == 'supabase.auth')
          .map((record) => record.message)
          .join('\n'),
      contains('autoRefreshToken: false'),
    );
    expect(
      records.any((record) => record.message.contains('Starting auto refresh')),
      isFalse,
    );
    expect(identical(services<SupabaseClient>(), client), isTrue);
  });
}
