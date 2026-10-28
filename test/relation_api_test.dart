import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jangjak_diary/diary/diary_store.dart';
import 'package:jangjak_diary/relationships/relation_api.dart';
import 'package:jangjak_diary/relationships/relationship_data.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26);
  Interest fire(String id, List<String> logs) => Interest(
    id: id,
    title: id,
    heatUpdatedAt: now,
    entries: [for (final text in logs) DiaryEntry(text: text, createdAt: now)],
  );
  final interests = [
    fire('real-id-123', ['  직접 앱 만드는 게 재밌다\n']),
    fire('game', ['시스템 만드는 게 재밌다']),
  ];
  Map<String, Object> relation() => {
    'source': 'real-id-123',
    'target': 'game',
    'score': 0.6601,
    'type': 'motivation',
    'summary': '직접 만드는 즐거움이 공통됩니다.',
    'evidence': interests.map((item) => item.entries.first.text).toList(),
    'suggestion': 'Flutter로 작은 게임 도구를 만들어보세요.',
  };
  RelationApi api(Object body, {int status = 200}) => RelationApi(
    baseUrl: 'http://localhost:3000',
    client: MockClient(
      (_) async => http.Response(
        jsonEncode(body),
        status,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      ),
    ),
  );

  test(
    'sends actual IDs and original nonblank log text with UTF-8 JSON',
    () async {
      final service = RelationApi(
        baseUrl: 'http://localhost:3000/prefix/',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(
            request.url.toString(),
            'http://localhost:3000/prefix/analyze-relations',
          );
          expect(request.headers['content-type'], contains('application/json'));
          final items = (jsonDecode(request.body) as Map)['interests'] as List;
          expect(items, [
            {
              'id': 'real-id-123',
              'title': 'real-id-123',
              'logs': ['  직접 앱 만드는 게 재밌다\n'],
            },
            {
              'id': 'game',
              'title': 'game',
              'logs': ['시스템 만드는 게 재밌다'],
            },
          ]);
          return http.Response('{"relations":[]}', 200);
        }),
      );
      expect(service.timeout, const Duration(seconds: 55));
      final map = await service.analyze([
        ...interests,
        fire('empty', ['', ' \n ']),
      ]);
      expect(map.interests, hasLength(3));
      expect(map.connections, isEmpty);
    },
  );

  test(
    'preserves server score, type, explanation, evidence and suggestion',
    () async {
      final map = await api({
        'relations': [relation()],
      }).analyze(interests);
      final edge = map.connections.single;
      expect(edge.left.id, 'real-id-123');
      expect(edge.right.id, 'game');
      expect(edge.strength, 0.6601);
      expect(edge.type, RelationType.motivation);
      expect(edge.explanation, relation()['summary']);
      expect(edge.suggestion, relation()['suggestion']);
      expect(
        edge.evidence.map((item) => item.entry.text),
        relation()['evidence'],
      );
      expect(map.candidates, isEmpty);
    },
  );

  test(
    'sends recordless identities as candidates and maps one-sided topic evidence to its owner',
    () async {
      const text = '오늘 기타를 치는 책을 읽었다. 여러가지 주법이 있는게 신기했다.';
      final input = [
        fire('books', [text]),
        fire('guitar', []),
      ];
      final service = RelationApi(
        baseUrl: 'http://localhost:3000',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          expect(body['candidateInterests'], [
            {'id': 'guitar', 'title': 'guitar'},
          ]);
          expect((body['interests'] as List).length, 1);
          return http.Response(
            jsonEncode({
              'relations': [
                {
                  'source': 'books',
                  'target': 'guitar',
                  'score': 0.95,
                  'type': 'topic',
                  'basis': 'explicit_reference',
                  'summary': '책에서 기타 주법을 직접 다뤘어요.',
                  'evidence': [text],
                  'suggestion': '기타 주법 하나를 연습해보세요.',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final edge = (await service.analyze(input)).connections.single;
      expect(edge.left.id, 'books');
      expect(edge.right.id, 'guitar');
      expect(edge.basis, RelationBasis.explicitReference);
      expect(edge.strength, 0.95);
      expect(edge.evidence.single.interest.id, 'books');
      expect(edge.evidence.single.entry.text, text);
    },
  );

  test(
    'one-sided evidence cannot masquerade as shared motivation or use a fabricated quote',
    () async {
      final input = [interests.first, fire('game', [])];
      final valid = {
        ...relation(),
        'type': 'topic',
        'basis': 'explicit_reference',
        'evidence': [interests.first.entries.single.text],
      };
      for (final invalid in [
        {...valid, 'basis': 'shared_logs'},
        {...valid, 'basis': 'unknown'},
        {...valid, 'type': 'motivation'},
        {...valid, 'source': 'game', 'target': 'real-id-123'},
        {
          ...valid,
          'evidence': ['없는 기록'],
        },
        {...valid, 'target': 'unregistered'},
      ]) {
        await expectLater(
          api({
            'relations': [invalid],
          }).analyze(input),
          throwsA(
            isA<RelationApiException>().having(
              (e) => e.code,
              'code',
              'INVALID_RESPONSE',
            ),
          ),
        );
      }
      final both = (await api({
        'relations': [valid],
      }).analyze(interests)).connections.single;
      expect(both.evidence.single.interest.id, 'real-id-123');
    },
  );

  test(
    'does not filter low server scores or create absent connections',
    () async {
      final map = await api({
        'relations': [
          {...relation(), 'score': 0.1, 'type': 'transition'},
        ],
      }).analyze(interests);
      expect(map.connections.single.strength, 0.1);
      expect(map.connections.single.label, 'real-id-123 → game');
      final empty = await api({'relations': []}).analyze(interests);
      expect(empty.connections, isEmpty);
      expect(empty.candidates, isEmpty);
    },
  );

  test(
    'never submits duplicate IDs, empty logs, or silently truncated text',
    () async {
      var calls = 0;
      final service = RelationApi(
        baseUrl: 'http://localhost:3000',
        client: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      for (final input in [
        [interests.first, interests.first],
        [
          fire('blank', [' \n ']),
        ],
        [
          fire('long', ['a' * 2001]),
        ],
        [
          for (var i = 0; i < 13; i++) fire('$i', ['기록']),
        ],
      ]) {
        await expectLater(
          service.analyze(input),
          throwsA(isA<RelationApiException>()),
        );
      }
      expect(calls, 0);
      final payload = RelationApi.buildRequest([
        fire('many', [for (var i = 0; i < 35; i++) '원문 $i']),
      ]);
      final logs =
          ((payload['interests'] as List).single as Map)['logs'] as List;
      expect(logs, hasLength(30));
      expect(logs.first, '원문 0');
      expect(logs.last, '원문 29');
    },
  );

  test(
    'rejects invalid identities, scores, fields, evidence and duplicate pairs',
    () async {
      for (final invalid in [
        {...relation(), 'source': 'unknown'},
        {...relation(), 'target': 'real-id-123'},
        {...relation(), 'score': 1.1},
        {...relation(), 'score': '0.66'},
        {...relation(), 'type': 'invented'},
        {...relation(), 'summary': ''},
        {...relation()}..remove('suggestion'),
        {
          ...relation(),
          'evidence': ['invented', '시스템 만드는 게 재밌다'],
        },
        {
          ...relation(),
          'evidence': ['시스템 만드는 게 재밌다', '시스템 만드는 게 재밌다'],
        },
      ]) {
        await expectLater(
          api({
            'relations': [invalid],
          }).analyze(interests),
          throwsA(
            isA<RelationApiException>().having(
              (error) => error.code,
              'code',
              'INVALID_RESPONSE',
            ),
          ),
        );
      }
      await expectLater(
        api({
          'relations': [
            relation(),
            {...relation(), 'source': 'game', 'target': 'real-id-123'},
          ],
        }).analyze(interests),
        throwsA(isA<RelationApiException>()),
      );
      for (final body in [
        {},
        {
          'error': {'code': 'WRONG', 'message': '오류'},
        },
        {'relations': null},
      ]) {
        await expectLater(
          api(body).analyze(interests),
          throwsA(isA<RelationApiException>()),
        );
      }
    },
  );

  test(
    'surfaces structured errors and never converts HTTP failures to empty results',
    () async {
      for (final code in [
        'INVALID_LLM_RESPONSE',
        'LLM_NOT_CONFIGURED',
        'LLM_RATE_LIMITED',
        'LLM_TIMEOUT',
      ]) {
        await expectLater(
          api({
            'error': {'code': code, 'message': '서버에서 분석하지 못했어요.'},
          }, status: 502).analyze(interests),
          throwsA(
            isA<RelationApiException>().having(
              (error) => error.code,
              'code',
              code,
            ),
          ),
        );
      }
      await expectLater(
        api({'relations': []}, status: 500).analyze(interests),
        throwsA(isA<RelationApiException>()),
      );
      for (final status in [200, 502]) {
        final service = RelationApi(
          baseUrl: 'http://localhost:3000',
          client: MockClient(
            (_) async => http.Response('<html>bad gateway</html>', status),
          ),
        );
        await expectLater(
          service.analyze(interests),
          throwsA(isA<RelationApiException>()),
        );
      }
    },
  );

  test(
    'prevents concurrent requests and permits retry after timeout',
    () async {
      var calls = 0;
      final service = RelationApi(
        baseUrl: 'http://localhost:3000',
        timeout: const Duration(milliseconds: 20),
        client: MockClient((_) async {
          calls++;
          if (calls == 1) await Completer<void>().future;
          return http.Response('{"relations":[]}', 200);
        }),
      );
      final first = service.analyze(interests);
      await expectLater(
        service.analyze(interests),
        throwsA(
          isA<RelationApiException>().having(
            (e) => e.code,
            'code',
            'IN_PROGRESS',
          ),
        ),
      );
      await expectLater(
        first,
        throwsA(
          isA<RelationApiException>().having(
            (e) => e.code,
            'code',
            'CLIENT_TIMEOUT',
          ),
        ),
      );
      expect((await service.analyze(interests)).connections, isEmpty);
      expect(calls, 2);
    },
  );

  test('reports unreachable server and missing base URL as errors', () async {
    final service = RelationApi(
      baseUrl: 'http://localhost:3000',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      service.analyze(interests),
      throwsA(
        isA<RelationApiException>().having((e) => e.code, 'code', 'NETWORK'),
      ),
    );
    for (final url in [
      '',
      'http://0.0.0.0:3000',
      'file:///tmp',
      'http://user:password@localhost',
    ]) {
      await expectLater(
        RelationApi(baseUrl: url).analyze(interests),
        throwsA(
          isA<RelationApiException>().having(
            (e) => e.code,
            'code',
            'CONFIGURATION',
          ),
        ),
      );
    }
  });
}
