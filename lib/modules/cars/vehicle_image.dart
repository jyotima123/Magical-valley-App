import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache for vehicle photos.
///
/// A car's photos are immutable: the feed can change which URLs a listing
/// points at, but the bytes behind any one URL never change. So a photo is
/// downloaded exactly once and served from disk from then on — across scrolls,
/// across screens, and across app launches.
class VehicleImageCache {
  VehicleImageCache._();

  /// Names both the cache folder and its metadata database, so vehicle photos
  /// are evicted independently of every other cached image in the app.
  static const String cacheKey = 'vehicleImageCache';

  /// How long a downloaded photo is trusted without asking the server again.
  /// The bytes never change, so revalidating buys nothing and costs a round
  /// trip per photo on every cold start.
  static const Duration _validity = Duration(days: 365);

  /// Files are dropped only once untouched for [_stalePeriod], or when the
  /// store outgrows [_maxObjects]. A dealer's inventory runs to hundreds of
  /// photos, so the package defaults (30 days / 200 files) evict listings the
  /// user is still scrolling past.
  static const Duration _stalePeriod = Duration(days: 365);
  static const int _maxObjects = 1000;

  static final CacheManager instance = CacheManager(
    Config(
      cacheKey,
      stalePeriod: _stalePeriod,
      maxNrOfCacheObjects: _maxObjects,
      fileService: _ImmutableFileService(),
    ),
  );

  /// Pulls [urls] onto disk without building widgets, so photos below the fold
  /// are already local by the time they scroll into view. Already-cached URLs
  /// cost nothing; failures are ignored because the widget will retry when it
  /// actually renders.
  static void prefetch(Iterable<String> urls) {
    for (final url in urls) {
      if (url.isEmpty) continue;
      instance.getSingleFile(url).ignore();
    }
  }
}

/// Serves photos through [VehicleImageCache] and forces every response to stay
/// valid for a year, whatever `Cache-Control` the dealer's CDN happens to send.
class _ImmutableFileService extends HttpFileService {
  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    return _NeverStaleResponse(await super.get(url, headers: headers));
  }
}

class _NeverStaleResponse implements FileServiceResponse {
  _NeverStaleResponse(this._inner);

  final FileServiceResponse _inner;

  @override
  DateTime get validTill => DateTime.now().add(VehicleImageCache._validity);

  @override
  Stream<List<int>> get content => _inner.content;

  @override
  int? get contentLength => _inner.contentLength;

  @override
  int get statusCode => _inner.statusCode;

  @override
  String? get eTag => _inner.eTag;

  @override
  String get fileExtension => _inner.fileExtension;
}

/// A vehicle photo backed by [VehicleImageCache].
///
/// Drop-in replacement for `Image.network` on the cars screens. Note that
/// [decodeWidth] only downsizes the decoded bitmap in memory — the file on disk
/// stays the original, so the thumbnail in the list and the full-bleed photo on
/// the detail screen share a single download.
class VehicleImage extends StatelessWidget {
  const VehicleImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.decodeWidth,
    this.placeholder,
    this.errorWidget,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Target decode width in physical pixels. Set it for list thumbnails so a
  /// 4000px dealer photo is not decoded at full size into memory.
  final int? decodeWidth;

  final WidgetBuilder? placeholder;
  final WidgetBuilder? errorWidget;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: VehicleImageCache.instance,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: decodeWidth,
      placeholder: (context, _) =>
          placeholder?.call(context) ?? _defaultPlaceholder(),
      errorWidget: (context, _, __) =>
          errorWidget?.call(context) ??
          placeholder?.call(context) ??
          _defaultPlaceholder(),
      // A cached photo is already on disk, so fading it in just makes the list
      // look sluggish while scrolling.
      fadeInDuration: const Duration(milliseconds: 120),
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
    );
  }

  Widget _defaultPlaceholder() => Container(
        width: width,
        height: height,
        color: const Color(0xFFF0F0F0),
      );
}
