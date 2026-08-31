import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_service.dart';
import '../../state/engine_providers.dart';
import '../../workspace/workspace.dart';

/// AI 一括修正。指示文から変更案を作らせ（fix）、選んだものだけ適用する（fix --apply-from）。
Future<bool> showFixDialog(BuildContext context, WidgetRef ref, {required PageRef page}) async {
  final applied = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _FixDialog(page: page),
  );
  return applied ?? false;
}

enum _Scope { page, volume, all }

class _FixDialog extends ConsumerStatefulWidget {
  const _FixDialog({required this.page});
  final PageRef page;
  @override
  ConsumerState<_FixDialog> createState() => _FixDialogState();
}

class _FixDialogState extends ConsumerState<_FixDialog> {
  final _instruction = TextEditingController();
  _Scope _scope = _Scope.page;
  bool _withImages = false;
  Job? _job;
  List<Map<String, dynamic>> _changes = [];
  final Set<int> _selected = {};
  bool _applying = false;
  String? _error;

  Future<void> _propose() async {
    final p = widget.page;
    final args = [
      'fix', p.title, '--run', p.run, '-i', _instruction.text.trim(),
      if (_scope != _Scope.all) ...['--volume', '${p.volume}'],
      if (_scope == _Scope.page) ...['--page', '${p.page}'],
      if (_withImages) '--with-images',
    ];
    final job = await ref.read(jobsProvider.notifier).start(args, label: 'AI 修正案: ${p.title} (${p.run})', run: p.run);
    setState(() { _job = job; _changes = []; _selected.clear(); _error = null; });
    job.stream.listen((e) {
      if (!mounted) return;
      if (e.type == 'change') setState(() { _changes.add(e.data); _selected.add(_changes.length - 1); });
      if (e.type == 'error') setState(() => _error = e.data['message'] as String?);
    }, onDone: () { if (mounted) setState(() {}); });
  }

  Future<void> _apply() async {
    final p = widget.page;
    setState(() => _applying = true);
    final plan = {
      'changes': [
        for (final i in _selected)
          {
            'volume': _changes[i]['volume'], 'page': _changes[i]['page'], 'index': _changes[i]['index'],
            'speaker': _changes[i]['speaker'], 'text': _changes[i]['text'], 'panel': _changes[i]['panel'],
            'reason': _changes[i]['reason'] ?? '',
          }
      ],
    };
    final file = File('${Directory.systemTemp.path}/manga_dialogue_fix_${DateTime.now().millisecondsSinceEpoch}.json');
    file.writeAsStringSync(jsonEncode(plan));
    final events = await ref.read(engineServiceProvider).query(['fix', p.title, '--run', p.run, '--apply-from', file.path]);
    file.deleteSync();
    if (!mounted) return;
    final err = events.where((e) => e.type == 'error').map((e) => e.data['message'] as String?).firstOrNull;
    if (err != null) {
      setState(() { _error = err; _applying = false; });
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = _job?.isRunning ?? false;
    final done = _job != null && !running;
    return AlertDialog(
      title: const Text('AI による一括修正'),
      content: SizedBox(
        width: 760,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('範囲: '),
                SegmentedButton<_Scope>(
                  segments: [
                    ButtonSegment(value: _Scope.page, label: Text('このページ (p${widget.page.page})')),
                    ButtonSegment(value: _Scope.volume, label: Text('${widget.page.volume}巻')),
                    const ButtonSegment(value: _Scope.all, label: Text('全巻')),
                  ],
                  selected: {_scope},
                  onSelectionChanged: running ? null : (v) => setState(() => _scope = v.first),
                ),
                const SizedBox(width: 16),
                Checkbox(value: _withImages, onChanged: running ? null : (v) => setState(() => _withImages = v ?? false)),
                const Text('画像も送る（話者の再判定向け。費用増）'),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _instruction,
              enabled: !running,
              maxLines: 2,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '修正の指示',
                hintText: '例: 「うう」の話者を「主人公の母（仮）」にする / 「不明」のうち尻尾が明確なものを再判定する',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  icon: running ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high),
                  label: Text(running ? '提案を作成中…' : '変更案を作成'),
                  onPressed: running || _instruction.text.trim().isEmpty ? null : _propose,
                ),
                if (running) TextButton(onPressed: () => ref.read(jobsProvider.notifier).cancel(_job!), child: const Text('キャンセル')),
                const Spacer(),
                if (done) Text('変更案 ${_changes.length} 件（選択 ${_selected.length}）', style: const TextStyle(color: Colors.grey)),
              ],
            ),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: TextStyle(color: scheme.error))),
            const Divider(),
            Expanded(
              child: _changes.isEmpty
                  ? Center(child: Text(done ? '変更案はありませんでした' : '指示を入力して「変更案を作成」を押してください', style: const TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _changes.length,
                      itemBuilder: (context, i) {
                        final c = _changes[i];
                        final before = c['before'] as Map<String, dynamic>?;
                        final diffs = <String>[];
                        for (final f in ['speaker', 'text', 'panel']) {
                          if (c[f] != null) diffs.add('$f: ${before?[f]} → ${c[f]}');
                        }
                        return CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selected.contains(i),
                          onChanged: (v) => setState(() => v == true ? _selected.add(i) : _selected.remove(i)),
                          title: Text('${c['volume']}巻 p${(c['page'] as num).toString().padLeft(3, '0')} #${(c['index'] as num) + 1}  「${before?['text'] ?? ''}」', maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text('${diffs.join('   ')}\n${c['reason'] ?? ''}', style: const TextStyle(fontSize: 12)),
                          isThreeLine: true,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _applying ? null : () => Navigator.pop(context, false), child: const Text('閉じる')),
        FilledButton(
          onPressed: _selected.isEmpty || _applying || running ? null : _apply,
          child: Text(_applying ? '適用中…' : '選択した ${_selected.length} 件を適用'),
        ),
      ],
    );
  }
}
