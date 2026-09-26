import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';

/// A square thumbnail from a user photo or a remote image, decoded at the
/// size it is shown.
///
/// Full-size decodes (user photos are up to 1024px) cost frames while a list
/// scrolls and push each other out of the image cache. Flutter's own resize
/// with both sides set stretches to them instead, squashing non-square food
/// photos, so the decode keeps the shape.
///
/// A user photo (food on a plate) fills the square, trimming the longer
/// side. A remote image is a product's pack shot, with its name and weight
/// printed to the edges, so it is shown whole on a white card instead;
/// cropping it to fill a rounded square cut off exactly those parts.
class ThumbnailImage extends StatelessWidget {
  const ThumbnailImage({
    super.key,
    this.localPath,
    this.url,
    required this.size,
    required this.fallback,
    this.borderRadius = BorderRadius.zero,
    this.showWhole,
  });

  /// A user photo's relative path in [UserImageStorage]; wins over [url].
  final String? localPath;
  final String? url;
  final double size;

  /// Shown while loading, when there is no image, and when it fails.
  final Widget fallback;
  final BorderRadius borderRadius;

  /// Show the whole image rather than filling the square. Null decides by
  /// source: remote images whole, the user's own photos filling.
  final bool? showWhole;

  @override
  Widget build(BuildContext context) {
    final side = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final local = localPath;
    final remote = url;
    final whole = showWhole ?? local == null;
    Widget child;
    if (local != null) {
      final path = UserImageStorage.absolutePathIfReady(local);
      child = path != null
          ? _image(FileImage(File(path)), side, whole)
          : FutureBuilder<String>(
              future: UserImageStorage.absolutePath(local),
              builder: (context, snapshot) => snapshot.hasData
                  ? _image(FileImage(File(snapshot.data!)), side, whole)
                  : fallback,
            );
    } else if (remote != null && remote.isNotEmpty) {
      child = _image(
        CachedNetworkImageProvider(
          remote,
          cacheManager: locator<CacheManager>(),
        ),
        side,
        whole,
      );
    } else {
      child = fallback;
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox.square(dimension: size, child: child),
    );
  }

  Widget _image(ImageProvider provider, int side, bool whole) => Image(
    image: _FitResizeImage(provider, side, whole: whole),
    width: size,
    height: size,
    fit: whole ? BoxFit.contain : BoxFit.cover,
    gaplessPlayback: true,
    frameBuilder: (context, image, frame, synchronous) {
      if (!synchronous && frame == null) return fallback;
      if (!whole) return image;
      // Inset far enough that a rounded corner never clips the picture.
      final inset = math.max(size * 0.06, borderRadius.topLeft.x * 0.3);
      return ColoredBox(
        color: Colors.white,
        child: Padding(padding: EdgeInsets.all(inset), child: image),
      );
    },
    errorBuilder: (context, error, stack) => fallback,
  );
}

/// Decodes [image] at [side] pixels, never upscaling: the shorter side when
/// the picture fills a square, the longer one when it is shown [whole].
class _FitResizeImage extends ImageProvider<_FitResizeKey> {
  const _FitResizeImage(this.image, this.side, {required this.whole});

  final ImageProvider image;
  final int side;
  final bool whole;

  @override
  Future<_FitResizeKey> obtainKey(ImageConfiguration configuration) async =>
      _FitResizeKey(await image.obtainKey(configuration), side, whole);

  @override
  ImageStreamCompleter loadImage(
    _FitResizeKey key,
    ImageDecoderCallback decode,
  ) {
    Future<ui.Codec> decodeFitted(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) => decode(
      buffer,
      getTargetSize: (width, height) {
        final measured = whole
            ? math.max(width, height)
            : math.min(width, height);
        if (measured <= side) {
          return ui.TargetImageSize(width: width, height: height);
        }
        final scale = side / measured;
        return ui.TargetImageSize(
          width: (width * scale).round(),
          height: (height * scale).round(),
        );
      },
    );
    return image.loadImage(key.inner, decodeFitted);
  }
}

@immutable
class _FitResizeKey {
  const _FitResizeKey(this.inner, this.side, this.whole);

  final Object inner;
  final int side;
  final bool whole;

  @override
  bool operator ==(Object other) =>
      other is _FitResizeKey &&
      other.inner == inner &&
      other.side == side &&
      other.whole == whole;

  @override
  int get hashCode => Object.hash(inner, side, whole);
}
