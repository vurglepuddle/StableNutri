import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/notification_service.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezone = MethodChannel('flutter_timezone');
  final calls = <MethodCall>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    calls.clear();
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(
      timezone,
      (_) async => {
        'identifier': 'Africa/Nairobi',
        'localizedName': 'East Africa Time',
        'locale': 'en',
      },
    );
    messenger.setMockMethodCallHandler(notifications, (call) async {
      calls.add(call);
      return call.method == 'initialize' ? true : null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(timezone, null);
    messenger.setMockMethodCallHandler(notifications, null);
    debugDefaultTargetPlatformOverride = null;
    tz.setLocalLocation(tz.UTC);
  });

  test(
    'daily reminders use the IANA zone and replace the existing alarm',
    () async {
      final service = NotificationService();
      await service.scheduleDailyReminder(
        hour: 20,
        minute: 15,
        title: 'Meal reminder',
        body: 'Log your day',
        channelName: 'Meals',
        channelDescription: 'Daily meal reminders',
      );
      expect(calls.map((call) => call.method), [
        'initialize',
        'cancel',
        'zonedSchedule',
      ]);
      expect(calls[1].arguments['id'], 0);
      final args = calls.last.arguments as Map;
      expect(args['id'], 0);
      expect(args['timeZoneName'], 'Africa/Nairobi');
      expect(args['scheduledDateTime'], contains('T20:15:00'));
      expect(args['matchDateTimeComponents'], DateTimeComponents.time.index);
      expect(args['platformSpecifics']['channelId'], 'daily_reminder');
      expect(
        args['platformSpecifics']['scheduleMode'],
        'inexactAllowWhileIdle',
      );
    },
  );

  test(
    'fasting keeps its instant and cancellation ids remain distinct',
    () async {
      final service = NotificationService();
      final when = DateTime.now().toUtc().add(const Duration(days: 2));
      await service.scheduleFastingComplete(
        when: when,
        title: 'Fast complete',
        body: 'Target reached',
        channelName: 'Fasting',
        channelDescription: 'Fasting reminders',
      );
      final args = calls.last.arguments as Map;
      expect(args['id'], 1);
      expect(args['timeZoneName'], 'Africa/Nairobi');
      final local = DateTime.parse(args['scheduledDateTime'] as String);
      final expected = tz.TZDateTime.from(when, tz.local);
      expect(local.hour, expected.hour);
      expect(local.minute, expected.minute);
      expect(args['matchDateTimeComponents'], isNull);
      expect(args['platformSpecifics']['channelId'], 'fasting_complete');

      calls.clear();
      await service.cancelDailyReminder();
      await service.cancelFastingComplete();
      await service.cancelAllScheduled();
      expect(calls.map((call) => call.method), [
        'cancel',
        'cancel',
        'cancelAll',
      ]);
      expect(calls[0].arguments['id'], 0);
      expect(calls[1].arguments['id'], 1);
    },
  );
}
