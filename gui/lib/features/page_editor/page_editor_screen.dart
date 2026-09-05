import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../engine/engine_service.dart';
import '../../models/models.dart';
import '../../state/engine_providers.dart';
import '../../state/providers.dart';
import '../../workspace/workspace.dart';
import '../../widgets/app_actions.dart';
import '../../widgets/split_pane.dart';
import '../characters/characters_panel.dart';
import '../jobs/run_dialogs.dart';
import 'line_list.dart';
import 'page_image.dart';

class PageEditorScreen extends ConsumerStatefulWidget {
  const PageEditorScreen({super.key, required this.title, required this.run, required this.volume, this.page});
  final String title;
  final String run;
  final int volume;
  final int? page;

  @override
  ConsumerState<PageEditorScreen> createState() => _PageEditorScreenState();
}

class _PageEditorScreenState extends ConsumerState<PageEditorScreen> {
  bool _showCharacters = false;
  bool _showMarkers = true;

  /// 分割位置。ドラッグ中はローカルに持ち、離したときに設定へ保存する
  static const _splitKey = 'editor.split';
  static const _charactersKey = 'editor.characters';
  double? _split;
  double? _charactersSplit;

  void _saveLayout(String key, double v) => ref.read(settingsProvider.notifier).update((s) => s.layout[key] = v);

  /// ジョブが終わったら現在のページと台帳を読み直す
  void _watchJob(Job job) {
    job.stream.listen(null, onDone: () {
      if (!mounted) return;
      final n = ref.read(pageEditorProvider.notifier);
      final s = ref.read(pageEditorProvider);
      if (s != null) n.open(s.ref);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${job.label}: ${job.status == JobStatus.succeeded ? '完了' : job.errorMessage ?? '終了'}')));
    });
  }

  Future<void> _repassCurrent(PageEditorState s, {bool force = false}) async {
    final job = await ref.read(jobsProvider.notifier).start(
      ['repass', s.ref.title, '--run', s.ref.run, '--volume', '${s.ref.volume}', '--page', '${s.ref.page}', if (force) '--force'],
      label: '再抽出: ${s.ref.title} ${s.ref.volume}巻 p${s.ref.page} (${s.ref.run})',
      run: s.ref.run,
    );
    _watchJob(job);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(pageEditorProvider.notifier).open(PageRef(title: widget.title, run: widget.run, volume: widget.volume, page: widget.page ?? 1));
      ref.read(settingsProvider.notifier).update((s) => s.lastRun[widget.title] = widget.run);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(pageEditorProvider);
    final n = ref.read(pageEditorProvider.notifier);
    final ws = ref.watch(workspaceProvider);
    final characters = ref.watch(charactersProvider);
    final speakers = [for (final n in specialSpeakers) SpeakerOption(n), for (final c in characters) SpeakerOption(c.name, c.aliases)];
    final locked = ws.isLocked(widget.title, widget.run);
    if (s == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final layout = ref.watch(settingsProvider.select((st) => st.layout));
    final r = s.result;
    final lineList = r == null
        ? const SizedBox.shrink()
        : AbsorbPointer(
            absorbing: locked,
            child: LineList(
              lines: r.lines,
              selected: s.selected,
              speakers: speakers,
              onSelect: n.select,
              onSpeaker: (i, v) => n.editLine(i, (l) => l.speaker = v),
              onText: (i, v) => n.editLine(i, (l) => l.text = v),
              onPanel: (i, v) => n.editLine(i, (l) => l.panel = v),
              onDelete: n.removeLine,
            ),
          );

    return CallbackShortcuts(
      bindings: {
        // テキスト欄の編集中はカーソル移動が優先され、ここには届かない
        const SingleActivator(LogicalKeyboardKey.arrowLeft): n.next,
        const SingleActivator(LogicalKeyboardKey.arrowRight): n.prev,
        const SingleActivator(LogicalKeyboardKey.arrowLeft, meta: true): n.next,
        const SingleActivator(LogicalKeyboardKey.arrowRight, meta: true): n.prev,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): n.undo,
        const SingleActivator(LogicalKeyboardKey.keyM): () => setState(() => _showMarkers = !_showMarkers),
        const SingleActivator(LogicalKeyboardKey.backspace, meta: true): () {
          final sel = ref.read(pageEditorProvider)?.selected;
          if (sel != null && !locked) n.removeLine(sel);
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.home_outlined), onPressed: () => context.go('/')),
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title),
                const SizedBox(width: 12),
                _VolumeSwitcher(title: widget.title, run: widget.run, volume: widget.volume),
                if (ws.listRuns(widget.title).length > 1 || ws.runModel(widget.title, widget.run) != null) ...[
                  const SizedBox(width: 12),
                  Text(
                    () {
                      final m = ws.runModel(widget.title, widget.run);
                      return m == null || m == widget.run ? '抽出モデル: ${widget.run}' : '抽出モデル: ${widget.run}（$m）';
                    }(),
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ],
            ),
            actions: [
              if (locked) const Padding(padding: EdgeInsets.only(right: 12), child: Chip(label: Text('エンジン実行中（読み取り専用）'))),
              IconButton(tooltip: '次のページ（左へ進む） ←', icon: const Icon(Icons.chevron_left), onPressed: s.hasNext ? n.next : null),
              _PageJump(pages: s.pages, current: s.ref.page, onJump: n.goTo),
              IconButton(tooltip: '前のページ（右へ戻る） →', icon: const Icon(Icons.chevron_right), onPressed: s.hasPrev ? n.prev : null),
              const VerticalDivider(),
              IconButton(
                tooltip: _showMarkers ? '番号マーカーを隠す (M)' : '番号マーカーを表示 (M)',
                icon: Icon(_showMarkers ? Icons.pin_drop : Icons.pin_drop_outlined),
                onPressed: () => setState(() => _showMarkers = !_showMarkers),
              ),
              IconButton(tooltip: '元に戻す (⌘Z)', icon: const Icon(Icons.undo), onPressed: s.undo != null ? n.undo : null),
              IconButton(tooltip: 'キャラ台帳', icon: Icon(_showCharacters ? Icons.people : Icons.people_outline), onPressed: () => setState(() => _showCharacters = !_showCharacters)),
              IconButton(
                tooltip: '改名候補のレビュー',
                icon: const Icon(Icons.rule),
                onPressed: () async {
                  await context.push('/review/${Uri.encodeComponent(widget.title)}/${widget.run}');
                  if (mounted) ref.read(pageEditorProvider.notifier).open(s.ref);
                },
              ),
              const VerticalDivider(),
              IconButton(
                tooltip: r == null ? 'このページを抽出' : (r.isLocked ? 'このページを再抽出（手動修正を上書き）' : 'このページを再抽出'),
                icon: const Icon(Icons.autorenew),
                onPressed: locked
                    ? null
                    : () async {
                        if (r != null && r.isLocked) {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('手動修正を上書きしますか？'),
                              content: const Text('このページには手動で修正した行があります。再抽出すると上書きされます。'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
                                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('上書きして再抽出')),
                              ],
                            ),
                          );
                          if (ok != true) return;
                        }
                        await _repassCurrent(s, force: r?.isLocked ?? false);
                      },
              ),
              IconButton(
                tooltip: 'エクスポート',
                icon: const Icon(Icons.download_outlined),
                onPressed: () async {
                  final job = await showExportDialog(context, ref, title: widget.title, run: widget.run, volumes: ws.listVolumes(widget.title), defaultVolume: widget.volume);
                  if (job != null) _watchJob(job);
                },
              ),
              const AppActions(),
            ],
          ),
          body: SplitPane(
            axis: Axis.horizontal,
            fraction: _split ?? layout[_splitKey] ?? 0.45,
            minFirst: 240,
            minSecond: 320,
            onFractionChanged: (v) => setState(() => _split = v),
            onFractionCommitted: (v) => _saveLayout(_splitKey, v),
            first: PageImage(
              path: ws.capturePath(s.ref),
              lines: r?.lines ?? const [],
              selected: s.selected,
              showMarkers: _showMarkers,
              onSelect: n.select,
              onTapEmpty: (x, y) => locked ? null : n.addLine(x: x, y: y),
            ),
            second: r == null
                ? const Center(child: Text('このページの抽出結果はまだありません'))
                : Column(
                    children: [
                      _Toolbar(state: s, locked: locked),
                      const Divider(height: 1),
                      Expanded(
                        child: _showCharacters
                            ? SplitPane(
                                axis: Axis.vertical,
                                fraction: _charactersSplit ?? layout[_charactersKey] ?? 0.55,
                                minFirst: 120,
                                minSecond: 120,
                                onFractionChanged: (v) => setState(() => _charactersSplit = v),
                                onFractionCommitted: (v) => _saveLayout(_charactersKey, v),
                                first: lineList,
                                second: CharactersPanel(title: widget.title, run: widget.run),
                              )
                            : lineList,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({required this.state, required this.locked});
  final PageEditorState state;
  final bool locked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.read(pageEditorProvider.notifier);
    final r = state.result!;
    final sel = state.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Text('${r.lines.length} 件   不明 ${r.unknownCount}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const Spacer(),
          IconButton(tooltip: '行を追加（画像クリックでも追加できます）', icon: const Icon(Icons.add), onPressed: locked ? null : () => n.addLine()),
          IconButton(tooltip: '行を削除', icon: const Icon(Icons.remove), onPressed: locked || sel == null ? null : () => n.removeLine(sel)),
          IconButton(tooltip: '上へ', icon: const Icon(Icons.arrow_upward), onPressed: locked || sel == null || sel == 0 ? null : () => n.moveLine(sel, sel - 1)),
          IconButton(tooltip: '下へ', icon: const Icon(Icons.arrow_downward), onPressed: locked || sel == null || sel >= r.lines.length - 1 ? null : () => n.moveLine(sel, sel + 1)),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('確定'),
            tooltip: 'ページ全体を確定済みにする（再抽出で上書きされない）',
            selected: r.manual,
            onSelected: locked ? null : n.setPageManual,
          ),
        ],
      ),
    );
  }
}

class _PageJump extends StatelessWidget {
  const _PageJump({required this.pages, required this.current, required this.onJump});
  final List<int> pages;
  final int current;
  final void Function(int) onJump;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 120,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: pages.contains(current) ? current : null,
            isDense: true,
            items: [for (final p in pages) DropdownMenuItem(value: p, child: Text('${p.toString().padLeft(4, '0')} / ${pages.length}'))],
            onChanged: (v) { if (v != null) onJump(v); },
          ),
        ),
      );
}


class _VolumeSwitcher extends ConsumerWidget {
  const _VolumeSwitcher({required this.title, required this.run, required this.volume});
  final String title;
  final String run;
  final int volume;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volumes = ref.watch(workspaceProvider).listVolumes(title);
    if (volumes.length <= 1) return Text('$volume巻', style: const TextStyle(fontSize: 16));
    return DropdownButton<int>(
      value: volumes.contains(volume) ? volume : null,
      isDense: true,
      underline: const SizedBox(),
      items: [for (final v in volumes) DropdownMenuItem(value: v, child: Text('$v巻'))],
      onChanged: (v) { if (v != null && v != volume) context.go('/edit/${Uri.encodeComponent(title)}/$run/$v'); },
    );
  }
}
