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
        // Handle error
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
        // Calculate the rendered rect of the image using BoxFit.contain
        final Size containerSize = constraints.biggest;
        final Size imageSize = Size(
          _image!.width.toDouble(),
          _image!.height.toDouble(),
        );

        final FittedSizes fittedSizes = applyBoxFit(
          BoxFit.contain,
          imageSize,
          containerSize,
        );
        final Size destinationSize = fittedSizes.destination;

        final double dx = (containerSize.width - destinationSize.width) / 2.0;
        final double dy = (containerSize.height - destinationSize.height) / 2.0;

        final Rect renderedImageRect = Rect.fromLTWH(
          dx,
          dy,
          destinationSize.width,
          destinationSize.height,
        );

        // Calculate absolute LCD rect relative to the RENDERED image rect
        final absoluteLcdRect = Rect.fromLTWH(
          renderedImageRect.left +
              (widget.lcdRect.left * renderedImageRect.width),
          renderedImageRect.top +
              (widget.lcdRect.top * renderedImageRect.height),
          widget.lcdRect.width * renderedImageRect.width,
          widget.lcdRect.height * renderedImageRect.height,
        );

        return Stack(
          children: [
            // Background Image (Centered)
            Center(
              child: Image.asset(
                widget.backgroundImagePath,
                fit: BoxFit.contain,
              ),
            ),

            // LCD Content Area
            Positioned.fromRect(
              rect: absoluteLcdRect,
              child: widget.lcdContent,
            ),

            // Interactive Control Areas
            if (widget.controlAreas != null)
              ...widget.controlAreas!.map((area) {
                final absoluteRect = Rect.fromLTWH(
                  renderedImageRect.left +
                      (area.rect.left * renderedImageRect.width),
                  renderedImageRect.top +
                      (area.rect.top * renderedImageRect.height),
                  area.rect.width * renderedImageRect.width,
                  area.rect.height * renderedImageRect.height,
                );

                return Positioned.fromRect(
                  rect: absoluteRect,
                  child: Stack(
                    children: [
                      // Touch Interaction & Ripple
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: area.onTap,
                          customBorder: area.shape == SkinControlShape.circle
                              ? const CircleBorder()
                              : RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                          splashColor: Colors.white.withValues(alpha: 0.3),
                          highlightColor: Colors.white.withValues(alpha: 0.1),
                          child: Container(),
                        ),
                      ),
                      // Debug Visualization
                      if (widget.debugLayout)
                        IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.3),
                              border: Border.all(color: Colors.blue, width: 2),
                              shape: area.shape == SkinControlShape.circle
                                  ? BoxShape.circle
                                  : BoxShape.rectangle,
                              borderRadius:
                                  area.shape == SkinControlShape.rectangle
                                  ? BorderRadius.circular(10)
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                area.debugLabel,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  backgroundColor: Colors.black54,
                                  fontSize: 8,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),

            // Debug Overlay
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
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        backgroundColor: Colors.black54,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

            // Media Controls (Optional Overlay - kept at screen bottom)
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
