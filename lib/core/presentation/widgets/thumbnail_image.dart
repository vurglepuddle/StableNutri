import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/user_image_storage.dart';

/// A square, cover-cropped list thumbnail from a user photo or a remote
/// image, decoded at the size it is shown.
///
/// Full-size decodes (user photos are up to 1024px) cost frames while a list
/// scrolls and push each other out of the image cache. Flutter's own resize
/// with both sides set stretches to them instead, squashing non-square food
/// photos, so the decode keeps the shape and trims only the shorter side.
class ThumbnailImage extends StatelessWidget {
  const ThumbnailImage({
    super.key,
    this.localPath,
    this.url,
    required this.size,
    required this.fallback,
    this.borderRadius = BorderRadius.zero,
  });

  /// A user photo's relative path in [UserImageStorage]; wins over [url].
  final String? localPath;
  final String? url;
  final double size;

  /// Shown while loading, when there is no image, and when it fails.
  final Widget fallback;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final side = (size * MediaQuery.devicePixelRatioOf(context)).round();
    final local = localPath;
    final remote = url;
    Widget child;
    if (local != null) {
      final path = UserImageStorage.absolutePathIfReady(local);
      child = path != null
          ? _image(FileImage(File(path)), side)
          : FutureBuilder<String>(
              future: UserImageStorage.absolutePath(local),
              builder: (context, snapshot) => snapshot.hasData
                  ? _image(FileImage(File(snapshot.data!)), side)
                  : fallback,
            );
    } else if (remote != null && remote.isNotEmpty) {
      child = _image(
        CachedNetworkImageProvider(
          remote,
          cacheManager: locator<CacheManager>(),
        ),
        side,
      );
    } else {
      child = fallback;
    }
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox.square(dimension: size, child: child),
    );
  }

  Widget _image(ImageProvider provider, int side) => Image(
    image: _CoverResizeImage(provider, side),
    width: size,
    height: size,
    fit: BoxFit.cover,
    gaplessPlayback: true,
    frameBuilder: (context, image, frame, synchronous) =>
        synchronous || frame != null ? image : fallback,
    errorBuilder: (context, error, stack) => fallback,
  );
}

/// Decodes [image] so its shorter side is [side] pixels, never upscaling.
class _CoverResizeImage extends ImageProvider<_CoverResizeKey> {
  const _CoverResizeImage(this.image, this.side);

  final ImageProvider image;
  final int side;

  @override
  Future<_CoverResizeKey> obtainKey(ImageConfiguration configuration) async =>
      _CoverResizeKey(await image.obtainKey(configuration), side);

  @override
  ImageStreamCompleter loadImage(
    _CoverResizeKey key,
    ImageDecoderCallback decode,
  ) {
    Future<ui.Codec> decodeCover(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) => decode(
      buffer,
      getTargetSize: (width, height) {
        final shorter = math.min(width, height);
        if (shorter <= side) {
          return ui.TargetImageSize(width: width, height: height);
        }
        final scale = side / shorter;
        return ui.TargetImageSize(
          width: (width * scale).round(),
          height: (height * scale).round(),
        );
      },
    );
    return image.loadImage(key.inner, decodeCover);
  }
}

@immutable
class _CoverResizeKey {
  const _CoverResizeKey(this.inner, this.side);

  final Object inner;
  final int side;

  @override
  bool operator ==(Object other) =>
      other is _CoverResizeKey && other.inner == inner && other.side == side;

  @override
  int get hashCode => Object.hash(inner, side);
}
