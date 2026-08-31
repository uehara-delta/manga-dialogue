import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/engine_providers.dart';
import '../../state/providers.dart';

/// 保留中の改名候補のレビュー。一覧はエンジンの `pending list`、承認・却下は `pending approve/reject` に依頼する。
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.title, required this.run});
  final String title;
  final String run;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  List<Map<String, dynamic>> _items = [];
  bool _showAll = false;
  bool _loading = true;
  String? _error;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() { _loading = true; _error = null; });
    final events = await ref.read(engineServiceProvider).query(['pending', 'list', widget.title, '--run', widget.run, if (_showAll) '--all']);
    if (!mounted) return;
    setState(() {
      _items = [for (final e in events) if (e.type == 'pending') e.data];
      _error = events.where((e) => e.type == 'error').map((e) => e.data['message'] as String?).firstOrNull;
      _loading = false;
    });
  }

  Future<void> _set(String id, String action) async {
    setState(() => _busy.add(id));
    final events = await ref.read(engineServiceProvider).query(['pending', action, widget.title, id, '--run', widget.run]);
    if (!mounted) return;
    final err = events.where((e) => e.type == 'error').map((e) => e.data['message'] as String?).firstOrNull;
    final done = events.where((e) => e.type == 'done').map((e) => e.data).firstOrNull;
    _busy.remove(id);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    } else if (done != null && action == 'approve') {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('承認しました（出力 ${done['replaced']} 件を置換）')));
    }
    ref.read(charactersProvider.notifier).load(widget.title, widget.run);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.canPop() ? context.pop() : context.go('/')),
        title: Text('改名候補のレビュー  ${widget.title} (${widget.run})'),
        actions: [
          FilterChip(label: const Text('処理済みも表示'), selected: _showAll, onSelected: (v) { setState(() => _showAll = v); _reload(); }),
          const SizedBox(width: 8),
          IconButton(tooltip: '再読込', icon: const Icon(Icons.refresh), onPressed: _reload),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('読み込めません: $_error', style: TextStyle(color: scheme.error)))
              : _items.isEmpty
                  ? const Center(child: Text('保留中の候補はありません'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _PendingTile(
                        item: _items[i],
                        busy: _busy.contains(_items[i]['id']),
                        onApprove: () => _set(_items[i]['id'] as String, 'approve'),
                        onReject: () => _set(_items[i]['id'] as String, 'reject'),
                        onReopen: () => _set(_items[i]['id'] as String, 'reopen'),
                      ),
                    ),
    );
  }
}

class _PendingTile extends StatelessWidget {
  const _PendingTile({required this.item, required this.busy, required this.onApprove, required this.onReject, required this.onReopen});
  final Map<String, dynamic> item;
  final bool busy;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onReopen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = item['status'] as String;
    final applicable = item['applicable'] as bool? ?? true;
    final conf = (item['confidence'] as num).toDouble();
    final sources = (item['sources'] as List).cast<Map<String, dynamic>>();
    final pending = status == 'pending';
    return ExpansionTile(
      leading: Chip(
        label: Text(conf.toStringAsFixed(2)),
        backgroundColor: conf >= 0.7 ? scheme.primaryContainer : scheme.surfaceContainerHighest,
        padding: EdgeInsets.zero,
      ),
      title: Row(
        children: [
          Text(item['from_name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward, size: 16)),
          Text(item['to_name'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 12),
          if (!pending) Chip(label: Text(status == 'approved' ? '承認済み' : '却下'), visualDensity: VisualDensity.compact),
          if (pending && !applicable) const Chip(label: Text('台帳に元の名前なし（統合済み）'), visualDensity: VisualDensity.compact),
        ],
      ),
      subtitle: Text('${item['reason']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      trailing: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: pending
                  ? [
                      TextButton(onPressed: onReject, child: const Text('却下')),
                      const SizedBox(width: 4),
                      FilledButton(onPressed: onApprove, child: Text(applicable ? '承認して統合' : '承認（統合済み）')),
                    ]
                  : [TextButton(onPressed: onReopen, child: const Text('保留に戻す'))],
            ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('提案 ${sources.length} 件', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              for (final s in sources)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${s['volume']}巻 p${(s['page'] as num).toString().padLeft(3, '0')}  conf ${(s['confidence'] as num).toStringAsFixed(2)}\n${s['reason']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
