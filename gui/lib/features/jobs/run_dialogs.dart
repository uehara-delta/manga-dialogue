import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_service.dart';
import '../../state/engine_providers.dart';

/// 抽出（extract）の実行ダイアログ
Future<Job?> showExtractDialog(BuildContext context, WidgetRef ref, {required String title, required List<int> volumes, required List<String> runs, String? defaultRun, String? defaultModel}) async {
  var volume = volumes.isEmpty ? 1 : volumes.first;
  final run = TextEditingController(text: defaultRun ?? (runs.isEmpty ? 'default' : runs.first));
  final model = TextEditingController(text: defaultModel ?? 'gemini-3.7-flash');
  var resume = true;
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
              TextField(controller: run, decoration: const InputDecoration(labelText: '抽出データの名前', helperText: '通常は変えなくてよい。別のモデルで比較したいときだけ新しい名前にする')),
              TextField(controller: model, decoration: const InputDecoration(labelText: 'モデル')),
              CheckboxListTile(
                value: resume,
                contentPadding: EdgeInsets.zero,
                title: const Text('出力済みページをスキップ（--resume）'),
                onChanged: (v) => setState(() => resume = v ?? true),
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
  return ref.read(jobsProvider.notifier).start(
    ['extract', title, '--volume', '$volume', '--run', run.text.trim(), '--model', model.text.trim(), if (resume) '--resume'],
    label: '抽出: $title $volume巻 (${run.text.trim()})',
    run: run.text.trim(),
  );
}

/// エクスポートの実行ダイアログ
Future<Job?> showExportDialog(BuildContext context, WidgetRef ref, {required String title, required String run}) async {
  var format = 'csv';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('エクスポート: $title ($run)'),
        content: DropdownButtonFormField<String>(
          initialValue: format,
          decoration: const InputDecoration(labelText: '形式'),
          items: const [
            DropdownMenuItem(value: 'csv', child: Text('CSV')),
            DropdownMenuItem(value: 'tsv', child: Text('TSV')),
            DropdownMenuItem(value: 'markdown', child: Text('Markdown')),
          ],
          onChanged: (v) => setState(() => format = v ?? format),
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
  final path = p.join(dir, '${title}_$run.$ext');
  return ref.read(jobsProvider.notifier).start(
    ['export', title, '--run', run, '--format', format, '--out', path],
    label: 'エクスポート: $title ($run) → $path',
  );
}
