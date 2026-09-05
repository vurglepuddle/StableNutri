import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/retry_util.dart';

class _BoomError implements Exception {
  final String message;
  _BoomError(this.message);
  @override
  String toString() => 'BoomError($message)';
}

void main() {
  group('withRetry', () {
    test('returns the result on first success without retrying', () async {
      var calls = 0;
      final result = await withRetry(() async {
        calls++;
        return 42;
      });

      expect(result, equals(42));
      expect(calls, equals(1));
    });

    test('rethrows immediately when shouldRetry returns false', () async {
      var calls = 0;
      Object? caught;

      try {
        await withRetry<int>(
          () async {
            calls++;
            throw _BoomError('non-retriable');
          },
          attempts: 5,
          shouldRetry: (_) => false,
        );
      } catch (e) {
        caught = e;
      }

      expect(
        calls,
        equals(1),
        reason: 'must not retry when shouldRetry returns false',
      );
      expect(caught, isA<_BoomError>());
    });

    test('rethrows immediately on attempts=1', () async {
      var calls = 0;
      Object? caught;
      try {
        await withRetry<int>(() async {
          calls++;
          throw _BoomError('first try');
        }, attempts: 1);
      } catch (e) {
        caught = e;
      }

      expect(calls, equals(1));
      expect(caught, isA<_BoomError>());
    });

    test('shouldRetry can inspect error type to decide', () async {
      var calls = 0;
      Object? caught;

      try {
        await withRetry<int>(
          () async {
            calls++;
            throw StateError('always non-retriable');
          },
          attempts: 5,
          shouldRetry: (e) => e is _BoomError,
        );
      } catch (e) {
        caught = e;
      }

      expect(calls, equals(1));
      expect(caught, isA<StateError>());
    });

    test(
      'retries on exception and succeeds when attempts allow',
      () async {
        var calls = 0;
        final stopwatch = Stopwatch()..start();
        final result = await withRetry<int>(() async {
          calls++;
          if (calls < 2) throw _BoomError('once');
          return 7;
        }, attempts: 3);
        stopwatch.stop();

        expect(result, equals(7));
        expect(calls, equals(2));
        // Backoff after the first failed attempt is 1<<0 = 1 second.
        expect(
          stopwatch.elapsed,
          greaterThan(const Duration(milliseconds: 800)),
        );
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );

    test(
      'rethrows the original error after all attempts exhausted',
      () async {
        var calls = 0;
        Object? caught;

        try {
          await withRetry<int>(
            () async {
              calls++;
              throw _BoomError('try $calls');
            },
            attempts: 2, // 1 failure + 1s wait + 1 retry = ~1s
          );
        } catch (e) {
          caught = e;
        }

        expect(calls, equals(2));
        expect(caught, isA<_BoomError>());
        expect((caught as _BoomError).message, equals('try 2'));
      },
      timeout: const Timeout(Duration(seconds: 5)),
    );
  });
}
