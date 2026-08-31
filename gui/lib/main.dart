import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setSize(const Size(1440, 900));
  await windowManager.setMinimumSize(const Size(1000, 640));
  runApp(const ProviderScope(child: MangaDialogueApp()));
}
