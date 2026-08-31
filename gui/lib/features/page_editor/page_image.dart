import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/models.dart';

/// キャプチャ画像に吹き出し位置のマーカーを重ねて表示する。
/// マーカーのクリックで行を選択し、空白のクリックで新規行の座標を通知する。
class PageImage extends StatefulWidget {
  const PageImage({super.key, required this.path, required this.lines, required this.selected, required this.onSelect, required this.onTapEmpty});
  final String path;
  final List<Line> lines;
  final int? selected;
  final void Function(int index) onSelect;
  final void Function(double x, double y) onTapEmpty;

  @override
  State<PageImage> createState() => _PageImageState();
}

class _PageImageState extends State<PageImage> {
  final _controller = TransformationController();

  @override
  Widget build(BuildContext context) {
    final file = File(widget.path);
    if (!file.existsSync()) {
      return const Center(child: Text('画像がありません'));
    }
    return ClipRect(
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 0.5,
        maxScale: 6,
        child: Center(
          child: AspectRatio(
            aspectRatio: _aspect(file),
            child: LayoutBuilder(
              builder: (context, c) => GestureDetector(
                onTapUp: (d) {
                  final x = d.localPosition.dx / c.maxWidth;
                  final y = d.localPosition.dy / c.maxHeight;
                  final hit = _hit(x, y, c);
                  if (hit != null) {
                    widget.onSelect(hit);
                  } else {
                    widget.onTapEmpty(x.clamp(0, 1), y.clamp(0, 1));
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(file, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                    CustomPaint(painter: _MarkerPainter(widget.lines, widget.selected, Theme.of(context).colorScheme)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int? _hit(double x, double y, BoxConstraints c) {
    int? best;
    double bestD = double.infinity;
    for (var i = 0; i < widget.lines.length; i++) {
      final l = widget.lines[i];
      if (l.x == null || l.y == null) continue;
      final dx = (l.x! - x) * c.maxWidth;
      final dy = (l.y! - y) * c.maxHeight;
      final d = dx * dx + dy * dy;
      if (d < 18 * 18 && d < bestD) { best = i; bestD = d; }
    }
    return best;
  }

  static final _aspectCache = <String, double>{};
  double _aspect(File f) {
    return _aspectCache.putIfAbsent(f.path, () {
      // PNG ヘッダから幅と高さを読む（16〜24 バイト目）
      final bytes = f.openSync().readSync(24);
      if (bytes.length < 24) return 0.85;
      final w = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19];
      final h = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23];
      return h == 0 ? 0.85 : w / h;
    });
  }
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter(this.lines, this.selected, this.scheme);
  final List<Line> lines;
  final int? selected;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (l.x == null || l.y == null) continue;
      final c = Offset(l.x! * size.width, l.y! * size.height);
      final isSel = i == selected;
      final fill = Paint()..color = isSel ? scheme.primary : (l.speaker == '不明' ? scheme.error : scheme.secondary).withValues(alpha: 0.85);
      canvas.drawCircle(c, isSel ? 13 : 10, fill);
      canvas.drawCircle(c, isSel ? 13 : 10, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5);
      final tp = TextPainter(
        text: TextSpan(text: '${i + 1}', style: TextStyle(color: Colors.white, fontSize: isSel ? 12 : 10, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => old.lines != lines || old.selected != selected;
}
