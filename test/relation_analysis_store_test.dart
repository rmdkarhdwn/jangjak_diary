import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jangjak_diary/diary/diary_store.dart';
import 'package:jangjak_diary/relationships/relation_api.dart';
import 'package:jangjak_diary/relationships/relation_analysis_store.dart';

http.Response response(String body, int status) => http.Response.bytes(
  utf8.encode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

class MemoryCache {
  String? data;
  bool fail = false;
  RelationAnalysisStore open() => RelationAnalysisStore(
    read: () async => data,
    write: (value) async {
      if (fail) throw StateError('disk full');
      data = value;
    },
  );
}

void main() {
  final now = DateTime.utc(2026, 10, 26, 12);
  Interest fire(
    String id,
    List<String> texts, {
    String? title,
    int level = 1,
  }) => Interest(
    id: id,
    title: title ?? id,
    level: FireLevel.values[level],
    heatUpdatedAt: now,
    entries: [
      for (var i = 0; i < texts.length; i++)
        DiaryEntry(
          text: texts[i],
          createdAt: now.subtract(Duration(minutes: i)),
        ),
    ],
  );
  final original = [
    fire('books', ['기타 주법을 읽었다']),
    fire('guitar', ['코드를 연습했다']),
  ];
  List<Interest> add(int count) => [
    Interest(
      id: 'books',
      title: 'books',
      heatUpdatedAt: now,
      entries: [
        for (var i = 0; i < count; i++)
          DiaryEntry(
            text: '새 장작 $i',
            createdAt: now.add(Duration(minutes: i + 1)),
          ),
        ...original.first.entries,
      ],
    ),
    original.last,
  ];
  final body = jsonEncode({
    'relations': [
      {
        'source': 'books',
        'target': 'guitar',
        'score': 0.66,
        'type': 'motivation',
        'summary': '직접 배우는 즐거움',
        'evidence': ['기타 주법을 읽었다', '코드를 연습했다'],
        'suggestion': '책 속 주법을 연습해보세요.',
      },
    ],
  });
  late MemoryCache memory;
  late RelationAnalysisStore cache;
  late RelationApi api;
  late int calls;
  setUp(() {
    memory = MemoryCache();
    cache = memory.open();
    calls = 0;
    api = RelationApi(
      baseUrl: 'http://test.local',
      client: MockClient((_) async {
        calls++;
        return response(body, 200);
      }),
    );
  });
  tearDown(() => api.close());

  test(
    'first analysis requires two nodes and one nonblank original log',
    () async {
      await cache.load();
      expect(cache.status([fire('a', [])], now).canUpdate, false);
      expect(
        cache.status([
          fire('a', [' ']),
          fire('b', []),
        ], now).canUpdate,
        false,
      );
      expect(
        cache.status([
          fire('a', ['원문']),
          fire('b', []),
        ], now).canUpdate,
        true,
      );
    },
  );

  test(
    'success survives restart, rebinds current fire state and never repeats unchanged input',
    () async {
      await cache.analyze(original, api, () => now);
      final reopened = memory.open();
      final fresh = [
        fire('books', ['기타 주법을 읽었다'], level: 4),
        original.last,
      ];
      final restored = await reopened.restore(fresh);
      expect(restored.connections.single.strength, 0.66);
      expect(identical(restored.connections.single.left, fresh.first), true);
      expect(reopened.status(fresh.reversed.toList(), now).canUpdate, false);
      await reopened.analyze(fresh, api, () => now);
      expect(calls, 1);
    },
  );

  test(
    'one or two new records are counted across interests; three unlock and success resets baseline',
    () async {
      await cache.analyze(original, api, () => now);
      for (var count = 1; count < 3; count++) {
        expect(cache.status(add(count), now).newRecords, count);
        expect(cache.status(add(count), now).canUpdate, false);
        await cache.analyze(add(count), api, () => now);
      }
      expect(calls, 1);
      final spread = [
        add(2).first,
        Interest(
          id: 'guitar',
          title: 'guitar',
          heatUpdatedAt: now,
          entries: [
            DiaryEntry(
              text: '다른 불에도 새 장작',
              createdAt: now.add(const Duration(hours: 1)),
            ),
            ...original.last.entries,
          ],
        ),
      ];
      expect(cache.status(spread, now).newRecords, 3);
      expect(cache.status(spread, now).canUpdate, true);
      await cache.analyze(spread, api, () => now);
      expect(calls, 2);
      expect(cache.status(spread, now).canUpdate, false);
      expect(cache.status(spread, now).newRecords, 0);
    },
  );

  test(
    'edited records and new candidates unlock update, while heat and archiving do not',
    () async {
      await cache.analyze(original, api, () => now);
      final edited = [
        fire('books', ['기타 주법을 읽었다. 수정']),
        original.last,
      ];
      expect(cache.status(edited, now).canUpdate, true);
      expect(cache.status(edited, now).newRecords, 0);
      expect(cache.status([...original, fire('new', [])], now).canUpdate, true);
      final archived = [
        original.first.archive(now, reason: ArchiveReason.resting),
        original.last,
      ];
      expect(cache.status(archived, now).canUpdate, false);
    },
  );

  test(
    'same-timestamp duplicates count additions without treating edits as added logs',
    () async {
      await cache.analyze(original, api, () => now);
      final duplicated = [
        Interest(
          id: 'books',
          title: 'books',
          heatUpdatedAt: now,
          entries: [
            ...original.first.entries,
            DiaryEntry(text: '다른 기록', createdAt: now),
          ],
        ),
        original.last,
      ];
      expect(cache.status(duplicated, now).newRecords, 1);
      final edited = [
        fire('books', ['수정된 기록']),
        original.last,
      ];
      expect(cache.status(edited, now).newRecords, 0);
      expect(cache.status(edited, now).canUpdate, true);
    },
  );

  test(
    'editing or deleting evidence removes only invalid cached edges and purges raw text from disk',
    () async {
      await cache.analyze(original, api, () => now);
      final edited = [
        fire('books', ['수정된 기록']),
        original.last,
      ];
      expect((await cache.restore(edited)).connections, isEmpty);
      expect(memory.data, isNot(contains('기타 주법을 읽었다')));
      expect(cache.hasResult, true);
      expect(cache.status(edited, now).canUpdate, true);
      expect((await cache.restore([original.last])).connections, isEmpty);
      expect(calls, 1);
      expect(cache.status(original, now).canUpdate, true);
    },
  );

  test(
    'a valid empty response persists and blocks reanalysis without new inputs',
    () async {
      final empty = RelationApi(
        baseUrl: 'http://test.local',
        client: MockClient((_) async {
          calls++;
          return response('{"relations":[]}', 200);
        }),
      );
      addTearDown(empty.close);
      await cache.analyze(original, empty, () => now);
      final reopened = memory.open();
      expect((await reopened.restore(original)).connections, isEmpty);
      expect(reopened.hasResult, true);
      await reopened.analyze(original, empty, () => now);
      expect(calls, 1);
    },
  );

  test(
    'failure retains previous graph and baseline and can be retried',
    () async {
      await cache.analyze(original, api, () => now);
      final failing = RelationApi(
        baseUrl: 'http://test.local',
        client: MockClient(
          (_) async => response(
            '{"error":{"code":"LLM_API_ERROR","message":"잠시 후 다시 시도"}}',
            502,
          ),
        ),
      );
      addTearDown(failing.close);
      await expectLater(
        cache.analyze(add(3), failing, () => now),
        throwsA(isA<RelationApiException>()),
      );
      expect(cache.cachedMap(add(3)).connections, hasLength(1));
      expect(cache.status(add(3), now).newRecords, 3);
      expect(cache.status(add(3), now).canUpdate, true);
      final reopened = memory.open();
      await reopened.load();
      expect(reopened.status(add(3), now).canUpdate, true);
      await reopened.analyze(add(3), api, () => now);
      expect(calls, 2);
    },
  );

  test(
    'five attempts including failures persist across restart; Korean midnight resets the quota',
    () async {
      final failing = RelationApi(
        baseUrl: 'http://test.local',
        client: MockClient((_) async {
          calls++;
          return response('{}', 502);
        }),
      );
      addTearDown(failing.close);
      for (var i = 0; i < 5; i++) {
        await expectLater(
          cache.analyze(original, failing, () => now),
          throwsA(isA<RelationApiException>()),
        );
      }
      cache = memory.open();
      await cache.load();
      expect(cache.status(original, now).canUpdate, false);
      await expectLater(
        cache.analyze(original, failing, () => now),
        throwsA(isA<RelationApiException>()),
      );
      expect(calls, 5);
      final midnight = DateTime.utc(2026, 10, 26, 15);
      expect(
        analysisDay(midnight.subtract(const Duration(seconds: 1))),
        '2026-10-26',
      );
      expect(analysisDay(midnight), '2026-10-27');
      expect(cache.status(original, midnight).canUpdate, true);
      await cache.analyze(original, api, () => midnight);
      expect(calls, 6);
    },
  );

  test('concurrent attempts reserve one call only', () async {
    final pending = Completer<http.Response>();
    final slow = RelationApi(
      baseUrl: 'http://test.local',
      client: MockClient((_) {
        calls++;
        return pending.future;
      }),
    );
    addTearDown(slow.close);
    final first = cache.analyze(original, slow, () => now);
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      cache.analyze(original, slow, () => now),
      throwsA(
        isA<RelationApiException>().having(
          (error) => error.code,
          'code',
          'IN_PROGRESS',
        ),
      ),
    );
    pending.complete(response(body, 200));
    await first;
    expect(calls, 1);
    expect(cache.status(original, now).remaining, 4);
  });

  test(
    'failed quota persistence prevents HTTP; failed response persistence keeps valid in-memory result',
    () async {
      memory.fail = true;
      await expectLater(
        cache.analyze(original, api, () => now),
        throwsA(isA<RelationApiException>()),
      );
      expect(calls, 0);
      memory.fail = false;
      final diskFailure = RelationApi(
        baseUrl: 'http://test.local',
        client: MockClient((_) async {
          calls++;
          memory.fail = true;
          return response(body, 200);
        }),
      );
      addTearDown(diskFailure.close);
      await expectLater(
        cache.analyze(original, diskFailure, () => now),
        throwsA(isA<RelationApiException>()),
      );
      expect(cache.cachedMap(original).connections, hasLength(1));
      expect(cache.status(original, now).canUpdate, false);
      await cache.analyze(original, diskFailure, () => now);
      expect(calls, 1);
      memory.fail = false;
      await cache.restore(original); // Save retry must not repeat the AI call.
      final reopened = memory.open();
      expect((await reopened.restore(original)).connections, hasLength(1));
      expect(reopened.status(original, now).canUpdate, false);
      expect(calls, 1);
    },
  );

  test(
    'an in-flight response cannot resurrect a node deleted while analysis was running',
    () async {
      final pending = Completer<http.Response>();
      final slow = RelationApi(
        baseUrl: 'http://test.local',
        client: MockClient((_) => pending.future),
      );
      addTearDown(slow.close);
      final first = cache.analyze(original, slow, () => now);
      await Future<void>.delayed(Duration.zero);
      await cache.restore([original.last]);
      pending.complete(response(body, 200));
      expect((await first).connections, isEmpty);
      expect(memory.data, isNot(contains('기타 주법을 읽었다')));
      expect(
        (await memory.open().restore([original.last])).connections,
        isEmpty,
      );
    },
  );

  test(
    'invalid persisted baseline reports a cache failure before use',
    () async {
      await cache.analyze(original, api, () => now);
      final value = jsonDecode(memory.data!) as Map;
      value['snapshot']['baseline'][0]['entries'] = 'corrupt';
      memory.data = jsonEncode(value);
      await expectLater(
        memory.open().load(),
        throwsA(
          isA<RelationApiException>().having(
            (error) => error.code,
            'code',
            'CACHE_READ_FAILED',
          ),
        ),
      );
      expect(calls, 1);
    },
  );
}
