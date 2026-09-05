import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/models.dart';
import '../../state/engine_providers.dart';
import '../../state/providers.dart';

/// キャラ台帳の一覧と編集。名前の変更（統合）はエンジンの rename に委ねるため、ここでは別名と外見のみ編集する。
class CharactersPanel extends ConsumerStatefulWidget {
  const CharactersPanel({super.key, required this.title, required this.run});
  final String title;
  final String run;

  @override
  ConsumerState<CharactersPanel> createState() => _CharactersPanelState();
}

class _CharactersPanelState extends ConsumerState<CharactersPanel> {
  String _query = '';
  String get title => widget.title;
  String get run => widget.run;

  @override
  Widget build(BuildContext context) {
    final characters = ref.watch(charactersProvider);
    final counts = ref.watch(workspaceProvider).speakerCounts(title, run);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? characters
        : characters.where((c) => c.name.toLowerCase().contains(q) || c.aliases.any((a) => a.toLowerCase().contains(q)) || c.appearance.toLowerCase().contains(q)).toList();
    final sorted = [...filtered]..sort((a, b) => (counts[b.name] ?? 0).compareTo(counts[a.name] ?? 0));
    final candidates = ref.watch(workspaceProvider).loadCandidates(title, run)
      ..sort((a, b) => (counts[b.name] ?? 0).compareTo(counts[a.name] ?? 0));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
          child: Row(
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  '台帳 ${characters.length} 名（仮名 ${characters.where((c) => c.isProvisional).length}）',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: TextField(
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '名前・別名・外見で検索',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      suffixIcon: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => _query = '')),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: '台帳を整理（consolidate）',
                icon: const Icon(Icons.merge_type, size: 20),
                onPressed: () => _consolidate(context, ref),
              ),
              IconButton(
                tooltip: '改名候補のレビュー',
                icon: const Icon(Icons.rule, size: 20),
                onPressed: () => context.push('/review/${Uri.encodeComponent(title)}/$run'),
              ),
              IconButton(
                tooltip: 'キャラを追加',
                icon: const Icon(Icons.person_add_alt, size: 20),
                onPressed: () => _editDialog(context, ref, characters, null),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: sorted.length + (candidates.isEmpty ? 0 : 1),
            itemBuilder: (context, i) {
              if (i == sorted.length) return _candidatesSection(context, candidates, counts);
              final c = sorted[i];
              return ListTile(
                dense: true,
                title: Row(children: [
                  Text(c.name, style: TextStyle(fontWeight: FontWeight.bold, color: c.isProvisional ? Colors.grey.shade700 : null)),
                  const SizedBox(width: 8),
                  Text('${counts[c.name] ?? 0} 件', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  if (c.displayAliases.isNotEmpty) ...[const SizedBox(width: 8), Text('別名: ${c.displayAliases.join(', ')}', style: const TextStyle(fontSize: 11, color: Colors.grey))],
                  if (c.mergedAliases.isNotEmpty) ...[const SizedBox(width: 8), Tooltip(message: '統合前の仮名: ${c.mergedAliases.join(', ')}', child: Text('統合 ${c.mergedAliases.length}', style: const TextStyle(fontSize: 11, color: Colors.grey)))],
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

  /// 台帳に昇格する前の仮名候補。1 ページしか登場していない人物なので既定で折りたたむ
  Widget _candidatesSection(BuildContext context, List<Candidate> candidates, Map<String, int> counts) {
    return ExpansionTile(
      dense: true,
      title: Text('候補 ${candidates.length} 名（まだ台帳に載せていない仮名。再登場すると自動で台帳に入ります）', style: const TextStyle(fontSize: 13, color: Colors.grey)),
      children: [
        for (final c in candidates)
          ListTile(
            dense: true,
            title: Row(children: [
              Text(c.name, style: const TextStyle(color: Colors.grey)),
              const SizedBox(width: 8),
              Text('${counts[c.name] ?? 0} 件 / ${c.pageCount} ページ', style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
            subtitle: Text(c.appearance, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Wrap(spacing: 4, children: [
              TextButton(onPressed: () => _promote(c), child: const Text('台帳に登録')),
              TextButton(onPressed: () => _renameCandidate(context, c), child: const Text('改名…')),
              IconButton(tooltip: '候補から削除（セリフの話者はそのまま）', icon: const Icon(Icons.close, size: 16), onPressed: () => _dropCandidate(c)),
            ]),
          ),
      ],
    );
  }

  void _promote(Candidate c) {
    final ws = ref.read(workspaceProvider);
    final book = [...ref.read(charactersProvider), Character(name: c.name, appearance: c.appearance)];
    ref.read(charactersProvider.notifier).save(title, run, book);
    ws.saveCandidates(title, run, ws.loadCandidates(title, run).where((x) => x.name != c.name).toList());
    setState(() {});
  }

  void _dropCandidate(Candidate c) {
    final ws = ref.read(workspaceProvider);
    ws.saveCandidates(title, run, ws.loadCandidates(title, run).where((x) => x.name != c.name).toList());
    setState(() {});
  }

  Future<void> _renameCandidate(BuildContext context, Candidate c) async {
    final name = TextEditingController(text: c.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('「${c.name}」を改名'),
        content: SizedBox(width: 380, child: TextField(controller: name, autofocus: true, decoration: const InputDecoration(labelText: '新しい名前（既存のキャラ名なら統合）'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('改名')),
        ],
      ),
    );
    final to = name.text.trim();
    if (ok != true || to.isEmpty || to == c.name || !context.mounted) return;
    await _rename(context, ref, c.name, to);
    setState(() {});
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
    await _rename(context, ref, from.name, target!);
  }

  Future<void> _editDialog(BuildContext context, WidgetRef ref, List<Character> all, Character? c) async {
    final counts = ref.read(workspaceProvider).speakerCounts(title, run);
    final name = TextEditingController(text: c?.name ?? '');
    final aliases = TextEditingController(text: c?.displayAliases.join(', ') ?? '');
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
              TextField(controller: name, decoration: const InputDecoration(labelText: '名前')),
              if (c != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('名前を変えると出力の話者（${counts[c.name] ?? 0} 件）も置き換わります。既存のキャラ名にすると、そのキャラに統合されます。', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                ),
              TextField(controller: aliases, decoration: const InputDecoration(labelText: '別名（カンマ区切り）')),
              if (c != null && c.mergedAliases.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('統合前の仮名（再登録を防ぐため保持）: ${c.mergedAliases.join(', ')}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ),
                ),
              TextField(controller: appearance, decoration: const InputDecoration(labelText: '外見'), maxLines: 3),
            ],
          ),
        ),
        actions: [
          if (c != null) TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('削除', style: TextStyle(color: Colors.red))),
          if (c != null) TextButton(onPressed: () => Navigator.pop(context, 'merge'), child: const Text('別のキャラに統合…')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('保存')),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    if (result == 'merge') {
      await _mergeDialog(context, ref, all, c!);
      return;
    }
    final list = [...all];
    if (result == 'delete') {
      list.remove(c);
      ref.read(charactersProvider.notifier).save(title, run, list);
      return;
    }
    final newName = name.text.trim();
    if (newName.isEmpty) return;
    final parsed = aliases.text.split(RegExp(r'[,、]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (c == null) {
      list.add(Character(name: newName, aliases: parsed, appearance: appearance.text.trim()));
      ref.read(charactersProvider.notifier).save(title, run, list);
      return;
    }
    // 名前以外を先に保存し、名前が変わっていればエンジンの rename で出力ごと置き換える
    c.aliases = [...parsed, ...c.mergedAliases];
    c.appearance = appearance.text.trim();
    ref.read(charactersProvider.notifier).save(title, run, list);
    if (newName != c.name) await _rename(context, ref, c.name, newName);
  }

  /// エンジンの rename を実行し、台帳と現在のページを再読込する
  Future<void> _rename(BuildContext context, WidgetRef ref, String from, String to) async {
    final events = await ref.read(engineServiceProvider).query(['rename', title, from, to, '--run', run]);
    if (!context.mounted) return;
    final err = events.where((e) => e.type == 'error').map((e) => e.data['message'] as String?).firstOrNull;
    final done = events.where((e) => e.type == 'done').map((e) => e.data).firstOrNull;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? '「$from」→「$to」（出力 ${done?['replaced']} 件を置換）')));
    ref.read(charactersProvider.notifier).load(title, run);
    final s = ref.read(pageEditorProvider);
    if (s != null) ref.read(pageEditorProvider.notifier).open(s.ref);
  }
}
