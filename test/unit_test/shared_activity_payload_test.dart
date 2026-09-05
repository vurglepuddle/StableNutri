import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/physical_activity_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_activity_entity.dart';
import 'package:opennutritracker/features/home/domain/entity/shared_activity_payload.dart';

UserActivityEntity _testActivity({
  required String code,
  required double duration,
}) {
  return UserActivityEntity(
    'ua-$code',
    duration,
    duration * 5,
    DateTime(2026, 4, 27),
    PhysicalActivityEntity(
      code,
      'Activity $code',
      '',
      5.0,
      const <String>[],
      PhysicalActivityTypeEntity.conditioningExercise,
    ),
  );
}

void main() {
  group('SharedActivityPayload', () {
    test('round-trips items', () {
      final source = SharedActivityPayload.fromUserActivityList([
        _testActivity(code: '01010', duration: 30),
        _testActivity(code: '02020', duration: 45),
      ]);
      final encoded = source.toJsonString();
      final decoded = SharedActivityPayload.fromJsonString(encoded);

      expect(decoded.items, hasLength(2));
      expect(decoded.items.first.code, '01010');
      expect(decoded.items.first.duration, 30);
      expect(decoded.items.last.code, '02020');
      expect(decoded.items.last.duration, 45);
    });

    test('garbage input throws SharedActivityParseException', () {
      expect(
        () => SharedActivityPayload.fromJsonString('not-anything'),
        throwsA(isA<SharedActivityParseException>()),
      );
    });

    test(
      'oversized decompressed payload throws SharedActivityParseException',
      () {
        // 1 MiB of repeated bytes compresses to ~1 KiB but expands well
        // past the 64 KiB cap on decode. A malicious QR could in
        // principle ship something like this.
        final blob = List<int>.filled(1024 * 1024, 0x43);
        final compressed = gzip.encode(blob);
        final raw = base64Url.encode(compressed);
        expect(
          () => SharedActivityPayload.fromJsonString(raw),
          throwsA(
            isA<SharedActivityParseException>().having(
              (e) => e.message,
              'message',
              contains('too large'),
            ),
          ),
        );
      },
    );
  });
}
