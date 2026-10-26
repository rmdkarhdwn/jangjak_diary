import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jangjak_diary/main.dart';
import 'package:jangjak_diary/home/diary_sheets.dart';
import 'package:jangjak_diary/diary/diary_store.dart';

void main() {
  Future<DiaryStore> openDiary(WidgetTester tester, {DiaryStore? store}) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? saved;
    final repository =
        store ??
        DiaryStore(
          read: () async => saved,
          write: (value) async => saved = value,
        );
    await tester.pumpWidget(MyApp(store: repository));
    await tester.pumpAndSettle();
    return repository;
  }

  testWidgets('opens a form to create a new interest', (tester) async {
    await openDiary(tester);
    await tester.tap(find.byTooltip('새 불 만들기'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '사진 찍기');
    await tester.pump();
    await tester.tap(find.text('불 피우기'));
    await tester.pumpAndSettle();
    expect(find.text('사진 찍기'), findsOneWidget);
  });

  testWidgets('saves an entry under the current interest', (tester) async {
    await openDiary(tester);
    await tester.tap(find.text('장작 넣기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '오늘은 좋아하는 곡을 연습했어요.');
    await tester.pump();
    await tester.tap(find.text('마음 남기기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록 보기'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(EntryHistory),
        matching: find.text('오늘은 좋아하는 곡을 연습했어요.'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('swiping selects another interest', (tester) async {
    await openDiary(tester);
    await tester.drag(
      find.byKey(const Key('interest-carousel')),
      const Offset(-290, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('달리기'), findsOneWidget);
  });

  testWidgets('entries remain after restarting the app', (tester) async {
    final store = await openDiary(tester);
    await tester.tap(find.text('장작 넣기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '다시 들어와도 남아 있는 마음');
    await tester.pump();
    await tester.tap(find.text('마음 남기기'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('기록 보기'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(EntryHistory),
        matching: find.text('다시 들어와도 남아 있는 마음'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'failed saves keep the draft and allow retry without duplicates',
    (tester) async {
      String? saved;
      var shouldFail = false;
      await openDiary(
        tester,
        store: DiaryStore(
          read: () async => saved,
          write: (value) async {
            if (shouldFail) throw StateError('disk unavailable');
            saved = value;
          },
        ),
      );
      shouldFail = true;
      await tester.tap(find.text('장작 넣기'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '사라지면 안 되는 마음');
      await tester.pump();
      await tester.tap(find.text('마음 남기기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('저장하지 못했어요'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '사라지면 안 되는 마음',
      );
      shouldFail = false;
      await tester.tap(find.text('마음 남기기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기록 보기'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(EntryHistory),
          matching: find.text('사라지면 안 되는 마음'),
        ),
        findsOneWidget,
      );
      expect(find.text('1개의 장작'), findsOneWidget);
    },
  );

  testWidgets('the fire cools after resuming following three days away', (
    tester,
  ) async {
    var now = DateTime.utc(2026, 10, 1, 12);
    String? saved;
    await openDiary(
      tester,
      store: DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
        now: () => now,
      ),
    );
    expect(find.text('3단계 · 작은 불'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    now = now.add(const Duration(days: 3));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('2단계 · 살아난 불씨'), findsOneWidget);
  });

  testWidgets('resizing to a small screen preserves the current interest', (
    tester,
  ) async {
    await openDiary(tester);
    expect(find.text('기타 치기'), findsOneWidget);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    expect(find.text('기타 치기'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('장작 넣기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('장작 넣기'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
  });
}
