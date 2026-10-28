import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jangjak_diary/diary/diary_store.dart';

void main() {
  final start = DateTime.utc(2026, 10, 1, 12);
  Interest fire(FireLevel level) => Interest(
    id: 'guitar',
    title: '기타 치기',
    level: level,
    heatUpdatedAt: start,
  );

  test('new interests need their first log to reach level one', () {
    final interest = Interest(id: 'new', title: '새 관심사', heatUpdatedAt: start);
    expect(interest.levelAt(start), FireLevel.ash);
    expect(
      interest.withEntry(DiaryEntry(text: '첫 장작', createdAt: start)).level,
      FireLevel.faintEmber,
    );
  });

  test('cumulative logs reach levels at 1, 3, 5, 7 and 9', () {
    var interest = fire(FireLevel.ash);
    const expectedLevels = [1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 5];
    for (var i = 0; i < expectedLevels.length; i++) {
      interest = interest.withEntry(
        DiaryEntry(text: '장작 ${i + 1}', createdAt: start),
      );
      expect(interest.level.index, expectedLevels[i], reason: '${i + 1} logs');
      expect(
        interest.logsUntilNextLevelAt(start),
        const [2, 1, 2, 1, 2, 1, 2, 1, 0, 0, 0][i],
      );
    }
  });

  test('cooling happens at each exact 72-hour boundary and stops at ashes', () {
    final interest = fire(FireLevel.blazing);
    expect(
      interest.levelAt(start.add(const Duration(hours: 71, minutes: 59))),
      FireLevel.blazing,
    );
    expect(
      interest.levelAt(start.add(const Duration(days: 3))),
      FireLevel.largeFire,
    );
    expect(
      interest.levelAt(start.add(const Duration(days: 6))),
      FireLevel.smallFire,
    );
    expect(
      interest.levelAt(start.add(const Duration(days: 15))),
      FireLevel.ash,
    );
    expect(
      interest.levelAt(start.add(const Duration(days: 120))),
      FireLevel.ash,
    );
    expect(
      interest.levelAt(start.subtract(const Duration(days: 1))),
      FireLevel.blazing,
    );
  });

  test('a log grows the cooled state and starts a fresh cooling interval', () {
    final now = start.add(const Duration(days: 10));
    var updated = fire(
      FireLevel.largeFire,
    ).withEntry(DiaryEntry(text: '다시 연습했어요', createdAt: now));
    expect(updated.level, FireLevel.faintEmber);
    expect(updated.logsUntilNextLevelAt(now), 1);
    updated = updated.withEntry(DiaryEntry(text: '한 번 더 연습', createdAt: now));
    expect(updated.level, FireLevel.revivedEmber);
    expect(
      updated.levelAt(now.add(const Duration(hours: 71))),
      FireLevel.revivedEmber,
    );
    expect(
      updated.levelAt(now.add(const Duration(days: 3))),
      FireLevel.faintEmber,
    );
  });

  test('cooling drops a level and clears unfinished growth progress', () {
    var interest = fire(FireLevel.ash);
    for (var i = 0; i < 4; i++) {
      interest = interest.withEntry(
        DiaryEntry(text: '장작 $i', createdAt: start),
      );
    }
    expect(interest.level, FireLevel.revivedEmber);
    expect(interest.logsUntilNextLevelAt(start), 1);
    final later = start.add(const Duration(days: 3));
    expect(interest.levelAt(later), FireLevel.faintEmber);
    expect(interest.logsUntilNextLevelAt(later), 2);
    final updated = interest.withEntry(
      DiaryEntry(text: '다시 쌓기', createdAt: later),
    );
    expect(updated.level, FireLevel.faintEmber);
    expect(updated.logsUntilNextLevelAt(later), 1);
    expect(updated.entries, hasLength(5));
  });

  test(
    'reopening halfway to a level preserves progress and the cooling clock',
    () async {
      String? saved;
      final store = DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
        now: () => start,
      );
      var interest = fire(FireLevel.ash);
      for (var i = 0; i < 2; i++) {
        interest = interest.withEntry(
          DiaryEntry(text: '장작 $i', createdAt: start),
        );
      }
      await store.save([interest]);
      final restored = (await store.load()).single;
      expect(jsonDecode(saved!)['version'], 4);
      expect(restored.heatUpdatedAt, start);
      expect(restored.level, FireLevel.faintEmber);
      expect(restored.logsUntilNextLevelAt(start), 1);
      expect(
        restored.withEntry(DiaryEntry(text: '세 번째 장작', createdAt: start)).level,
        FireLevel.revivedEmber,
      );
    },
  );

  test(
    'version-three migration preserves the snapshot, records and lifecycle once',
    () async {
      final old = fire(FireLevel.smallFire)
          .withEntry(DiaryEntry(text: '기존 기록', createdAt: start))
          .archive(start, reason: ArchiveReason.transitioned, note: '관심이 이어짐');
      final oldJson = Map<String, Object>.of(old.toJson())
        ..remove('growthProgress');
      String? saved = jsonEncode({
        'version': 3,
        'interests': [oldJson],
      });
      var writes = 0;
      final store = DiaryStore(
        read: () async => saved,
        write: (value) async {
          saved = value;
          writes++;
        },
        now: () => start,
      );
      final restored = (await store.load()).single;
      expect(restored.level, old.level);
      expect(restored.heatUpdatedAt, start);
      expect(restored.entries.single.text, '기존 기록');
      expect(restored.isArchived, isTrue);
      expect(restored.lastArchive!.reason, ArchiveReason.transitioned);
      expect(restored.lastArchive!.note, '관심이 이어짐');
      expect(restored.growthProgress, 0);
      expect(jsonDecode(saved!)['version'], 4);
      await store.load();
      expect(writes, 1);
    },
  );

  test('invalid saved growth progress is rejected', () {
    for (final progress in [-1, 2, 0.5, '1']) {
      final json = Map<String, Object>.of(fire(FireLevel.faintEmber).toJson())
        ..['growthProgress'] = progress;
      expect(() => Interest.fromJson(json, now: start), throwsFormatException);
    }
  });

  test(
    'ashes can be rekindled and adding logs at five never exceeds the cap',
    () {
      final revived = fire(
        FireLevel.ash,
      ).withEntry(DiaryEntry(text: '첫 장작', createdAt: start));
      expect(revived.level, FireLevel.faintEmber);
      final capped = fire(
        FireLevel.blazing,
      ).withEntry(DiaryEntry(text: '계속 연습', createdAt: start));
      expect(capped.level, FireLevel.blazing);
    },
  );

  test(
    'reopening preserves the first anchor rather than restarting the clock',
    () async {
      String? saved;
      var now = start;
      DiaryStore open() => DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
        now: () => now,
      );
      final initial = await open().load();
      initial[1] = fire(FireLevel.smallFire);
      await open().save(initial);
      now = start.add(const Duration(days: 9));
      final restored = await open().load();
      expect(restored[1].heatUpdatedAt, start);
      expect(restored[1].levelAt(now), FireLevel.ash);
    },
  );

  test(
    'version-one data migrates once while preserving notes and their dates',
    () async {
      String? saved = jsonEncode({
        'version': 1,
        'interests': [
          {
            'id': 'guitar',
            'title': '기타 치기',
            'level': 'steady',
            'entries': [
              {'text': '기존 장작', 'createdAt': '2026-10-01T12:00:00.000Z'},
            ],
          },
          {'id': 'books', 'title': '책 읽기', 'level': 'ember', 'entries': []},
        ],
      });
      var now = start.add(const Duration(days: 3));
      DiaryStore open() => DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
        now: () => now,
      );
      final migrated = await open().load();
      expect(migrated[0].entries.single.text, '기존 장작');
      expect(migrated[0].heatUpdatedAt, start);
      expect(migrated[0].levelAt(now), FireLevel.revivedEmber);
      expect(jsonDecode(saved!)['version'], 4);
      now = now.add(const Duration(days: 3));
      final reopened = await open().load();
      expect(reopened[1].heatUpdatedAt, start.add(const Duration(days: 3)));
      expect(reopened[1].levelAt(now), FireLevel.ash);
    },
  );

  test('saved activity timestamps use UTC across timezone changes', () {
    final local = DateTime(2026, 10, 1, 12);
    final interest = Interest(
      id: 'guitar',
      title: '기타 치기',
      heatUpdatedAt: local,
    ).withEntry(DiaryEntry(text: '기록', createdAt: local));
    expect(interest.toJson()['heatUpdatedAt'], endsWith('Z'));
    expect(interest.entries.single.toJson()['createdAt'], endsWith('Z'));
    final restored = Interest.fromJson(interest.toJson(), now: local);
    expect(restored.heatUpdatedAt.isAtSameMomentAs(local), isTrue);
  });
}
