import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../../workspace/workspace.dart';

/// 巻のキャプチャをサムネイルで確認し、不要なページ（Kindle の終了画面など）を削除する。
class CapturesScreen extends ConsumerStatefulWidget {
  const CapturesScreen({super.key, required this.title, required this.volume});
  final String title;
  final int volume;

  @override
  ConsumerState<CapturesScreen> createState() => _CapturesScreenState();
}

class _CapturesScreenState extends ConsumerState<CapturesScreen> {
  final Set<int> _selected = {};

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceProvider);
    final pages = ws.listPages(widget.title, widget.volume);
    final runs = ws.listRuns(widget.title);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        title: Text('${widget.title} ${widget.volume}巻 のキャプチャ  ${pages.length} 枚'),
        actions: [
          if (_selected.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: Text('${_selected.length} 枚を削除'),
              onPressed: () => _deleteSelected(ws, runs),
            ),
        ],
      ),
      body: pages.isEmpty
          ? const Center(child: Text('キャプチャがありません'))
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 260, childAspectRatio: 1.15, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: pages.length,
              itemBuilder: (context, i) {
                final page = pages[i];
                final selected = _selected.contains(page);
                final extracted = runs.any((r) => File(ws.outputPath(PageRef(title: widget.title, run: r, volume: widget.volume, page: page))).existsSync());
                return InkWell(
                  onTap: () => setState(() => selected ? _selected.remove(page) : _selected.add(page)),
                  onDoubleTap: () {
                    final run = ref.read(settingsProvider).lastRun[widget.title] ?? (runs.isNotEmpty ? runs.first : null);
                    if (run != null) context.push('/edit/${Uri.encodeComponent(widget.title)}/$run/${widget.volume}?page=$page');
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      children: [
                        Expanded(child: Image.file(File(ws.capturePath(PageRef(title: widget.title, run: '', volume: widget.volume, page: page))), fit: BoxFit.contain, cacheWidth: 500)),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('${page.toString().padLeft(4, '0')}${extracted ? '  抽出済' : ''}', style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Future<void> _deleteSelected(Workspace ws, List<String> runs) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${_selected.length} 枚を削除しますか？'),
        content: Text('キャプチャ画像と、${runs.isEmpty ? '' : '抽出データ（${runs.join(', ')}）の'}該当ページの結果を削除します。元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;
    for (final page in _selected) {
      ws.deleteCapturePage(widget.title, widget.volume, page);
    }
    setState(() => _selected.clear());
    ref.read(worksProvider.notifier).refresh();
  }
}
