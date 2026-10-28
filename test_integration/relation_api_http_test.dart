import 'package:flutter_test/flutter_test.dart';
import 'package:jangjak_diary/diary/diary_store.dart';
import 'package:jangjak_diary/relationships/relation_api.dart';
import 'package:jangjak_diary/relationships/relation_analysis_store.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26);
  List<Interest> input(String title) => [
    Interest(
      id: 'flutter',
      title: title,
      heatUpdatedAt: now,
      entries: [DiaryEntry(text: '직접 앱 만드는 게 재밌다', createdAt: now)],
    ),
    Interest(
      id: 'game',
      title: '게임 개발',
      heatUpdatedAt: now,
      entries: [DiaryEntry(text: '시스템 만드는 게 재밌다', createdAt: now)],
    ),
  ];
  late RelationApi api;
  setUp(
    () => api = RelationApi(
      baseUrl: const String.fromEnvironment(
        'AI_SIMULATION_BASE_URL',
        defaultValue: 'http://127.0.0.1:3001',
      ),
    ),
  );
  tearDown(() => api.close());

  test(
    'Flutter HTTP client → real Fastify → real SDK → Postman fixture',
    () async {
      final map = await api.analyze(input('Flutter'));
      expect(map.connections.single.strength, 0.66);
      expect(map.connections.single.left.id, 'flutter');
      expect(
        map.connections.single.explanation,
        '직접 만들어 결과물을 확인하는 즐거움이 공통됩니다.',
      );
      expect(map.connections.single.suggestion, 'Flutter로 작은 게임 도구를 만들어보세요.');
      expect(map.connections.single.evidence, hasLength(2));
    },
  );
  test('real server errors propagate instead of becoming empty maps', () async {
    for (final fixture in {
      '__upstream_failure__': 'LLM_API_ERROR',
      '__invalid_json__': 'INVALID_LLM_RESPONSE',
    }.entries) {
      await expectLater(
        api.analyze(input(fixture.key)),
        throwsA(
          isA<RelationApiException>().having(
            (error) => error.code,
            'code',
            fixture.value,
          ),
        ),
      );
    }
  });
  test('a legitimate empty server response stays empty', () async {
    final map = await api.analyze(input('Flutter').take(1).toList());
    expect(map.connections, isEmpty);
  });
  test(
    'a recordless target connects through source-only topic evidence over actual HTTP',
    () async {
      const text = '오늘 기타를 치는 책을 읽었다. 여러가지 주법이 있는게 신기했다.';
      final map = await api.analyze([
        Interest(
          id: 'books',
          title: '책 읽기',
          heatUpdatedAt: now,
          entries: [DiaryEntry(text: text, createdAt: now)],
        ),
        Interest(id: 'guitar', title: '기타 치기', heatUpdatedAt: now),
      ]);
      final edge = map.connections.single;
      expect(edge.strength, 0.95);
      expect(edge.right.id, 'guitar');
      expect(edge.evidence.single.interest.id, 'books');
      expect(edge.evidence.single.entry.text, text);
    },
  );

  test(
    'persistent cache gates real HTTP until three new records and restores the last valid graph after upstream failure',
    () async {
      String? saved;
      RelationAnalysisStore open() => RelationAnalysisStore(
        read: () async => saved,
        write: (value) async => saved = value,
      );
      var cache = open();
      final original = input('Flutter');
      await cache.analyze(original, api, () => now);
      cache = open();
      expect((await cache.restore(original)).connections.single.strength, 0.66);
      final afterFirst = saved;
      await cache.analyze(original, api, () => now);
      expect(saved, afterFirst); // No attempt reserved and no HTTP.
      List<Interest> withNew(int count) => [
        Interest(
          id: 'flutter',
          title: 'Flutter',
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
      await cache.analyze(withNew(2), api, () => now);
      expect(saved, afterFirst);
      expect(cache.status(withNew(3), now).canUpdate, true);
      await cache.analyze(withNew(3), api, () => now);
      expect(cache.status(withNew(3), now).canUpdate, false);
      final failed = input('__upstream_failure__');
      await expectLater(
        cache.analyze(failed, api, () => now),
        throwsA(
          isA<RelationApiException>().having(
            (error) => error.code,
            'code',
            'LLM_API_ERROR',
          ),
        ),
      );
      expect(cache.cachedMap(failed).connections.single.strength, 0.66);
      final restored = open();
      expect((await restored.restore(failed)).connections, hasLength(1));
      expect(restored.status(failed, now).canUpdate, true);
    },
  );
}
