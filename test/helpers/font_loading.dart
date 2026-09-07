import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the real Biryani faces into the test binding.
///
/// `flutter test` substitutes a placeholder font whose every glyph is a square
/// and whose line box is exactly the font size. That makes the whole class of
/// font-metric bugs invisible to the suite: Biryani's real line box is 1.78x
/// its size, and no existing widget test could have seen that, because none of
/// them render Biryani at all.
///
/// Call this from any test whose assertion depends on real text metrics.
/// Loading is per-test-file, deliberately: making it global would silently
/// change the measurements every other widget test is pinned against.
Future<void> loadBiryani() async {
  const faces = [
    'fonts/Biryani-Regular.ttf',
    'fonts/Biryani-SemiBold.ttf',
    'fonts/Biryani-Bold.ttf',
  ];
  final loader = FontLoader('Biryani');
  for (final path in faces) {
    loader.addFont(
      File(path).readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
    );
  }
  await loader.load();
}
