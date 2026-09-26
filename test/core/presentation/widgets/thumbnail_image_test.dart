import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/presentation/widgets/thumbnail_image.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

/// List thumbnails are decoded at their shown size, keeping the photo's
/// shape: decoding full-size photos cost frames while scrolling, and the
/// previous resize squashed non-square photos into squares.
void main() {
  late Directory root;
  const fallbackKey = Key('fallback');

  setUp(() async {
    root = await Directory.systemTemp.createTemp('stable_thumb_test_');
    PathProviderPlatform.instance = _FakePathProvider(root.path);
    UserImageStorage.resetDocumentsPathCache();
  });

  tearDown(() => root.delete(recursive: true));

  /// Writes a [width] x [height] PNG as a user meal photo.
  Future<String> photo(int width, int height) async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(
      ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFF2E74B5),
    );
    final image = await recorder.endRecording().toImage(width, height);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    const relative = 'meal_images/photo.webp';
    await Directory('${root.path}/meal_images').create();
    await File(
      '${root.path}/$relative',
    ).writeAsBytes(png!.buffer.asUint8List());
    return relative;
  }

  Future<void> pumpThumbnail(
    WidgetTester tester,
    String relative, {
    bool? showWhole,
  }) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(devicePixelRatio: 2),
        child: Center(
          child: ThumbnailImage(
            localPath: relative,
            size: 50,
            showWhole: showWhole,
            fallback: const SizedBox(key: fallbackKey),
          ),
        ),
      ),
    );
    // File reads and decoding happen outside the fake clock.
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.byType(RawImage).evaluate().isNotEmpty &&
          tester.widget<RawImage>(find.byType(RawImage)).image != null) {
        return;
      }
    }
  }

  testWidgets('a landscape photo keeps its shape at the shown size', (
    tester,
  ) async {
    final relative = await tester.runAsync(() => photo(400, 200));
    await pumpThumbnail(tester, relative!);

    final decoded = tester.widget<RawImage>(find.byType(RawImage)).image!;
    // 50 logical px at 2x: the shorter side is decoded at 100 px.
    expect(decoded.height, 100);
    expect(decoded.width, 200);
  });

  testWidgets('a small photo is not upscaled', (tester) async {
    final relative = await tester.runAsync(() => photo(60, 80));
    await pumpThumbnail(tester, relative!);

    final decoded = tester.widget<RawImage>(find.byType(RawImage)).image!;
    expect(decoded.width, 60);
    expect(decoded.height, 80);
  });

  testWidgets('a missing photo shows the fallback', (tester) async {
    await pumpThumbnail(tester, 'meal_images/missing.webp');

    expect(find.byKey(fallbackKey), findsOneWidget);
  });

  testWidgets('shown whole, the longer side is decoded at the shown size, '
      'on a white card', (tester) async {
    final relative = await tester.runAsync(() => photo(400, 200));
    await pumpThumbnail(tester, relative!, showWhole: true);

    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image!.width, 100);
    expect(raw.image!.height, 50);
    expect(raw.fit, BoxFit.contain);
    expect(
      find.byWidgetPredicate((w) => w is ColoredBox && w.color == Colors.white),
      findsOneWidget,
    );
  });

  testWidgets("the user's own photo fills the square by default", (
    tester,
  ) async {
    final relative = await tester.runAsync(() => photo(400, 200));
    await pumpThumbnail(tester, relative!);

    expect(tester.widget<RawImage>(find.byType(RawImage)).fit, BoxFit.cover);
  });
}
