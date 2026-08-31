import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/models.dart';
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
                onTap: () => _editDialog(context, ref, characters, c),
              );
            },
          ),
        ),
      ],
    );
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
