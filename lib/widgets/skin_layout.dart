import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

enum SkinControlShape { rectangle, circle }

class SkinControlArea {
  final Rect rect;
  final SkinControlShape shape;
  final VoidCallback onTap;
  final String debugLabel;

  const SkinControlArea({
    required this.rect,
    this.shape = SkinControlShape.rectangle,
    required this.onTap,
    this.debugLabel = '',
  });
}

TextStyle _debugLabelStyle(double fontSize) => TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.bold,
  backgroundColor: Colors.black54,
  fontSize: fontSize,
);

class SkinLayout extends HookWidget {
  final String backgroundImagePath;
  final Rect lcdRect;
  final Widget lcdContent;
  final bool debugLayout;
  final Widget? mediaControls;
  final List<SkinControlArea>? controlAreas;

  const SkinLayout({
    super.key,
    required this.backgroundImagePath,
    required this.lcdRect,
    required this.lcdContent,
    this.debugLayout = false,
    this.mediaControls,
    this.controlAreas,
  });

  @override
  Widget build(BuildContext context) {
    final image = useState<ui.Image?>(null);
    final isLoading = useState<bool>(true);

    // Reload the background whenever the asset path changes (matches the old
    // didUpdateWidget branch); the effect re-runs on path change and on first
    // build, mirroring initState + didUpdateWidget.
    useEffect(() {
      var disposed = false;
      isLoading.value = true;
      final ImageStream stream = AssetImage(
        backgroundImagePath,
      ).resolve(ImageConfiguration.empty);
      final Completer<ui.Image> completer = Completer();
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (!completer.isCompleted) {
            completer.complete(info.image);
          }
        },
        onError: (dynamic exception, StackTrace? stackTrace) {
          if (!disposed) isLoading.value = false;
        },
      );

      stream.addListener(listener);
      completer.future.then((loaded) {
        stream.removeListener(listener);
        if (disposed) return;
        image.value = loaded;
        isLoading.value = false;
      });

      return () {
        disposed = true;
        stream.removeListener(listener);
      };
    }, [backgroundImagePath]);

    if (isLoading.value || image.value == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final loadedImage = image.value!;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Rendered rect of the image under BoxFit.contain (centered).
        final Size containerSize = constraints.biggest;
        final Size imageSize = Size(
          loadedImage.width.toDouble(),
          loadedImage.height.toDouble(),
        );

        final Size destinationSize =
            applyBoxFit(BoxFit.contain, imageSize, containerSize).destination;

        final Rect renderedImageRect = Rect.fromLTWH(
          (containerSize.width - destinationSize.width) / 2.0,
          (containerSize.height - destinationSize.height) / 2.0,
          destinationSize.width,
          destinationSize.height,
        );

        // Map a relative (0..1) rect into the rendered image rect.
        Rect toAbsolute(Rect r) => Rect.fromLTWH(
          renderedImageRect.left + (r.left * renderedImageRect.width),
          renderedImageRect.top + (r.top * renderedImageRect.height),
          r.width * renderedImageRect.width,
          r.height * renderedImageRect.height,
        );

        final absoluteLcdRect = toAbsolute(lcdRect);

        return Stack(
          children: [
            Center(
              child: Image.asset(
                backgroundImagePath,
                fit: BoxFit.contain,
              ),
            ),

            // LCD content area.
            Positioned.fromRect(
              rect: absoluteLcdRect,
              child: lcdContent,
            ),

            // Interactive control areas.
            if (controlAreas != null)
              ...controlAreas!.map((area) {
                final isCircle = area.shape == SkinControlShape.circle;
                return Positioned.fromRect(
                  rect: toAbsolute(area.rect),
                  child: Stack(
                    children: [
                      // Touch interaction & ripple.
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: area.onTap,
                          customBorder: isCircle
                              ? const CircleBorder()
                              : RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                          splashColor: Colors.white.withValues(alpha: 0.3),
                          highlightColor: Colors.white.withValues(alpha: 0.1),
                          child: Container(),
                        ),
                      ),
                      if (debugLayout)
                        IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.3),
                              border: Border.all(color: Colors.blue, width: 2),
                              shape: isCircle
                                  ? BoxShape.circle
                                  : BoxShape.rectangle,
                              borderRadius: isCircle
                                  ? null
                                  : BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                area.debugLabel,
                                style: _debugLabelStyle(8),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),

            if (debugLayout)
              Positioned.fromRect(
                rect: absoluteLcdRect,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.3),
                    border: Border.all(color: Colors.red, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      'LCD Area\n${(lcdRect.left * 100).toStringAsFixed(1)}%, ${(lcdRect.top * 100).toStringAsFixed(1)}%\n${(lcdRect.width * 100).toStringAsFixed(1)}% x ${(lcdRect.height * 100).toStringAsFixed(1)}%',
                      style: _debugLabelStyle(10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

            // Media controls (optional overlay pinned near screen bottom).
            if (mediaControls != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 40,
                child: mediaControls!,
              ),
          ],
        );
      },
    );
  }
}
