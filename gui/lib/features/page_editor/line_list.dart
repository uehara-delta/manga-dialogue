import 'package:flutter/material.dart';

import '../../models/models.dart';

/// セリフの一覧。行の選択、話者の変更、本文の編集、コマ番号の編集をインラインで行う。
class LineList extends StatelessWidget {
  const LineList({
    super.key,
    required this.lines,
    required this.selected,
    required this.speakers,
    required this.onSelect,
    required this.onSpeaker,
    required this.onText,
    required this.onPanel,
  });
  final List<Line> lines;
  final int? selected;
  final List<String> speakers;
  final void Function(int) onSelect;
  final void Function(int, String) onSpeaker;
  final void Function(int, String) onText;
  final void Function(int, int) onPanel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      itemCount: lines.length,
      itemBuilder: (context, i) {
        final l = lines[i];
        final isSel = i == selected;
        Color? tint;
        if (l.speaker == '不明') {
          tint = scheme.errorContainer.withValues(alpha: 0.5);
        } else if (l.confidence < 0.6) {
          tint = scheme.tertiaryContainer.withValues(alpha: 0.4);
        }
        if (l.manual) tint = scheme.primaryContainer.withValues(alpha: 0.5);
        return Material(
          color: isSel ? scheme.primary.withValues(alpha: 0.12) : tint,
          child: InkWell(
            onTap: () => onSelect(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 28, child: Text('${i + 1}', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], color: Colors.grey))),
                  SizedBox(
                    width: 44,
                    child: _PanelField(value: l.panel, onChanged: (v) => onPanel(i, v)),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 150,
                    child: _SpeakerField(value: l.speaker, options: speakers, onChanged: (v) => onSpeaker(i, v)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: _TextField(value: l.text, onChanged: (v) => onText(i, v))),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 74,
                    child: Text(
                      '${l.confidence.toStringAsFixed(2)} ${_basisLabel(l.basis)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                  if (l.manual) const Icon(Icons.edit, size: 14, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String _basisLabel(String? b) => switch (b) { 'tail' => '尻尾', 'context' => '文脈', 'unknown' => '不明', _ => '' };
}

class _PanelField extends StatelessWidget {
  const _PanelField({required this.value, required this.onChanged});
  final int value;
  final void Function(int) onChanged;
  @override
  Widget build(BuildContext context) => TextFormField(
        key: ValueKey('panel-$value'),
        initialValue: '$value',
        textAlign: TextAlign.center,
        decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
        style: const TextStyle(fontSize: 13),
        onFieldSubmitted: (v) { final n = int.tryParse(v); if (n != null && n != value) onChanged(n); },
      );
}

class _SpeakerField extends StatelessWidget {
  const _SpeakerField({required this.value, required this.options, required this.onChanged});
  final String value;
  final List<String> options;
  final void Function(String) onChanged;
  @override
  Widget build(BuildContext context) {
    final items = {...options, value}.toList();
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isDense: true,
        isExpanded: true,
        style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface, fontWeight: value == '不明' ? FontWeight.normal : FontWeight.bold),
        items: [for (final s in items) DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis))],
        onChanged: (v) { if (v != null && v != value) onChanged(v); },
      ),
    );
  }
}

class _TextField extends StatefulWidget {
  const _TextField({required this.value, required this.onChanged});
  final String value;
  final void Function(String) onChanged;
  @override
  State<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends State<_TextField> {
  late final _c = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(_TextField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value && _c.text != widget.value) _c.text = widget.value;
  }
  @override
  Widget build(BuildContext context) => Focus(
        onFocusChange: (has) { if (!has && _c.text != widget.value) widget.onChanged(_c.text); },
        child: TextField(
          controller: _c,
          decoration: const InputDecoration(isDense: true, border: InputBorder.none, contentPadding: EdgeInsets.zero),
          style: const TextStyle(fontSize: 13),
          onSubmitted: (v) { if (v != widget.value) widget.onChanged(v); },
        ),
      );
}
