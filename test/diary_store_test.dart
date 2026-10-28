import 'package:flutter_test/flutter_test.dart';
import 'package:jangjak_diary/diary/diary_store.dart';

void main() {
  test('deleting the final interest stays empty after reopening', () async {
    String? saved;
    DiaryStore open() => DiaryStore(
      read: () async => saved,
      write: (value) async => saved = value,
    );
    await open().load();
    await open().save([]);
    expect(await open().load(), isEmpty);
  });

  test(
    'nine logs grow a new fire to level five without losing records',
    () async {
      final store = DiaryStore(read: () async => null, write: (_) async {});
      var interest = (await store.load())[1];
      for (var i = 0; i < 9; i++) {
        interest = interest.withEntry(
          DiaryEntry(text: '연습 $i', createdAt: DateTime.now()),
        );
      }
      expect(interest.level.index, 5);
      expect(interest.entries.length, 9);
    },
  );

  test(
    'loading stored entries preserves their interest and timestamp',
    () async {
      String? saved;
      DiaryStore openStore() => DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
      );
      final interests = [...await openStore().load()];
      interests[1] = interests[1].withEntry(
        DiaryEntry(
          text: '코드 세 개를 연습했어요.',
          createdAt: DateTime.utc(2026, 10, 26, 11, 30),
        ),
      );
      await openStore().save(interests);
      final restored = await openStore().load();
      expect(restored[1].title, '기타 치기');
      expect(restored[1].entries.single.text, '코드 세 개를 연습했어요.');
      expect(
        restored[1].entries.single.createdAt,
        DateTime.utc(2026, 10, 26, 11, 30),
      );
      expect(restored[0].entries, isEmpty);
      expect(restored[2].entries, isEmpty);
    },
  );

  test(
    'corrupt saved data is not silently replaced with sample data',
    () async {
      final store = DiaryStore(
        read: () async => '{broken json',
        write: (_) async => fail('Loading must not overwrite existing data'),
      );
      await expectLater(store.load(), throwsFormatException);
    },
  );

  test(
    'editing a record survives reopening without adding heat, logs or changing dates',
    () async {
      final firstAt = DateTime.utc(2026, 10, 1);
      final lastAt = firstAt.add(const Duration(hours: 1));
      final interest =
          Interest(id: 'guitar', title: '기타 치기', heatUpdatedAt: firstAt)
              .withEntry(DiaryEntry(text: '기타 주법이 신기햇다', createdAt: firstAt))
              .withEntry(DiaryEntry(text: '코드를 연습했다', createdAt: lastAt));
      final edited = interest.withEditedEntry(
        interest.entries.last,
        '기타 주법이 신기했다',
      );
      String? saved;
      final store = DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
      );
      await store.save([edited]);
      final restored = (await store.load()).single;
      expect(restored.entries.map((entry) => entry.text), [
        '코드를 연습했다',
        '기타 주법이 신기했다',
      ]);
      expect(restored.entries.map((entry) => entry.createdAt), [
        lastAt,
        firstAt,
      ]);
      expect(restored.level, interest.level);
      expect(restored.growthProgress, interest.growthProgress);
      expect(restored.heatUpdatedAt, lastAt);
      final later = lastAt.add(const Duration(days: 3));
      expect(restored.levelAt(later), interest.levelAt(later));
      expect(
        restored.logsUntilNextLevelAt(later),
        interest.logsUntilNextLevelAt(later),
      );
    },
  );

  test(
    'editing selects exactly one record even when text and dates are identical',
    () {
      final at = DateTime.utc(2026, 10, 1);
      final first = DiaryEntry(text: '똑같은 장작', createdAt: at);
      final second = DiaryEntry(text: '똑같은 장작', createdAt: at);
      final interest = Interest(
        id: 'books',
        title: '책 읽기',
        heatUpdatedAt: at,
        entries: [first, second],
      );
      final edited = interest.withEditedEntry(second, '두 번째 장작 수정');
      expect(edited.entries.map((entry) => entry.text), [
        '똑같은 장작',
        '두 번째 장작 수정',
      ]);
      expect(interest.entries.last.text, '똑같은 장작');
      expect(
        () => edited.withEditedEntry(second, '오래된 편집'),
        throwsFormatException,
      );
    },
  );

  test(
    'editing an archived record preserves the archive and its lifecycle',
    () {
      final at = DateTime.utc(2026, 10, 1);
      final interest = Interest(id: 'books', title: '책 읽기', heatUpdatedAt: at)
          .withEntry(DiaryEntry(text: '옛날 기럭', createdAt: at))
          .archive(
            at.add(const Duration(days: 1)),
            reason: ArchiveReason.achieved,
            note: '완독',
          );
      final edited = interest.withEditedEntry(interest.entries.single, '옛날 기록');
      expect(edited.isArchived, isTrue);
      expect(edited.events, same(interest.events));
      expect(edited.lastArchive!.note, '완독');
      expect(edited.heatUpdatedAt, interest.heatUpdatedAt);
      expect(edited.level, interest.level);
      expect(edited.growthProgress, interest.growthProgress);
    },
  );

  test(
    'blank and overlong edits are rejected without changing the original record',
    () {
      final at = DateTime.utc(2026, 10, 1);
      final interest = Interest(
        id: 'books',
        title: '책 읽기',
        heatUpdatedAt: at,
      ).withEntry(DiaryEntry(text: '원래 기록', createdAt: at));
      for (final text in [' \n ', 'a' * 2001]) {
        expect(
          () => interest.withEditedEntry(interest.entries.single, text),
          throwsFormatException,
        );
      }
      expect(interest.entries.single.text, '원래 기록');
    },
  );
}
