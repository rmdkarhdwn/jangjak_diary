import 'package:flutter/gestures.dart';
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

  testWidgets('opens the relationship map from the left of the plus button', (
    tester,
  ) async {
    await openDiary(tester);
    expect(
      tester.getCenter(find.text('관계')).dx,
      lessThan(tester.getCenter(find.byTooltip('새 불 만들기')).dx),
    );
    await tester.tap(find.text('관계'));
    await tester.pumpAndSettle();
    expect(find.text('관계도'), findsOneWidget);
    expect(find.text('내 관심사'), findsOneWidget);
    expect(find.text('예시 관계도'), findsOneWidget);
    await tester.tap(find.byTooltip('내 불로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.text('기타 치기'), findsOneWidget);
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

  testWidgets(
    'scrolling down opens a separate category page including empty interests',
    (tester) async {
      String? saved;
      final store = DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
      );
      final interests = [...await store.load()];
      interests[0] = interests[0].withEntry(
        DiaryEntry(text: '책에서 마음에 드는 문장을 찾았어요.', createdAt: DateTime.now()),
      );
      await store.save(interests);
      await openDiary(tester, store: store);
      await tester.drag(
        find.byKey(const Key('interest-carousel')),
        const Offset(0, -420),
      );
      await tester.pumpAndSettle();
      expect(find.text('전체 분류'), findsOneWidget);
      expect(find.text('책 읽기'), findsOneWidget);
      expect(find.text('달리기'), findsOneWidget);
      expect(find.byKey(const Key('interest-carousel')), findsNothing);
      await tester.tap(find.text('책 읽기'));
      await tester.pumpAndSettle();
      expect(find.text('전체 분류'), findsNothing);
      expect(find.text('책 읽기'), findsOneWidget);
      expect(find.byType(EntryHistory), findsNothing);
      await tester.tap(find.text('기록 보기'));
      await tester.pumpAndSettle();
      expect(find.text('책 읽기의 기록'), findsOneWidget);
      expect(find.text('책에서 마음에 드는 문장을 찾았어요.'), findsOneWidget);
    },
  );

  testWidgets('the category page has a way back to the same selected fire', (
    tester,
  ) async {
    await openDiary(tester);
    await tester.drag(
      find.byKey(const Key('interest-carousel')),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    expect(find.text('전체 분류'), findsOneWidget);
    await tester.tap(find.byTooltip('내 불로 돌아가기'));
    await tester.pumpAndSettle();
    expect(find.text('기타 치기'), findsOneWidget);
    expect(find.byKey(const Key('interest-carousel')), findsOneWidget);
  });

  testWidgets(
    'pulling down from the top of categories returns to the same fire',
    (tester) async {
      await openDiary(tester);
      await tester.tap(find.text('전체 분류 보기'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('전체 분류'), const Offset(0, 20));
      await tester.pumpAndSettle();
      expect(find.text('전체 분류'), findsOneWidget);
      await tester.drag(find.text('전체 분류'), const Offset(150, 10));
      await tester.pumpAndSettle();
      expect(find.text('전체 분류'), findsOneWidget);
      await tester.drag(find.text('전체 분류'), const Offset(0, 180));
      await tester.pumpAndSettle();
      expect(find.text('전체 분류'), findsNothing);
      expect(find.text('기타 치기'), findsOneWidget);
      expect(find.byKey(const Key('interest-carousel')), findsOneWidget);
    },
  );

  testWidgets('scrolling upward at the category top returns to the fire', (
    tester,
  ) async {
    await openDiary(tester);
    await tester.tap(find.text('전체 분류 보기'));
    await tester.pumpAndSettle();
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(find.text('전체 분류')),
        scrollDelta: const Offset(0, -80),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('전체 분류'), findsNothing);
    expect(find.text('기타 치기'), findsOneWidget);
  });

  testWidgets(
    'scrolling a long category list back to its top does not dismiss it',
    (tester) async {
      String? saved;
      final store = DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
      );
      await store.save([
        for (var i = 0; i < 15; i++)
          Interest(
            id: 'interest-$i',
            title: '관심사 $i',
            heatUpdatedAt: DateTime.now(),
          ),
      ]);
      await openDiary(tester, store: store);
      await tester.tap(find.text('전체 분류 보기'));
      await tester.pumpAndSettle();
      final page = find.byKey(const Key('category-page'));
      await tester.drag(page, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.drag(page, const Offset(0, 250));
      await tester.pumpAndSettle();
      expect(page, findsOneWidget);
      await tester.drag(page, const Offset(0, 3000));
      await tester.pumpAndSettle();
      expect(page, findsOneWidget);
      expect(find.text('전체 분류').hitTestable(), findsOneWidget);
      await tester.drag(find.text('전체 분류'), const Offset(0, 160));
      await tester.pumpAndSettle();
      expect(page, findsNothing);
      expect(find.text('관심사 1'), findsOneWidget);
    },
  );

  testWidgets(
    'wheel scrolling opens one category page without changing fires',
    (tester) async {
      await openDiary(tester);
      final position = tester.getCenter(
        find.byKey(const Key('interest-carousel')),
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: position,
          scrollDelta: const Offset(40, 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('전체 분류'), findsNothing);
      for (var i = 0; i < 2; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: position,
            scrollDelta: const Offset(0, 80),
          ),
        );
      }
      await tester.pumpAndSettle();
      expect(find.text('전체 분류'), findsOneWidget);
      await tester.tap(find.byTooltip('내 불로 돌아가기'));
      await tester.pumpAndSettle();
      expect(find.text('기타 치기'), findsOneWidget);
      expect(find.text('전체 분류'), findsNothing);
    },
  );

  testWidgets('a long category grid scrolls and selects a distant fire', (
    tester,
  ) async {
    String? saved;
    final store = DiaryStore(
      read: () async => saved,
      write: (value) async => saved = value,
    );
    await store.save([
      for (var i = 0; i < 15; i++)
        Interest(
          id: 'interest-$i',
          title: '관심사 $i',
          heatUpdatedAt: DateTime.now(),
        ),
    ]);
    await openDiary(tester, store: store);
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    await tester.tap(find.text('전체 분류 보기'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('관심사 14'),
      350,
      scrollable: find.descendant(
        of: find.byKey(const Key('category-page')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('관심사 14'));
    await tester.pumpAndSettle();
    expect(find.text('관심사 14'), findsOneWidget);
    expect(find.text('전체 분류'), findsNothing);
  });

  testWidgets('a category can be created from the overview and reopened', (
    tester,
  ) async {
    await openDiary(tester);
    await tester.tap(find.text('전체 분류 보기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('새 불 피우기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '그림 그리기');
    await tester.pump();
    await tester.tap(find.text('불 피우기'));
    await tester.pumpAndSettle();
    expect(find.text('그림 그리기'), findsOneWidget);
    await tester.tap(find.text('전체 분류 보기'));
    await tester.pumpAndSettle();
    expect(find.text('그림 그리기'), findsOneWidget);
    expect(find.text('4개의 불'), findsOneWidget);
  });
}
