import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import '../../core/constants/api_constants.dart';
import '../../core/theme/app_theme.dart';

/// Affiche intelligemment aussi bien une URL réseau (`/Uploads/...`, `https://...`)
/// qu'une image encodée en Base64 (`data:image/...;base64,...` ou base64 brut)
/// avec décodage mémoïsé pour un défilement fluide à 60 fps.
class XfySmartImage extends StatelessWidget {
  const XfySmartImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.cacheWidth = 220,
    this.cacheHeight = 220,
    this.placeholderIcon = Icons.image_outlined,
  });

  final String? source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final IconData placeholderIcon;

  static final Map<int, Uint8List> _base64Cache = <int, Uint8List>{};

  static bool isBase64Source(String raw) {
    final t = raw.trim();
    if (t.startsWith('data:image')) return true;
    // Raw JPEG (/9j/) or PNG (iVBOR) or WebP (UklGR)
    if (t.length > 100 &&
        !t.startsWith('http://') &&
        !t.startsWith('https://') &&
        !t.startsWith('/')) {
      return t.startsWith('/9j/') ||
          t.startsWith('iVBOR') ||
          t.startsWith('UklGR') ||
          t.startsWith('R0lGOD');
    }
    return false;
  }

  static Uint8List? decodeBase64Cached(String raw) {
    final key = raw.hashCode ^ raw.length;
    final cached = _base64Cache[key];
    if (cached != null) return cached;
    try {
      final commaIdx = raw.indexOf(',');
      final payload =
          (raw.startsWith('data:') && commaIdx >= 0) ? raw.substring(commaIdx + 1) : raw;
      final bytes = base64Decode(payload.replaceAll(RegExp(r'\s+'), ''));
      if (_base64Cache.length > 60) {
        _base64Cache.remove(_base64Cache.keys.first);
      }
      _base64Cache[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Widget _placeholder() => Center(
        child: Icon(placeholderIcon, color: XfyColors.inkMuted, size: 22),
      );

  @override
  Widget build(BuildContext context) {
    final raw = source?.trim();
    if (raw == null || raw.isEmpty || raw == 'null') {
      return SizedBox(width: width, height: height, child: _placeholder());
    }

    if (isBase64Source(raw)) {
      final bytes = decodeBase64Cached(raw);
      if (bytes == null || bytes.isEmpty) {
        return SizedBox(width: width, height: height, child: _placeholder());
      }
      return Image.memory(
        bytes,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }

    final url = ApiConstants.resolveImageUrl(raw);
    if (url == null) {
      return SizedBox(width: width, height: height, child: _placeholder());
    }

    return Image.network(
      url,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      filterQuality: FilterQuality.low,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }
}

/// Visionneuse plein écran avec zoom tactile (pinch-to-zoom) pour les captures
/// de commande et les photos de produits.
Future<void> showXfyImageLightbox(
  BuildContext context, {
  required String source,
  String? title,
  String? subtitle,
}) async {
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.90),
    builder: (ctx) {
      return Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5.0,
                  child: Center(
                    child: XfySmartImage(
                      source: source,
                      fit: BoxFit.contain,
                      cacheWidth: null,
                      cacheHeight: null,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    if (title != null && title.isNotEmpty)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              if (subtitle != null && subtitle.isNotEmpty)
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
