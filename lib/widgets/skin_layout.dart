import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

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

class SkinLayout extends StatefulWidget {
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
  State<SkinLayout> createState() => _SkinLayoutState();
}

TextStyle _debugLabelStyle(double fontSize) => TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.bold,
  backgroundColor: Colors.black54,
  fontSize: fontSize,
);

class _SkinLayoutState extends State<SkinLayout> {
  ui.Image? _image;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(SkinLayout oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundImagePath != widget.backgroundImagePath) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    setState(() => _isLoading = true);
    final ImageStream stream = AssetImage(
      widget.backgroundImagePath,
    ).resolve(ImageConfiguration.empty);
    final Completer<ui.Image> completer = Completer();
    final ImageStreamListener listener = ImageStreamListener(
      (ImageInfo info, bool synchronousCall) {
        if (!completer.isCompleted) {
          completer.complete(info.image);
        }
      },
      onError: (dynamic exception, StackTrace? stackTrace) {
        setState(() => _isLoading = false);
      },
    );

    stream.addListener(listener);
    final image = await completer.future;
    stream.removeListener(listener);

    if (mounted) {
      setState(() {
        _image = image;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _image == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Rendered rect of the image under BoxFit.contain (centered).
        final Size containerSize = constraints.biggest;
        final Size imageSize = Size(
          _image!.width.toDouble(),
          _image!.height.toDouble(),
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

        final absoluteLcdRect = toAbsolute(widget.lcdRect);

        return Stack(
          children: [
            Center(
              child: Image.asset(
                widget.backgroundImagePath,
                fit: BoxFit.contain,
              ),
            ),

            // LCD content area.
            Positioned.fromRect(
              rect: absoluteLcdRect,
              child: widget.lcdContent,
            ),

            // Interactive control areas.
            if (widget.controlAreas != null)
              ...widget.controlAreas!.map((area) {
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
                      if (widget.debugLayout)
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

            if (widget.debugLayout)
              Positioned.fromRect(
                rect: absoluteLcdRect,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.3),
                    border: Border.all(color: Colors.red, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      'LCD Area\n${(widget.lcdRect.left * 100).toStringAsFixed(1)}%, ${(widget.lcdRect.top * 100).toStringAsFixed(1)}%\n${(widget.lcdRect.width * 100).toStringAsFixed(1)}% x ${(widget.lcdRect.height * 100).toStringAsFixed(1)}%',
                      style: _debugLabelStyle(10),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

            // Media controls (optional overlay pinned near screen bottom).
            if (widget.mediaControls != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 40,
                child: widget.mediaControls!,
              ),
          ],
        );
      },
    );
  }
}
