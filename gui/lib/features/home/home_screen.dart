import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../../widgets/app_actions.dart';
import '../jobs/run_dialogs.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final works = ref.watch(worksProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('manga-dialogue'),
        actions: [
          IconButton(tooltip: '再読込', icon: const Icon(Icons.refresh), onPressed: () => ref.read(worksProvider.notifier).refresh()),
          const AppActions(),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(settings.worksRoot, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            subtitle: const Text('作品データの場所（works）'),
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
          const Divider(height: 1),
          Expanded(
            child: works.isEmpty
                ? const Center(child: Text('作品がありません。works フォルダを指定するか、キャプチャを実行してください。'))
                : ListView.separated(
                    itemCount: works.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final w = works[i];
                      return ListTile(
                        title: Text(w.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('巻: ${w.volumes.join(', ')}   run: ${w.runs.isEmpty ? '（未抽出）' : w.runs.join(', ')}'),
                        trailing: Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final run in w.runs)
                              ActionChip(
                                label: Text(run),
                                onPressed: () => context.go('/edit/${Uri.encodeComponent(w.title)}/$run/${w.volumes.isEmpty ? 1 : w.volumes.first}'),
                              ),
                            IconButton(
                              tooltip: '抽出を実行',
                              icon: const Icon(Icons.play_arrow_outlined),
                              onPressed: () async {
                                final job = await showExtractDialog(context, ref, title: w.title, volumes: w.volumes, runs: w.runs);
                                if (job != null && context.mounted) context.push('/jobs');
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
