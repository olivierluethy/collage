import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'services/prefs_service.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Dark, edge-to-edge chrome to match the Darkroom theme.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF131110),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final prefs = await PrefsService.create();

  runApp(
    ProviderScope(
      overrides: [prefsProvider.overrideWithValue(prefs)],
      child: const CollageApp(),
    ),
  );
}
