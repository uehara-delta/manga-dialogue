import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/engine_providers.dart';
import '../../state/providers.dart';
import '../../widgets/app_actions.dart';
import '../../workspace/workspace.dart';
import '../capture/capture_dialog.dart';
import 'work_detail.dart';

/// トップ画面。左に作品一覧、右に選んだ作品の巻ごとの状況と操作。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String? _selectedTitle;

  @override
  Widget build(BuildContext context) {
    // ジョブが終わったら（実行中の件数が減ったら）作品一覧を再走査する
    ref.listen(runningJobCountProvider, (prev, next) {
      if (next < (prev ?? 0)) ref.read(worksProvider.notifier).refresh();
    });
    final settings = ref.watch(settingsProvider);
    final works = ref.watch(worksProvider);
    final selected = works.where((w) => w.title == _selectedTitle).firstOrNull ?? works.firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('manga-dialogue'),
        actions: [
          IconButton(tooltip: '再読込', icon: const Icon(Icons.refresh), onPressed: () => ref.read(worksProvider.notifier).refresh()),
          const AppActions(),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add_a_photo_outlined),
                    label: const Text('新しい作品をキャプチャ'),
                    onPressed: () async {
                      final job = await showCaptureDialog(context, ref);
                      if (job != null && context.mounted) await context.push('/jobs');
                      ref.read(worksProvider.notifier).refresh();
                    },
                  ),
                ),
                Expanded(
                  child: works.isEmpty
                      ? const Padding(padding: EdgeInsets.all(16), child: Text('作品がありません。Kindle で本を開いて「新しい作品をキャプチャ」から始めてください。', style: TextStyle(color: Colors.grey)))
                      : ListView.builder(
                          itemCount: works.length,
                          itemBuilder: (context, i) {
                            final w = works[i];
                            return ListTile(
                              selected: w.title == selected?.title,
                              title: Text(w.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${w.volumes.length} 巻${w.runs.isEmpty ? '（未抽出）' : ''}'),
                              onTap: () => setState(() => _selectedTitle = w.title),
                            );
                          },
                        ),
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined, size: 18),
                  title: Text(settings.worksRoot, style: const TextStyle(fontFamily: 'monospace', fontSize: 11), overflow: TextOverflow.ellipsis),
                  trailing: TextButton(
                    child: const Text('変更'),
                    onPressed: () async {
                      final dir = await FilePicker.getDirectoryPath(dialogTitle: 'works フォルダを選択');
                      if (dir != null) {
                        ref.read(settingsProvider.notifier).update((s) => s.worksRoot = dir);
                        ref.read(worksProvider.notifier).refresh();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: selected == null
                ? const Center(child: Text('作品を選ぶと、巻ごとの状況と操作がここに表示されます', style: TextStyle(color: Colors.grey)))
                : WorkDetail(key: ValueKey(selected.title), work: selected),
          ),
        ],
      ),
    );
  }
}

extension on Iterable<WorkSummary> {
  WorkSummary? get firstOrNull => isEmpty ? null : first;
}
