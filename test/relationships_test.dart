import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jangjak_diary/diary/diary_store.dart';
import 'package:jangjak_diary/relationships/connection_sheet.dart';
import 'package:jangjak_diary/relationships/force_layout.dart';
import 'package:jangjak_diary/relationships/relationship_data.dart';
import 'package:jangjak_diary/relationships/relationship_screen.dart';
import 'package:jangjak_diary/relationships/relation_api.dart';
import 'package:jangjak_diary/relationships/relation_analysis_store.dart';
import 'package:jangjak_diary/theme/diary_theme.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26, 12);
  Interest fire(String id, String text, {String? title}) => Interest(
    id: id,
    title: title ?? id,
    heatUpdatedAt: now,
    level: text.isEmpty ? FireLevel.ash : FireLevel.faintEmber,
    entries: text.isEmpty ? [] : [DiaryEntry(text: text, createdAt: now)],
  );
  final pair = [
    fire('books', '책 속 이야기의 리듬에서 위로를 받았다.', title: '책 읽기'),
    fire('guitar', '멜로디의 리듬과 가사로 위로를 표현했다.', title: '기타 치기'),
  ];

  test(
    'connections require matching records on both sides, not only titles',
    () {
      final map = RecordRelationshipAnalyzer().analyze([
        fire('empty', '', title: '음악 리듬'),
        fire('unrelated', '오늘 저녁에는 파스타를 먹었다.'),
        ...pair,
      ]);
      expect(map.connections, hasLength(1));
      final edge = map.connections.single;
      expect({edge.left.id, edge.right.id}, {'books', 'guitar'});
      expect(edge.themes, contains('나만의 리듬'));
      expect(edge.evidence.map((item) => item.entry.text).toSet(), {
        '책 속 이야기의 리듬에서 위로를 받았다.',
        '멜로디의 리듬과 가사로 위로를 표현했다.',
      });
    },
  );

  test('richer shared evidence creates a stronger connection', () {
    final weak = RecordRelationshipAnalyzer()
        .analyze([fire('a', '호흡을 맞췄다.'), fire('b', '박자에 맞췄다.')])
        .connections
        .single;
    final strong = RecordRelationshipAnalyzer()
        .analyze(pair)
        .connections
        .single;
    expect(strong.strength, greaterThan(weak.strength));
  });

  test(
    'dense maps keep a small neighborhood and offer other grounded links',
    () {
      final map = RecordRelationshipAnalyzer().analyze([
        for (var i = 0; i < 8; i++) fire('$i', '고요한 호흡과 리듬 속에 휴식을 찾았다.'),
      ]);
      for (final node in map.interests) {
        expect(map.connectionsFor(node.id).length, lessThanOrEqualTo(3));
      }
      expect(map.candidates, isNotEmpty);
      expect(map.suggestionsFor(map.connections.first), isNotEmpty);
      for (final suggestion in map.suggestionsFor(map.connections.first)) {
        expect(
          map.connections.map((edge) => edge.id),
          isNot(contains(suggestion.id)),
        );
        expect(suggestion.evidence, hasLength(2));
      }
    },
  );

  test(
    'force layout stays finite and contained, including disconnected nodes',
    () {
      for (final map in [
        RecordRelationshipAnalyzer().analyze([]),
        RecordRelationshipAnalyzer().analyze([fire('alone', '')]),
        exampleRelationshipMap(now),
      ]) {
        final layout = ForceLayout(map, const Size(320, 350));
        for (var i = 0; i < 100; i++) {
          layout.step();
        }
        for (final point in layout.positions.values) {
          expect(point.dx, inInclusiveRange(52, 268));
          expect(point.dy, inInclusiveRange(42, 284));
        }
      }
      expect(
        distanceToSegment(
          const Offset(50, 9),
          Offset.zero,
          const Offset(100, 0),
        ),
        9,
      );
      expect(
        distanceToSegment(
          const Offset(110, 0),
          Offset.zero,
          const Offset(100, 0),
        ),
        10,
      );
    },
  );

  Future<void> open(
    WidgetTester tester, {
    List<Interest>? interests,
    Size size = const Size(393, 852),
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: DiaryTheme.data,
        home: RelationshipScreen(
          interests: interests ?? pair,
          clock: () => now,
          analysisStore: RelationAnalysisStore(
            read: () async => null,
            write: (_) async {},
          ),
          api: RelationApi(
            baseUrl: 'http://test.local',
            client: MockClient(
              (_) async => http.Response(
                jsonEncode({
                  'relations':
                      (interests ?? pair).any((item) => item.id == 'books')
                      ? [
                          {
                            'source': 'books',
                            'target': 'guitar',
                            'score': 0.66,
                            'type': 'motivation',
                            'summary': '위로를 표현하는 즐거움이 공통됩니다.',
                            'evidence': pair
                                .map((item) => item.entries.first.text)
                                .toList(),
                            'suggestion': '책의 한 문장을 멜로디로 표현해보세요.',
                          },
                        ]
                      : [],
                }),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8',
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if ((interests ?? pair).any((item) => item.id == 'books')) {
      await tester.tap(find.text('관계 찾기'));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('touching a line opens its reason and original evidence', (
    tester,
  ) async {
    await open(tester);
    final a =
        tester.getTopLeft(find.byKey(const ValueKey('graph-node-books'))) +
        const Offset(50, 30);
    final b =
        tester.getTopLeft(find.byKey(const ValueKey('graph-node-guitar'))) +
        const Offset(50, 30);
    await tester.tapAt(Offset.lerp(a, b, .5)!);
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionSheet), findsOneWidget);
    expect(find.text('근거 기록'), findsOneWidget);
    expect(find.text('책 속 이야기의 리듬에서 위로를 받았다.'), findsOneWidget);
    expect(find.text('멜로디의 리듬과 가사로 위로를 표현했다.'), findsOneWidget);
    expect(find.text('함께 해볼 행동'), findsOneWidget);
    expect(find.text('위로를 표현하는 즐거움이 공통됩니다.'), findsOneWidget);
    expect(find.text('밀접도 0.66'), findsOneWidget);
    expect(find.text('책의 한 문장을 멜로디로 표현해보세요.'), findsOneWidget);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionSheet), findsNothing);
  });

  testWidgets('selecting a node offers only its own connections', (
    tester,
  ) async {
    await open(
      tester,
      interests: [
        ...pair,
        fire('cooking', '파스타를 만들었다.', title: '요리하기'),
      ],
    );
    await tester.tap(find.byKey(const ValueKey('graph-node-books')));
    await tester.pumpAndSettle();
    expect(find.text('책 읽기 · 작은 불씨'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '기타 치기'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '요리하기'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, '기타 치기'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectionSheet), findsOneWidget);
  });

  testWidgets(
    'example mode stays separate from personal interests on a small screen',
    (tester) async {
      await open(
        tester,
        interests: [fire('mine', '', title: '내 관심사 하나')],
        size: const Size(320, 568),
      );
      expect(find.text('아직 관계를 분석하지 않았어요'), findsOneWidget);
      await tester.tap(find.text('예시 관계도'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('graph-node-example-books')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('graph-node-mine')), findsNothing);
      await tester.tap(find.byTooltip('관계도 확대'));
      await tester.tap(find.byTooltip('전체 배치로 돌아가기'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('내 관심사'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('graph-node-mine')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('graph-node-example-books')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('selecting an example node keeps the constellation in place', (
    tester,
  ) async {
    await open(tester, size: const Size(897, 853));
    await tester.tap(find.text('예시 관계도'));
    await tester.pumpAndSettle();
    final node = find.byKey(const ValueKey('graph-node-example-books'));
    final before = tester.getCenter(node);
    await tester.tap(node);
    await tester.pumpAndSettle();
    expect((tester.getCenter(node) - before).distance, lessThan(12));
    expect(find.text('책 읽기 · 활활 타는 불'), findsOneWidget);
  });

  testWidgets('a focused node can be selected with the keyboard', (
    tester,
  ) async {
    await open(tester);
    final node = find.byKey(const ValueKey('graph-node-books'));
    Focus.of(tester.element(node)).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('책 읽기 · 작은 불씨'), findsOneWidget);
  });

  testWidgets(
    'opening a suggested connection brings its explanation to the top',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('예시 관계도'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('graph-node-example-books')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '기타 치기'));
      await tester.pumpAndSettle();
      final suggestion = find.text('기타 치기 · 달리기');
      await tester.scrollUntilVisible(
        suggestion,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ConnectionSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(suggestion);
      await tester.pumpAndSettle();
      expect(find.byTooltip('닫기').hitTestable(), findsOneWidget);
      expect(find.byTooltip('이전 연결').hitTestable(), findsOneWidget);
    },
  );
}
