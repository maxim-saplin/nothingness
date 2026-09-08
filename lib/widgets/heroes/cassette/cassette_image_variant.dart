import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../theme/app_palette.dart';
import 'cassette_shared.dart';

enum CassetteLook { mono, copper, nightwave, poolside }

const _cassetteViewBox = Rect.fromLTWH(44, 119, 418, 257);
const _cassetteAspect = 418 / 257;
const _leftHub = Offset(167.1211, 237.9517);
const _rightHub = Offset(337.0508, 237.9517);
const _minPackRadius = 32.0;
const _maxPackRadius = 77.0;
const _titleFontScale = 0.92;
final _window = RRect.fromRectAndRadius(
  Rect.fromLTWH(109.9443, 202.3404, 283.625, 63.942),
  Radius.circular(6.173),
);
const _titleRegion = Rect.fromLTWH(112, 151, 279, 24);

String formatCassetteLabel({String? artist, String? title}) {
  final cleanArtist = artist?.trim() ?? '';
  final cleanTitle = title?.trim() ?? '';
  if (cleanArtist.isEmpty) {
    return cleanTitle.isEmpty ? 'NO TAPE LOADED' : cleanTitle;
  }
  if (cleanTitle.isEmpty) return cleanArtist;
  return '$cleanArtist - $cleanTitle';
}

class CassetteImageVariant extends StatelessWidget {
  const CassetteImageVariant(
    this.ctx, {
    required this.look,
    this.vertical = true,
    super.key,
  });

  final CassetteVariantContext ctx;
  final CassetteLook look;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(Theme.of(context).extension<AppPalette>()!);
    final progress = tapeProgress(ctx.positionMs, ctx.durationMs);

    final cassette = LayoutBuilder(
      builder: (context, box) {
        var width = box.maxWidth;
        if (width / _cassetteAspect > box.maxHeight) {
          width = box.maxHeight * _cassetteAspect;
        }
        final size = Size(width, width / _cassetteAspect);
        return Center(
          child: RepaintBoundary(
            child: ReelSpin(
              isPlaying: ctx.isPlaying,
              rpm: 7,
              builder: (context, angle) => SizedBox.fromSize(
                size: size,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _layer('cassette', palette, _CassettePart.composite),
                    CustomPaint(
                      painter: _TitleCoverPainter(color: palette.label),
                    ),
                    CustomPaint(
                      painter: _TapePainter(
                        palette: palette,
                        progress: progress,
                      ),
                    ),
                    _rotatingHub(
                      '05-hub-left',
                      palette,
                      _leftHub,
                      angle * (_maxPackRadius / _packRadius(1 - progress)),
                    ),
                    _rotatingHub(
                      '06-hub-right',
                      palette,
                      _rightHub,
                      angle * (_maxPackRadius / _packRadius(progress)),
                    ),
                    CustomPaint(
                      painter: _TitlePainter(
                        title: (ctx.title ?? '').trim(),
                        artist: (ctx.artist ?? '').trim(),
                        color: palette.ink,
                        textScale: ctx.config.textScale,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    return ColoredBox(
      color: palette.background,
      child: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 56, 14, 14),
                child: vertical
                    ? RotatedBox(quarterTurns: 3, child: cassette)
                    : cassette,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _layer(String name, _CassettePalette palette, _CassettePart part) =>
      SvgPicture.asset(
        name == 'cassette'
            ? 'assets/cassette/cassette.svg'
            : 'assets/cassette/layers/$name.svg',
        fit: BoxFit.fill,
        excludeFromSemantics: true,
        colorMapper: _CassetteColorMapper(palette, part),
      );

  Widget _rotatingHub(
    String name,
    _CassettePalette palette,
    Offset center,
    double angle,
  ) => Transform.rotate(
    angle: angle,
    alignment: _alignmentAt(center),
    child: _layer(name, palette, _CassettePart.hub),
  );

  Alignment _alignmentAt(Offset point) => Alignment(
    (point.dx - _cassetteViewBox.center.dx) / (_cassetteViewBox.width / 2),
    (point.dy - _cassetteViewBox.center.dy) / (_cassetteViewBox.height / 2),
  );

  _CassettePalette _palette(AppPalette p) {
    switch (look) {
      case CassetteLook.mono:
        final shell = Color.lerp(p.background, p.fgPrimary, 0.18)!;
        final label = Color.lerp(p.background, p.fgPrimary, 0.30)!;
        return _CassettePalette(
          background: p.background,
          shell: shell,
          label: label,
          window: Color.lerp(p.background, p.fgPrimary, 0.10)!,
          ink: _contrast(label),
          hub: shell,
          tape: Color.lerp(shell, p.fgPrimary, 0.52)!,
        );
      case CassetteLook.copper:
        return _CassettePalette(
          background: p.background,
          shell: const Color(0xff5b3426),
          label: const Color(0xfff0c98f),
          window: const Color(0xffc6d7d0),
          ink: const Color(0xff2a1b17),
          hub: const Color(0xffffe7bd),
          tape: const Color(0xffb96842),
        );
      case CassetteLook.nightwave:
        return _CassettePalette(
          background: p.background,
          shell: const Color(0xff1b3151),
          label: const Color(0xffdce8f0),
          window: const Color(0xff8fc8c9),
          ink: const Color(0xff101c32),
          hub: const Color(0xffffd16b),
          tape: const Color(0xffe56b5b),
        );
      case CassetteLook.poolside:
        return _CassettePalette(
          background: p.background,
          shell: const Color(0xff0d6267),
          label: const Color(0xffeef1d9),
          window: const Color(0xffb3d8c8),
          ink: const Color(0xff123a3d),
          hub: const Color(0xffffe8bd),
          tape: const Color(0xffe98f5d),
        );
    }
  }
}

enum _CassettePart { hub, composite }

class _CassettePalette {
  const _CassettePalette({
    required this.background,
    required this.shell,
    required this.label,
    required this.window,
    required this.ink,
    required this.hub,
    required this.tape,
  });

  final Color background;
  final Color shell;
  final Color label;
  final Color window;
  final Color ink;
  final Color hub;
  final Color tape;
}

class _CassetteColorMapper extends ColorMapper {
  const _CassetteColorMapper(this.palette, this.part);

  final _CassettePalette palette;
  final _CassettePart part;

  @override
  Color substitute(
    String? id,
    String elementName,
    String attributeName,
    Color color,
  ) {
    switch (color.toARGB32()) {
      case 0xfffbfbf8:
        return switch (part) {
          _CassettePart.hub => palette.hub,
          _ => palette.shell,
        };
      case 0xffe8d5b7:
        return palette.label;
      case 0xffdce5e1:
        return palette.window;
      case 0xff262523:
        return palette.ink;
      case 0xff393733:
        return palette.tape;
      default:
        return color;
    }
  }
}

class _TapePainter extends CustomPainter {
  const _TapePainter({required this.palette, required this.progress});

  final _CassettePalette palette;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / _cassetteViewBox.width;
    final scaleY = size.height / _cassetteViewBox.height;
    canvas
      ..save()
      ..translate(
        -_cassetteViewBox.left * scaleX,
        -_cassetteViewBox.top * scaleY,
      )
      ..scale(scaleX, scaleY)
      ..clipRRect(_window);

    _drawPack(canvas, _leftHub, 1 - progress);
    _drawPack(canvas, _rightHub, progress);
    canvas.restore();
  }

  void _drawPack(Canvas canvas, Offset center, double fill) {
    final radius = _packRadius(fill);
    canvas.drawCircle(center, radius, Paint()..color = palette.tape);
  }

  @override
  bool shouldRepaint(_TapePainter old) =>
      old.palette != palette || old.progress != progress;
}

double _packRadius(double fill) =>
    _minPackRadius + (_maxPackRadius - _minPackRadius) * fill.clamp(0.0, 1.0);

class _TitlePainter extends CustomPainter {
  const _TitlePainter({
    required this.title,
    required this.artist,
    required this.color,
    required this.textScale,
  });

  final String title;
  final String artist;
  final Color color;
  final double textScale;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / _cassetteViewBox.width;
    final scaleY = size.height / _cassetteViewBox.height;
    final text = formatCassetteLabel(artist: artist, title: title);
    final painter = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontFamily: 'Caveat',
          fontSize: _titleRegion.height * scaleY * _titleFontScale * textScale,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    )..layout(maxWidth: _titleRegion.width * scaleX);
    painter.paint(
      canvas,
      Offset(
        (_titleRegion.left - _cassetteViewBox.left) * scaleX,
        (_titleRegion.top - _cassetteViewBox.top) * scaleY,
      ),
    );
  }

  @override
  bool shouldRepaint(_TitlePainter old) =>
      old.title != title ||
      old.artist != artist ||
      old.color != color ||
      old.textScale != textScale;
}

class _TitleCoverPainter extends CustomPainter {
  const _TitleCoverPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scaleX = size.width / _cassetteViewBox.width;
    final scaleY = size.height / _cassetteViewBox.height;
    canvas.drawRect(
      Rect.fromLTWH(
        (_titleRegion.left - _cassetteViewBox.left) * scaleX,
        (_titleRegion.top - _cassetteViewBox.top) * scaleY,
        _titleRegion.width * scaleX,
        _titleRegion.height * scaleY,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_TitleCoverPainter old) => old.color != color;
}

Color _contrast(Color color) => color.computeLuminance() > 0.42
    ? const Color(0xff1b1b1b)
    : const Color(0xfff8f7f1);
