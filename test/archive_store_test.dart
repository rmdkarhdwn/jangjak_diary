import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jangjak_diary/diary/diary_store.dart';
import 'package:jangjak_diary/relationships/relationship_data.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26, 12);
  final original = Interest(
    id: 'flutter',
    title: 'Flutter 공부',
    heatUpdatedAt: now,
    level: FireLevel.largeFire,
    entries: [DiaryEntry(text: '앱의 리듬을 표현했다.', createdAt: now)],
  );

  test(
    'archiving preserves identity, records and the reason for a transition',
    () {
      final archived = original.archive(
        now,
        reason: ArchiveReason.transitioned,
        note: '  앱 개발 자체로 넘어감  ',
      );
      expect(archived.id, 'flutter');
      expect(archived.entries.single.text, '앱의 리듬을 표현했다.');
      expect(archived.isArchived, isTrue);
      expect(archived.levelAt(now), FireLevel.ash);
      expect(archived.lastArchive!.reason, ArchiveReason.transitioned);
      expect(archived.lastArchive!.note, '앱 개발 자체로 넘어감');
      expect(
        () => archived.withEntry(DiaryEntry(text: '추가', createdAt: now)),
        throwsStateError,
      );
    },
  );

  test('rekindling keeps the full lifecycle and starts at a small ember', () {
    final withProgress = original.withEntry(
      DiaryEntry(text: '진행 중인 장작', createdAt: now),
    );
    final archived = withProgress.archive(now, reason: ArchiveReason.achieved);
    expect(archived.growthProgress, 1);
    final restored = archived.rekindle(now.add(const Duration(days: 10)));
    expect(restored.isArchived, isFalse);
    expect(
      restored.levelAt(now.add(const Duration(days: 10))),
      FireLevel.faintEmber,
    );
    expect(restored.entries.map((entry) => entry.createdAt), [now, now]);
    expect(restored.growthProgress, 0);
    expect(restored.logsUntilNextLevelAt(now.add(const Duration(days: 10))), 2);
    expect(restored.events.map((event) => event.kind), [
      FireEventKind.archived,
      FireEventKind.rekindled,
    ]);
    final archivedAgain = restored.archive(now.add(const Duration(days: 11)));
    expect(archivedAgain.events.length, 3);
    expect(archivedAgain.events.first.reason, ArchiveReason.achieved);
    expect(archivedAgain.archive(now).events.length, 3);
  });

  test(
    'reopening retains archive status, optional notes, and UTC event times',
    () async {
      String? saved;
      DiaryStore open() => DiaryStore(
        read: () async => saved,
        write: (value) async => saved = value,
      );
      await open().save([original.archive(now, note: '앱 만들기')]);
      final restored = (await open().load()).single;
      expect(restored.isArchived, isTrue);
      expect(restored.lastArchive!.note, '앱 만들기');
      expect(restored.lastArchive!.reason, isNull);
      expect(
        restored.lastArchive!.toJson()['occurredAt'],
        '2026-10-26T12:00:00.000Z',
      );
    },
  );

  test(
    'version two migrates as active without changing existing records',
    () async {
      final legacy = Map<String, Object>.of(original.toJson())
        ..remove('events')
        ..remove('growthProgress');
      String? saved = jsonEncode({
        'version': 2,
        'interests': [legacy],
      });
      var writes = 0;
      final store = DiaryStore(
        read: () async => saved,
        write: (value) async {
          saved = value;
          writes++;
        },
      );
      final restored = (await store.load()).single;
      expect(restored.isArchived, isFalse);
      expect(restored.events, isEmpty);
      expect(restored.entries.single.text, '앱의 리듬을 표현했다.');
      expect(jsonDecode(saved!)['version'], 4);
      await store.load();
      expect(writes, 1);
    },
  );

  test(
    'archived records still support relations; permanent deletion removes them',
    () {
      final archived = original.archive(
        now,
        reason: ArchiveReason.transitioned,
        note: '앱 개발로 이어짐',
      );
      final other = Interest(
        id: 'guitar',
        title: '기타 치기',
        heatUpdatedAt: now,
        entries: [DiaryEntry(text: '리듬과 박자로 표현했다.', createdAt: now)],
      );
      final analyzer = RecordRelationshipAnalyzer();
      expect(analyzer.analyze([archived, other]).connections, hasLength(1));
      expect(analyzer.analyze([other]).connections, isEmpty);
    },
  );
}
