import 'package:flutter_test/flutter_test.dart';
import 'package:jangjak_diary/diary/diary_store.dart';
import 'package:jangjak_diary/relationships/relation_api.dart';

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
}
