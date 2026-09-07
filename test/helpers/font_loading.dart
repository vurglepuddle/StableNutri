import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the real Commissioner faces into the test binding.
///
/// `flutter test` substitutes a placeholder font whose every glyph is a square
/// and whose line box is exactly the font size. That makes the whole class of
/// font-metric bugs invisible to the suite — the previous face, Biryani, had a
/// 1.78x line box that clipped screen titles on device, and no widget test
/// could have seen it, because none of them render the app font at all.
///
/// Call this from any test whose assertion depends on real text metrics.
/// Loading is per-test-file, deliberately: making it global would silently
/// change the measurements every other widget test is pinned against.
Future<void> loadAppFont() async {
  const faces = [
    'fonts/Commissioner-Regular.ttf',
    'fonts/Commissioner-Medium.ttf',
    'fonts/Commissioner-SemiBold.ttf',
    'fonts/Commissioner-Bold.ttf',
  ];
  final loader = FontLoader('Commissioner');
  for (final path in faces) {
    loader.addFont(
      File(path).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
    );
  }
  await loader.load();
}
