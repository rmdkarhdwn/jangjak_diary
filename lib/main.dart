import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'diary/diary_store.dart';
import 'home/diary_home.dart';
import 'theme/diary_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final family in ['NotoSansKR', 'NotoSerifKR']) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$family-OFL.txt'));
    }
  });
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.store});

  final DiaryStore? store;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '장작일기',
    debugShowCheckedModeBanner: false,
    theme: DiaryTheme.data,
    home: DiaryHome(store: store ?? DiaryStore()),
  );
}
