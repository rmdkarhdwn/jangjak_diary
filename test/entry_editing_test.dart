import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jangjak_diary/diary/diary_store.dart';
import 'package:jangjak_diary/home/archived_fire_sheet.dart';
import 'package:jangjak_diary/home/diary_sheets.dart';
import 'package:jangjak_diary/main.dart';

void main() {
  final at = DateTime.utc(2026, 10, 26, 12);
  Interest original() => Interest(
    id: 'guitar',
    title: '기타 치기',
    heatUpdatedAt: at,
  ).withEntry(DiaryEntry(text: '여러가지 주법이 신기햇다', createdAt: at));

  Future<void> open(WidgetTester tester, DiaryStore store) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MyApp(store: store));
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester) async {
    final button = find.byTooltip('장작 수정');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'editing prefills the record, updates history and survives restart',
    (tester) async {
      String? saved;
      final store = DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
        now: () => at,
      );
      await store.save([original()]);
      await open(tester, store);
      await tester.tap(find.text('기록 보기'));
      await tester.pumpAndSettle();
      await edit(tester);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '여러가지 주법이 신기햇다',
      );
      await tester.enterText(find.byType(TextField), '여러 가지 주법이 신기했다');
      await tester.pump();
      await tester.tap(find.text('수정 저장'));
      await tester.pumpAndSettle();
      expect(find.byType(DiaryComposer), findsNothing);
      expect(find.text('여러 가지 주법이 신기했다'), findsOneWidget);
      expect(find.text('1개의 장작'), findsOneWidget);
      final restored = (await store.load()).single;
      expect(restored.entries.single.createdAt, at);
      expect(restored.level, FireLevel.faintEmber);
      expect(restored.growthProgress, 0);
      expect(restored.heatUpdatedAt, at);
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, store);
      await tester.tap(find.text('기록 보기'));
      await tester.pumpAndSettle();
      expect(find.text('여러 가지 주법이 신기했다'), findsOneWidget);
    },
  );

  testWidgets(
    'blank edits cannot save and closing the editor cancels a draft',
    (tester) async {
      String? saved;
      var writes = 0;
      final store = DiaryStore(
        read: () async => saved,
        write: (value) async {
          saved = value;
          writes++;
        },
        now: () => at,
      );
      await store.save([original()]);
      await open(tester, store);
      await tester.tap(find.text('기록 보기'));
      await tester.pumpAndSettle();
      await edit(tester);
      await tester.enterText(find.byType(TextField), ' \n ');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '수정 저장'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '저장하지 않을 수정');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: find.byType(DiaryComposer),
          matching: find.byTooltip('닫기'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('여러가지 주법이 신기햇다'), findsOneWidget);
      expect((await store.load()).single.entries.single.text, '여러가지 주법이 신기햇다');
      expect(writes, 1);
    },
  );

  testWidgets(
    'failed edits retain the draft and original data, then retry once',
    (tester) async {
      String? saved;
      var fail = false;
      final store = DiaryStore(
        read: () async => saved,
        write: (value) async {
          if (fail) throw StateError('disk unavailable');
          saved = value;
        },
        now: () => at,
      );
      await store.save([original()]);
      await open(tester, store);
      await tester.tap(find.text('기록 보기'));
      await tester.pumpAndSettle();
      await edit(tester);
      await tester.enterText(find.byType(TextField), '고쳐 쓴 기록');
      await tester.pump();
      fail = true;
      await tester.tap(find.text('수정 저장'));
      await tester.pumpAndSettle();
      expect(find.textContaining('저장하지 못했어요'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '고쳐 쓴 기록',
      );
      expect((await store.load()).single.entries.single.text, '여러가지 주법이 신기햇다');
      fail = false;
      await tester.tap(find.text('수정 저장'));
      await tester.pumpAndSettle();
      expect(find.text('고쳐 쓴 기록'), findsOneWidget);
      expect(find.text('1개의 장작'), findsOneWidget);
      expect((await store.load()).single.entries.single.text, '고쳐 쓴 기록');
    },
  );

  testWidgets(
    'archived edits remain archived and refresh the category copy when reopened',
    (tester) async {
      String? saved;
      final store = DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
        now: () => at,
      );
      await store.save([
        original().archive(at, reason: ArchiveReason.achieved),
      ]);
      await open(tester, store);
      await tester.tap(find.text('전체 분류 보기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('보관한 불'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('기타 치기'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('장작 수정'), findsOneWidget);
      await edit(tester);
      await tester.enterText(find.byType(TextField), '보관한 기록의 오타 수정');
      await tester.pump();
      await tester.tap(find.text('수정 저장'));
      await tester.pumpAndSettle();
      expect(find.text('보관한 기록의 오타 수정'), findsOneWidget);
      final restored = (await store.load()).single;
      expect(restored.isArchived, isTrue);
      expect(restored.events, hasLength(1));
      expect(restored.lastArchive!.reason, ArchiveReason.achieved);
      expect(restored.entries.single.createdAt, at);
      await tester.tap(
        find.descendant(
          of: find.byType(ArchivedFireSheet),
          matching: find.byTooltip('닫기'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('기타 치기'));
      await tester.pumpAndSettle();
      expect(find.text('보관한 기록의 오타 수정'), findsOneWidget);
      expect(find.text('다시 불붙이기'), findsOneWidget);
    },
  );
}
