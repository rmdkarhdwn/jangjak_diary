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
    final updated = fire(
      FireLevel.largeFire,
    ).withEntry(DiaryEntry(text: '다시 연습했어요', createdAt: now));
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
      await open().load();
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
      expect(jsonDecode(saved!)['version'], 3);
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
