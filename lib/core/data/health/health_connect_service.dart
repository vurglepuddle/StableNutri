import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/domain/entity/daily_steps.dart';

class HealthConnectService {
  static const _channel = MethodChannel('stable/health_connect');
  static bool get supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<String> status() async => supportedPlatform
      ? await _channel.invokeMethod<String>('status') ?? 'unavailable'
      : 'unavailable';

  Future<bool> requestReadPermissions() async =>
      await _channel.invokeMethod<bool>('requestReadPermissions') ?? false;

  Future<bool> hasReadPermission() async =>
      await _channel.invokeMethod<bool>('hasReadPermission') ?? false;

  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  Future<List<DailySteps>> readRecentStepTotals({
    required int offsetMinutes,
    int days = 7,
  }) async {
    final records = await _channel.invokeListMethod<Object?>(
      'readRecentStepTotals',
      {'offsetMinutes': offsetMinutes, 'days': days},
    );
    return (records ?? [])
        .map(
          (record) =>
              DailySteps.fromJson((record as Map).cast<String, dynamic>()),
        )
        .toList();
  }
}
