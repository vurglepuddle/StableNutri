import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/share_qr_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus_platform_interface/method_channel/method_channel_share.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class _TemporaryPathProvider extends PathProviderPlatform {
  _TemporaryPathProvider(this.path);
  final String? path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: const Scaffold(
        body: ShareQrDialog(
          title: 'Share meal',
          code: 'sample-payload-code',
          fileBaseName: 'sample_qr',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // SharePlus captures this instance on first use; select the mobile channel
  // before the desktop test host can send sharing to its native implementation.
  final originalShare = SharePlatform.instance;
  setUpAll(() => SharePlatform.instance = MethodChannelShare());
  tearDownAll(() => SharePlatform.instance = originalShare);

  group('ShareQrDialog', () {
    for (final fallback in [false, true]) {
      testWidgets(
        fallback
            ? 'shares the code when temporary storage is unavailable'
            : 'shares a real PNG and code with the button anchor',
        (tester) async {
          final originalPaths = PathProviderPlatform.instance;
          final temporary = Directory.systemTemp.createTempSync(
            'stable-share-',
          );
          PathProviderPlatform.instance = _TemporaryPathProvider(
            fallback ? null : temporary.path,
          );
          const channel = MethodChannel('dev.fluttercommunity.plus/share');
          Map? shared;
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'share');
            shared = call.arguments as Map;
            return '';
          });
          addTearDown(() {
            messenger.setMockMethodCallHandler(channel, null);
            PathProviderPlatform.instance = originalPaths;
            temporary.deleteSync(recursive: true);
          });

          await _pumpDialog(tester);
          final button = find.ancestor(
            of: find.byIcon(Icons.share_rounded),
            matching: find.byType(OutlinedButton),
          );
          final rect = tester.getRect(button);
          await tester.runAsync(() async {
            // Run rasterization and filesystem I/O outside the fake test clock.
            final action =
                tester.widget<OutlinedButton>(button).onPressed!
                    as Future<void> Function();
            await action();
            final args = shared!;
            expect(args['text'], 'sample-payload-code');
            expect(args['originX'], rect.left);
            expect(args['originY'], rect.top);
            expect(args['originWidth'], rect.width);
            expect(args['originHeight'], rect.height);
            if (fallback) {
              expect(args.containsKey('paths'), isFalse);
            } else {
              expect(args['mimeTypes'], ['image/png']);
              final paths = args['paths'] as List;
              expect(paths, hasLength(1));
              final bytes = await File(paths.single as String).readAsBytes();
              expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
            }
          });
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('renders the title, QR image, and both action buttons', (
      tester,
    ) async {
      await _pumpDialog(tester);

      expect(find.text('Share meal'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      // Copy and Share buttons each render an OutlinedButton.icon —
      // there are exactly two of them in the dialog.
      expect(find.byType(OutlinedButton), findsNWidgets(2));
    });

    testWidgets('share button reports a bounded, on-screen render rect '
        '(guards iPad popover anchor + iPhone presentation fix)', (
      tester,
    ) async {
      await _pumpDialog(tester);

      // Locate the share button by its icon — the dialog has only one
      // Icons.share_rounded, on the share OutlinedButton.icon.
      final shareIcon = find.byIcon(Icons.share_rounded);
      expect(shareIcon, findsOneWidget);

      final shareButton = find.ancestor(
        of: shareIcon,
        matching: find.byType(OutlinedButton),
      );
      expect(shareButton, findsOneWidget);

      // If a future refactor wraps the share button in an Expanded or
      // similarly layout-greedy ancestor without a Semantics(container:
      // true) escape hatch, this rect would balloon to the screen size
      // — which is exactly the failure mode we don't want feeding into
      // share_plus' sharePositionOrigin. Lock the button to something
      // sensibly small.
      final rect = tester.getRect(shareButton);
      expect(rect.width, lessThan(400));
      expect(rect.height, lessThan(100));
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
    });
  });
}
