import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../../workspace/workspace.dart';
import '../capture/capture_dialog.dart';
import '../jobs/run_dialogs.dart';

/// 選択中の作品: 巻ごとのキャプチャ枚数と抽出状況、開く・抽出・整理・エクスポート、巻の追加。
class WorkDetail extends ConsumerStatefulWidget {
  const WorkDetail({super.key, required this.work});
  final WorkSummary work;
  @override
  ConsumerState<WorkDetail> createState() => _WorkDetailState();
}

class _WorkDetailState extends ConsumerState<WorkDetail> {
  String? _run;
  Future<int>? _sizeFuture;

  /// 数千ファイルの走査を UI スレッドから外す
  static Future<int> _computeSize(String path) => Isolate.run(() {
        var total = 0;
        for (final f in Directory(path).listSync(recursive: true).whereType<File>()) {
          total += f.lengthSync();
        }
        return total;
      });

  WorkSummary get work => widget.work;

  String? get run {
    final runs = work.runs;
    if (runs.isEmpty) return null;
    final remembered = _run ?? ref.read(settingsProvider).lastRun[work.title];
    return runs.contains(remembered) ? remembered : runs.first;
  }

  void _remember(String r) {
    setState(() => _run = r);
    ref.read(settingsProvider.notifier).update((s) => s.lastRun[work.title] = r);
  }

  Future<void> _push(String route) async {
    await context.push(route);
    if (mounted) ref.read(worksProvider.notifier).refresh();
  }

  void _open(int volume) {
    final r = run;
    if (r == null) return;
    _remember(r);
    _push('/edit/${Uri.encodeComponent(work.title)}/$r/$volume');
  }

  @override
  Widget build(BuildContext context) {
    final ws = ref.watch(workspaceProvider);
    final scheme = Theme.of(context).colorScheme;
    final r = run;
    final characters = r == null ? 0 : ws.loadCharacters(work.title, r).length;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: Text(work.title, style: Theme.of(context).textTheme.headlineSmall)),
            PopupMenuButton<String>(
              tooltip: 'その他',
              onSelected: (v) => switch (v) {
                'export' => r == null ? null : showExportDialog(context, ref, title: work.title, run: r),
                'delete_run' => _confirmDeleteRun(),
                'delete_work' => _confirmDeleteWork(),
                _ => null,
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'export', child: Text('エクスポート…')),
                const PopupMenuDivider(),
                if (r != null) PopupMenuItem(value: 'delete_run', child: Text('抽出結果「$r」を削除…')),
                const PopupMenuItem(value: 'delete_work', child: Text('この作品を削除…')),
              ],
            ),
          ],
        ),
        const SizedBox(height: 4),
        FutureBuilder<int>(
          future: _sizeFuture ??= _computeSize(ws.workDir(work.title)),
          builder: (context, snap) => Text(
            '${work.volumes.length} 巻   使用容量 ${snap.hasData ? _fmtSize(snap.data!) : '…'}${r != null ? '   台帳 $characters 名' : ''}',
            style: const TextStyle(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Column(
            children: [
              for (final v in work.volumes) _volumeRow(context, ws, v, r),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('巻を追加してキャプチャ'),
                subtitle: const Text('Kindle で次の巻の表紙を表示してから実行してください'),
                onTap: () async {
                  final next = work.volumes.isEmpty ? 1 : work.volumes.last + 1;
                  final job = await showCaptureDialog(context, ref, title: work.title, nextVolume: next);
                  if (job != null && context.mounted) _push('/jobs');
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        if (work.runs.length > 1)
          Row(
            children: [
              const Text('抽出モデル: ', style: TextStyle(color: Colors.grey)),
              DropdownButton<String>(
                value: r,
                isDense: true,
                underline: const SizedBox(),
                items: [for (final x in work.runs) DropdownMenuItem(value: x, child: Text(x))],
                onChanged: (v) { if (v != null) _remember(v); },
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'モデルごとに抽出結果を分けて保持しています。最近使ったものが先頭です',
                child: Icon(Icons.info_outline, size: 16, color: scheme.outline),
              ),
            ],
          ),
      ],
    );
  }

  Widget _volumeRow(BuildContext context, Workspace ws, int volume, String? r) {
    final pages = ws.listPages(work.title, volume).length;
    final done = r == null ? 0 : ws.countOutputs(work.title, r, volume);
    final scheme = Theme.of(context).colorScheme;
    final String status;
    final Color statusColor;
    if (pages == 0) {
      status = 'キャプチャなし';
      statusColor = scheme.outline;
    } else if (done == 0) {
      status = '未抽出';
      statusColor = scheme.outline;
    } else if (done < pages) {
      status = '抽出 $done / $pages';
      statusColor = scheme.tertiary;
    } else {
      status = '抽出済み';
      statusColor = scheme.primary;
    }
    return ListTile(
      leading: Text('$volume巻', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      title: Text('キャプチャ $pages 枚'),
      subtitle: Text(status, style: TextStyle(color: statusColor)),
      trailing: Wrap(
        spacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton(onPressed: pages == 0 ? null : () => _push('/captures/${Uri.encodeComponent(work.title)}/$volume'), child: const Text('キャプチャを確認')),
          TextButton(
            onPressed: pages == 0 ? null : () async {
              final job = await showExtractDialog(
                context, ref,
                title: work.title, volumes: [volume], runs: work.runs,
                defaultRun: r, defaultModel: ref.read(settingsProvider).defaultModel,
              );
              if (job != null && context.mounted) {
                if (job.run != null) _remember(job.run!);
                _push('/jobs');
              }
            },
            child: Text(done == 0 ? '抽出' : '再抽出…'),
          ),
          FilledButton(onPressed: done == 0 ? null : () => _open(volume), child: const Text('開く')),
          PopupMenuButton<String>(
            tooltip: 'この巻の操作',
            onSelected: (v) => switch (v) { 'delete' => _confirmDeleteVolume(volume), _ => null },
            itemBuilder: (context) => const [PopupMenuItem(value: 'delete', child: Text('この巻を削除…'))],
          ),
        ],
      ),
      onTap: done == 0 ? null : () => _open(volume),
    );
  }

  Future<void> _confirm(String title, String body, VoidCallback action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error), onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok == true) {
      action();
      ref.read(worksProvider.notifier).refresh();
    }
  }

  void _confirmDeleteVolume(int volume) => _confirm('$volume巻を削除しますか？', 'キャプチャ画像と、すべての抽出データのこの巻の結果を削除します。元に戻せません。', () => ref.read(workspaceProvider).deleteVolume(work.title, volume));

  void _confirmDeleteRun() {
    final r = run;
    if (r == null) return;
    final locked = ref.read(workspaceProvider).isLocked(work.title, r);
    if (locked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('エンジンが実行中のため削除できません')));
      return;
    }
    _confirm('抽出結果「$r」を削除しますか？', 'このモデルの台帳と全巻の抽出結果を削除します。キャプチャ画像は残ります。元に戻せません。', () => ref.read(workspaceProvider).deleteRun(work.title, r));
  }

  void _confirmDeleteWork() => _confirm('「${work.title}」を削除しますか？', 'キャプチャ画像・台帳・抽出結果をすべて削除します。元に戻せません。', () => ref.read(workspaceProvider).deleteWork(work.title));

  static String _fmtSize(int bytes) {
    if (bytes >= 1 << 30) return '${(bytes / (1 << 30)).toStringAsFixed(1)} GB';
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(0)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
