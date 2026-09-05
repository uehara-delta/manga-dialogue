import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_service.dart';
import '../../state/engine_providers.dart';

/// 抽出（extract）の実行ダイアログ
Future<Job?> showExtractDialog(BuildContext context, WidgetRef ref, {required String title, required List<int> volumes, required List<String> runs, String? defaultRun, String? defaultModel}) async {
  var volume = volumes.isEmpty ? 1 : volumes.first;
  final modelName = defaultModel ?? 'gemini-3.7-flash';
  // 保存先は「同じモデルで既に抽出した結果」があればそれ、なければモデル名
  final model = TextEditingController(text: modelName);
  final run = TextEditingController(text: defaultRun ?? (runs.contains(modelName) ? modelName : modelName));
  var resume = true;
  var verifyAfter = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('抽出を実行: $title'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: volume,
                decoration: const InputDecoration(labelText: '巻'),
                items: [for (final v in (volumes.isEmpty ? [1] : volumes)) DropdownMenuItem(value: v, child: Text('$v'))],
                onChanged: (v) => setState(() => volume = v ?? volume),
              ),
              TextField(
                controller: model,
                decoration: const InputDecoration(labelText: 'モデル', helperText: 'gemini-* / claude-* / gpt-*'),
                onChanged: (v) { if (!runs.contains(run.text)) run.text = v.trim(); },
              ),
              TextField(controller: run, decoration: const InputDecoration(labelText: '結果の保存先', helperText: '同じ保存先で続けると台帳を引き継ぎます。通常はモデル名のままで構いません')),
              CheckboxListTile(
                value: resume,
                contentPadding: EdgeInsets.zero,
                title: const Text('出力済みページをスキップ（--resume）'),
                onChanged: (v) => setState(() => resume = v ?? true),
              ),
              CheckboxListTile(
                value: verifyAfter,
                contentPadding: EdgeInsets.zero,
                title: const Text('抽出完了後に台帳の外見を検証する（verify-book）'),
                subtitle: const Text('主要キャラの外見を、実際に話しているページの画像から書き直します', style: TextStyle(fontSize: 11)),
                onChanged: (v) => setState(() => verifyAfter = v ?? true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('実行')),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  final runName = run.text.trim();
  final modelId = model.text.trim();
  final job = await ref.read(jobsProvider.notifier).start(
    ['extract', title, '--volume', '$volume', '--run', runName, '--model', modelId, if (resume) '--resume'],
    label: '抽出: $title $volume巻 ($runName)',
    run: runName,
  );
  if (verifyAfter) {
    // 抽出が正常終了したら、同じ run・同じモデルで台帳の外見を検証する
    job.stream.listen(null, onDone: () {
      if (job.status != JobStatus.succeeded) return;
      ref.read(jobsProvider.notifier).start(
        ['verify-book', title, '--run', runName, '--model', modelId],
        label: '台帳の検証: $title ($runName)',
        run: runName,
      );
    });
  }
  return job;
}

/// エクスポートの実行ダイアログ。巻ごと、または全巻を書き出す。
Future<Job?> showExportDialog(
  BuildContext context, WidgetRef ref, {
  required String title,
  required String run,
  List<int> volumes = const [],
  int? defaultVolume,
}) async {
  var format = 'csv';
  int? volume = defaultVolume;
  var excel = true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('エクスポート: $title'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int?>(
                initialValue: volume,
                decoration: const InputDecoration(labelText: '巻'),
                items: [
                  for (final v in volumes) DropdownMenuItem(value: v, child: Text('$v巻')),
                  const DropdownMenuItem(value: null, child: Text('全巻をまとめて')),
                ],
                onChanged: (v) => setState(() => volume = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: format,
                decoration: const InputDecoration(labelText: '形式'),
                items: const [
                  DropdownMenuItem(value: 'csv', child: Text('CSV')),
                  DropdownMenuItem(value: 'tsv', child: Text('TSV')),
                  DropdownMenuItem(value: 'markdown', child: Text('Markdown')),
                ],
                onChanged: (v) => setState(() => format = v ?? format),
              ),
              if (format != 'markdown')
                CheckboxListTile(
                  value: excel,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Excel に対応した形式（BOM 付き UTF-8）'),
                  subtitle: const Text('Excel で開いても文字化けしません。プログラムで読む場合はオフに', style: TextStyle(fontSize: 11)),
                  onChanged: (v) => setState(() => excel = v ?? true),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('保存先フォルダを選ぶ')),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  final ext = {'csv': 'csv', 'tsv': 'tsv', 'markdown': 'md'}[format]!;
  final dir = await FilePicker.getDirectoryPath(dialogTitle: '書き出し先フォルダ');
  if (dir == null) return null;
  final suffix = volume == null ? '' : '_${volume.toString().padLeft(2, '0')}';
  final path = p.join(dir, '$title$suffix.$ext');
  return ref.read(jobsProvider.notifier).start(
    ['export', title, '--run', run, '--format', format, '--out', path, if (volume != null) ...['--volume', '$volume'], if (!excel) '--no-excel'],
    label: 'エクスポート: $title${volume == null ? ' 全巻' : ' $volume巻'} → $path',
  );
}
