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
}
