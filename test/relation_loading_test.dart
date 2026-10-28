import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jangjak_diary/diary/diary_store.dart';
import 'package:jangjak_diary/relationships/relation_api.dart';
import 'package:jangjak_diary/relationships/relation_analysis_store.dart';
import 'package:jangjak_diary/relationships/relationship_graph.dart';
import 'package:jangjak_diary/relationships/relationship_screen.dart';

void main() {
  final now = DateTime.utc(2026, 10, 26);
  final interests = [
    for (final id in ['a', 'b'])
      Interest(
        id: id,
        title: id,
        heatUpdatedAt: now,
        entries: [DiaryEntry(text: '매일 호흡과 리듬을 맞췄다.', createdAt: now)],
      ),
  ];

  testWidgets(
    'loading blocks duplicates, separates error from empty, and retries',
    (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<http.Response>();
      var calls = 0;
      String? saved;
      RelationAnalysisStore openCache() => RelationAnalysisStore(
        read: () async => saved,
        write: (value) async => saved = value,
      );
      final client = MockClient((_) async {
        calls++;
        return calls == 1
            ? pending.future
            : http.Response('{"relations":[]}', 200);
      });
      final api = RelationApi(baseUrl: 'http://test.local', client: client);
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: RelationshipScreen(
            interests: interests,
            clock: () => now,
            api: api,
            analysisStore: openCache(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, 0);
      await tester.tap(find.text('관계 찾기'));
      await tester.pump();
      expect(find.text('관계를 분석하고 있어요…'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '분석 중'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('분석 중'));
      await tester.pump();
      expect(calls, 1);
      await tester.tap(find.text('예시 관계도'));
      await tester.pump();
      await tester.tap(find.text('내 관심사'));
      await tester.pump();
      expect(calls, 1);
      expect(find.text('관계를 분석하고 있어요…'), findsOneWidget);
      pending.complete(
        http.Response(
          jsonEncode({
            'error': {
              'code': 'INVALID_LLM_RESPONSE',
              'message': '관계 분석 결과 형식이 올바르지 않습니다.',
            },
          }),
          502,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('관계 분석에 실패했어요'), findsOneWidget);
      expect(find.textContaining('INVALID_LLM_RESPONSE'), findsOneWidget);
      expect(find.text('아직 발견된 연결이 없어요'), findsNothing);
      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('관계 분석을 마쳤어요'), findsOneWidget);
      expect(find.textContaining('이번 분석에서는 충분한 근거'), findsOneWidget);
      expect(find.text('관계 분석에 실패했어요'), findsNothing);
      // Matching local keywords must not fabricate edges after a server empty result.
      expect(
        tester
            .widget<RelationshipGraph>(find.byType(RelationshipGraph))
            .map
            .connections,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '관계 업데이트'))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: RelationshipScreen(
            interests: interests,
            clock: () => now,
            api: api,
            analysisStore: openCache(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('마지막 분석 이후 바뀐 기록이 없어요'), findsOneWidget);
      expect(find.text('관계 분석을 마쳤어요'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, '관계 업데이트'))
            .onPressed,
        isNull,
      );
      expect(calls, 2);
    },
  );
}
