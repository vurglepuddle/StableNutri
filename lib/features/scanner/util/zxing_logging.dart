import 'package:flutter/foundation.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

bool _applied = false;

/// Matches flutter_zxing's native logging to the build mode: on in debug,
/// off in release.
///
/// zxing-cpp's `isLogEnabled` is a zero-initialised global, so `false` is
/// already its default. We set it explicitly so the guarantee lives in our
/// code and survives an upstream change to that default.
///
/// Two things ride on this flag:
///   * `platform_log` writes decode timings and exception text straight to
///     logcat / the iOS system log.
///   * with it on, every [Code] carries a full copy of the cropped luminance
///     frame in `imageBytes`; with it off that field stays null and no frame
///     is copied per scan.
///
/// Both are useful while working on the scanner and neither should ship, which
/// is exactly what [kDebugMode] expresses — and unlike commenting the call out,
/// it can't be forgotten in the wrong state.
///
/// Called from the scanner screens rather than `main()` so opening the app
/// doesn't load the native library for users who never scan anything.
/// Best-effort: reaching the flag means loading `flutter_zxing`'s native
/// library, which is not present on every host this code runs on — a widget
/// test drives these screens on the desktop VM, where the `.dll` / `.so` was
/// never built and `DynamicLibrary.open` throws an [ArgumentError]. Configuring
/// a log flag must not be the thing that takes a screen down, and a genuine
/// inability to load the library surfaces where it matters anyway, through
/// `ReaderWidget.onControllerCreated`.
///
/// Latched either way: if the library cannot be loaded once it will not load on
/// the next scan either, and retrying would just re-throw on every open.
void configureZxingLogging() {
  if (_applied) return;
  _applied = true;
  try {
    zx.setLogEnabled(kDebugMode);
  } on Object {
    return;
  }
}
