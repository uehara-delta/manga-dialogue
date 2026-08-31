import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../state/engine_providers.dart';
import '../../state/providers.dart';

/// キャラ台帳の一覧と編集。名前の変更（統合）はエンジンの rename に委ねるため、ここでは別名と外見のみ編集する。
class CharactersPanel extends ConsumerWidget {
  const CharactersPanel({super.key, required this.title, required this.run});
  final String title;
  final String run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final characters = ref.watch(charactersProvider);
    final counts = ref.watch(workspaceProvider).speakerCounts(title, run);
    final sorted = [...characters]..sort((a, b) => (counts[b.name] ?? 0).compareTo(counts[a.name] ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Text('キャラ台帳  ${characters.length} 名（仮名 ${characters.where((c) => c.isProvisional).length}）', style: const TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.merge_type, size: 16),
                label: const Text('台帳を整理'),
                onPressed: () => _consolidate(context, ref),
              ),
              TextButton.icon(
                icon: const Icon(Icons.rule, size: 16),
                label: const Text('改名候補のレビュー'),
                onPressed: () => context.push('/review/${Uri.encodeComponent(title)}/$run'),
              ),
              TextButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('追加'),
                onPressed: () => _editDialog(context, ref, characters, null),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (context, i) {
              final c = sorted[i];
              return ListTile(
                dense: true,
                title: Row(children: [
                  Text(c.name, style: TextStyle(fontWeight: FontWeight.bold, color: c.isProvisional ? Colors.grey.shade700 : null)),
                  const SizedBox(width: 8),
                  Text('${counts[c.name] ?? 0} 件', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (c.aliases.isNotEmpty) ...[const SizedBox(width: 8), Text('別名: ${c.aliases.join(', ')}', style: const TextStyle(fontSize: 11, color: Colors.grey))],
                ]),
                subtitle: Text(c.appearance, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: IconButton(
                  tooltip: '別のキャラに統合（rename）',
                  icon: const Icon(Icons.call_merge, size: 18),
                  onPressed: () => _mergeDialog(context, ref, characters, c),
                ),
                onTap: () => _editDialog(context, ref, characters, c),
              );
            },
          ),
        ),
      ],
    );
  }

  /// consolidate をジョブとして実行し、終わったらレビュー画面を開く
  Future<void> _consolidate(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('台帳を整理しますか？'),
        content: const Text('全セリフを通読させて仮名の解決と重複の統合を提案させます。確信度 0.8 以上は自動で適用され、それ以外は改名候補として保留されます。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('実行')),
        ],
      ),
    );
    if (ok != true) return;
    final job = await ref.read(jobsProvider.notifier).start(['consolidate', title, '--run', run], label: '台帳の整理: $title ($run)', run: run);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('台帳の整理を開始しました。完了するとレビュー画面を開きます')));
    job.stream.listen(null, onDone: () {
      if (!context.mounted) return;
      ref.read(charactersProvider.notifier).load(title, run);
      final applied = job.events.where((e) => e.type == 'done').map((e) => e.data['applied']).firstOrNull;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(job.errorMessage ?? '台帳の整理が完了しました（自動適用 $applied 件）')));
      if (job.errorMessage == null) context.push('/review/${Uri.encodeComponent(title)}/$run');
    });
  }

  /// rename で別キャラに統合する
  Future<void> _mergeDialog(BuildContext context, WidgetRef ref, List<Character> all, Character from) async {
    String? target;
    final counts = ref.read(workspaceProvider).speakerCounts(title, run);
    final others = [...all.where((c) => c != from)]..sort((a, b) => (counts[b.name] ?? 0).compareTo(counts[a.name] ?? 0));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('「${from.name}」を統合'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('統合先を選んでください。「${from.name}」のセリフ ${counts[from.name] ?? 0} 件の話者が置き換わり、名前は統合先の別名に残ります。'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: target,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '統合先'),
                  items: [for (final c in others) DropdownMenuItem(value: c.name, child: Text('${c.name}  (${counts[c.name] ?? 0} 件)', overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => target = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
            FilledButton(onPressed: target == null ? null : () => Navigator.pop(context, true), child: const Text('統合')),
          ],
        ),
      ),
    );
    if (ok != true || target == null || !context.mounted) return;
    final events = await ref.read(engineServiceProvider).query(['rename', title, from.name, target!, '--run', run]);
    if (!context.mounted) return;
    final err = events.where((e) => e.type == 'error').map((e) => e.data['message'] as String?).firstOrNull;
    final done = events.where((e) => e.type == 'done').map((e) => e.data).firstOrNull;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? '統合しました（出力 ${done?['replaced']} 件を置換）')));
    ref.read(charactersProvider.notifier).load(title, run);
    final s = ref.read(pageEditorProvider);
    if (s != null) ref.read(pageEditorProvider.notifier).open(s.ref);
  }

  Future<void> _editDialog(BuildContext context, WidgetRef ref, List<Character> all, Character? c) async {
    final name = TextEditingController(text: c?.name ?? '');
    final aliases = TextEditingController(text: c?.aliases.join(', ') ?? '');
    final appearance = TextEditingController(text: c?.appearance ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(c == null ? 'キャラを追加' : 'キャラを編集'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: '名前'), enabled: c == null),
              if (c != null) const Padding(padding: EdgeInsets.only(top: 4), child: Text('名前の変更・統合はエンジンの rename で行います（出力の話者も一括で置き換わります）', style: TextStyle(fontSize: 11, color: Colors.grey))),
              TextField(controller: aliases, decoration: const InputDecoration(labelText: '別名（カンマ区切り）')),
              TextField(controller: appearance, decoration: const InputDecoration(labelText: '外見'), maxLines: 3),
            ],
          ),
        ),
        actions: [
          if (c != null) TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('削除', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('保存')),
        ],
      ),
    );
    if (result == null) return;
    final list = [...all];
    if (result == 'delete') {
      list.remove(c);
    } else {
      final parsed = aliases.text.split(RegExp(r'[,、]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (c == null) {
        if (name.text.trim().isEmpty) return;
        list.add(Character(name: name.text.trim(), aliases: parsed, appearance: appearance.text.trim()));
      } else {
        c.aliases = parsed;
        c.appearance = appearance.text.trim();
      }
    }
    ref.read(charactersProvider.notifier).save(title, run, list);
  }
}
