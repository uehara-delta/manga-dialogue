import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine_service.dart';
import '../../state/engine_providers.dart';
import '../../state/providers.dart';

/// キャプチャの実行ダイアログ。新しい作品の追加と、既存作品への巻の追加に使う。
Future<Job?> showCaptureDialog(BuildContext context, WidgetRef ref, {String? title, int? nextVolume}) async {
  final settings = ref.read(settingsProvider);
  final titleCtl = TextEditingController(text: title ?? '');
  final volumeCtl = TextEditingController(text: '${nextVolume ?? 1}');
  final maxPages = TextEditingController(text: '300');
  final delay = TextEditingController(text: settings.captureDelay.toString());
  var key = settings.captureKey;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(title == null ? '新しい作品をキャプチャ' : '$title に巻を追加'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Kindle で対象の巻の表紙（1 ページ目）を表示してから実行してください。実行中はマウス・キーボードに触れないでください。', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 8),
              if (title == null) TextField(controller: titleCtl, decoration: const InputDecoration(labelText: '作品名（フォルダ名になります）')),
              Row(
                children: [
                  Expanded(child: TextField(controller: volumeCtl, decoration: const InputDecoration(labelText: '巻'), keyboardType: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: maxPages, decoration: const InputDecoration(labelText: '最大枚数'), keyboardType: TextInputType.number)),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: key,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'ページ送りキー',
                        helperText: Platform.isWindows ? 'Windows ではスペース = ←' : null,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'space', child: Text('スペース')),
                        DropdownMenuItem(value: 'left', child: Text('←')),
                        DropdownMenuItem(value: 'right', child: Text('→')),
                      ],
                      onChanged: (v) => setState(() => key = v ?? key),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: delay, decoration: const InputDecoration(labelText: '待機秒数'), keyboardType: TextInputType.number)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('キャプチャ開始')),
        ],
      ),
    ),
  );
  if (ok != true) return null;
  final t = titleCtl.text.trim();
  final v = int.tryParse(volumeCtl.text.trim()) ?? 1;
  if (t.isEmpty) return null;
  ref.read(settingsProvider.notifier).update((s) {
    s.captureKey = key;
    s.captureDelay = double.tryParse(delay.text.trim()) ?? s.captureDelay;
  });
  return ref.read(jobsProvider.notifier).start(
    ['capture', t, '--volume', '$v', '--key', key, '--delay', delay.text.trim(), '--max-pages', maxPages.text.trim()],
    label: 'キャプチャ: $t $v巻',
  );
}
