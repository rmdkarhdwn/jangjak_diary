import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../diary/diary_store.dart';
import 'relationship_data.dart';

class RelationApiException implements Exception {
  const RelationApiException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

/// The server owns relation selection and scores. No local fallback is used.
class RelationApi {
  RelationApi({
    this.baseUrl = const String.fromEnvironment('AI_BASE_URL'),
    this.timeout = const Duration(seconds: 55),
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  final String baseUrl;
  final Duration timeout;
  final http.Client _client;
  final bool _ownsClient;
  Completer<void>? _abort;

  static const invalidResponse = RelationApiException(
    'INVALID_RESPONSE',
    '관계 분석 응답 형식이 올바르지 않습니다. 다시 시도해 주세요.',
  );

  static Map<String, Object> buildRequest(List<Interest> interests) {
    final ids = <String>{};
    final items = <Map<String, Object>>[];
    final candidates = <Map<String, String>>[];
    for (final interest in interests) {
      if (interest.id.trim() != interest.id ||
          interest.id.isEmpty ||
          interest.id.length > 100 ||
          !ids.add(interest.id)) {
        throw const RelationApiException(
          'INVALID_INPUT',
          '관심사 ID가 비어 있거나 중복되어 분석할 수 없어요.',
        );
      }
      if (interest.title.trim().isEmpty || interest.title.trim().length > 200) {
        throw const RelationApiException(
          'INVALID_INPUT',
          '관심사 이름은 1~200자로 입력해 주세요.',
        );
      }
      final logs = interest.entries
          .where((entry) => entry.text.trim().isNotEmpty)
          .take(30)
          .map((entry) => entry.text)
          .toList();
      if (logs.isEmpty) {
        candidates.add({'id': interest.id, 'title': interest.title});
        continue;
      }
      if (logs.any((text) => text.length > 2000)) {
        throw const RelationApiException(
          'INVALID_INPUT',
          '관심사 이름은 200자, 장작 기록은 2,000자까지 분석할 수 있어요. 원문은 줄이지 않습니다.',
        );
      }
      items.add({'id': interest.id, 'title': interest.title, 'logs': logs});
    }
    if (items.length + candidates.length > 12) {
      throw const RelationApiException(
        'INVALID_INPUT',
        '현재 서버는 관심사를 한 번에 12개까지 분석할 수 있어요.',
      );
    }
    final request = <String, Object>{
      'interests': items,
      if (candidates.isNotEmpty) 'candidateInterests': candidates,
    };
    if (utf8.encode(jsonEncode(request)).length > 128 * 1024) {
      throw const RelationApiException(
        'PAYLOAD_TOO_LARGE',
        '분석할 기록이 서버의 한 번 요청 크기(128 KiB)를 넘었어요.',
      );
    }
    return request;
  }

  Future<RelationshipMap> analyze(List<Interest> interests) async {
    if (_abort != null) {
      throw const RelationApiException('IN_PROGRESS', '이미 관계를 분석하고 있어요.');
    }
    final payload = buildRequest(interests);
    if ((payload['interests']! as List).isEmpty) {
      throw const RelationApiException(
        'NO_LOGS',
        '분석할 장작 기록이 아직 없어요. 먼저 장작을 남겨 주세요.',
      );
    }
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null ||
        !['http', 'https'].contains(base.scheme) ||
        base.host.isEmpty ||
        base.host == '0.0.0.0' ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const RelationApiException(
        'CONFIGURATION',
        '분석 서버 주소가 설정되지 않았거나 올바르지 않아요. AI_BASE_URL 실행 설정을 확인해 주세요.',
      );
    }
    final uri = base.replace(
      path: '${base.path.replaceFirst(RegExp(r'/+$'), '')}/analyze-relations',
    );
    final abort = Completer<void>();
    _abort = abort;
    try {
      final request =
          http.AbortableRequest('POST', uri, abortTrigger: abort.future)
            ..headers['Content-Type'] = 'application/json'
            ..body = jsonEncode(payload);
      final response = await (() async {
        final stream = await _client.send(request);
        return http.Response.fromStream(stream);
      })().timeout(timeout);
      Object? decoded;
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } on FormatException {
        if (response.statusCode != 200) {
          throw RelationApiException(
            'HTTP_${response.statusCode}',
            '분석 서버가 오류를 반환했어요. 잠시 후 다시 시도해 주세요.',
          );
        }
        throw invalidResponse;
      }
      if (response.statusCode != 200) {
        if (decoded is Map && decoded['error'] is Map) {
          final error = decoded['error'] as Map;
          if (error['code'] is String &&
              error['message'] is String &&
              (error['message'] as String).trim().isNotEmpty) {
            throw RelationApiException(
              error['code'] as String,
              error['message'] as String,
            );
          }
        }
        throw RelationApiException(
          'HTTP_${response.statusCode}',
          '분석 서버가 오류를 반환했어요. 잠시 후 다시 시도해 주세요.',
        );
      }
      return parseResponse(decoded, interests, payload);
    } on TimeoutException {
      throw const RelationApiException(
        'CLIENT_TIMEOUT',
        '분석 응답을 55초 안에 받지 못했어요. 연결을 확인하고 다시 시도해 주세요.',
      );
    } on http.ClientException {
      throw const RelationApiException(
        'NETWORK',
        '분석 서버에 연결하지 못했어요. 서버 실행 상태와 네트워크를 확인해 주세요.',
      );
    } finally {
      if (!abort.isCompleted) abort.complete();
      _abort = null;
    }
  }

  static RelationshipMap parseResponse(
    Object? body,
    List<Interest> interests,
    Map<String, Object> request,
  ) {
    if (body is! Map || body['relations'] is! List) throw invalidResponse;
    final relations = body['relations'] as List;
    if (relations.length > 30) throw invalidResponse;
    final nodes = {for (final interest in interests) interest.id: interest};
    final sent = {
      for (final item in request['interests']! as List)
        (item as Map)['id'] as String: Set<String>.from(item['logs'] as List),
    };
    final candidates = {
      for (final item in (request['candidateInterests'] as List? ?? []))
        (item as Map)['id'] as String,
    };
    final pairs = <String>{};
    final connections = <InterestConnection>[];
    for (final value in relations) {
      if (value is! Map) throw invalidResponse;
      final source = value['source'], target = value['target'];
      final score = value['score'], type = value['type'];
      final summary = value['summary'], evidence = value['evidence'];
      final suggestion = value['suggestion'];
      final basisValue = value['basis'] ?? 'shared_logs';
      final isReference = basisValue == 'explicit_reference';
      if (source is! String ||
          target is! String ||
          source == target ||
          !sent.containsKey(source) ||
          (!sent.containsKey(target) && !candidates.contains(target)) ||
          !nodes.containsKey(source) ||
          !nodes.containsKey(target) ||
          !RelationBasis.values.any((item) => item.apiValue == basisValue) ||
          score is! num ||
          !score.isFinite ||
          score < 0 ||
          score > 1 ||
          type is! String ||
          !RelationType.values.any((item) => item.name == type) ||
          summary is! String ||
          summary.trim().isEmpty ||
          suggestion is! String ||
          suggestion.trim().isEmpty ||
          evidence is! List ||
          evidence.length < (isReference ? 1 : 2) ||
          evidence.length > 10 ||
          evidence.any((text) => text is! String || text.trim().isEmpty)) {
        throw invalidResponse;
      }
      final pair = [source, target]..sort();
      if (!pairs.add(jsonEncode(pair))) throw invalidResponse;
      final quotes = evidence.cast<String>();
      if (quotes.toSet().length != quotes.length) throw invalidResponse;
      if (isReference) {
        if (type != 'topic' ||
            quotes.any((text) => !sent[source]!.contains(text))) {
          throw invalidResponse;
        }
      } else if (!sent.containsKey(target) ||
          quotes.any(
            (text) =>
                !sent[source]!.contains(text) && !sent[target]!.contains(text),
          ) ||
          !quotes.any(sent[source]!.contains) ||
          !quotes.any(sent[target]!.contains)) {
        throw invalidResponse;
      }
      final kind = RelationType.values.byName(type);
      connections.add(
        InterestConnection(
          left: nodes[source]!,
          right: nodes[target]!,
          strength: score.toDouble(),
          themes: [isReference ? '기록 속 주제' : kind.label],
          type: kind,
          basis: isReference
              ? RelationBasis.explicitReference
              : RelationBasis.sharedLogs,
          summary: summary,
          suggestion: suggestion,
          evidence: [
            for (final quote in quotes)
              for (final id in [source, if (!isReference) target])
                if (sent[id]!.contains(quote))
                  ConnectionEvidence(
                    nodes[id]!,
                    nodes[id]!.entries.firstWhere(
                      (entry) => entry.text == quote,
                    ),
                  ),
          ],
        ),
      );
    }
    return RelationshipMap(interests: interests, connections: connections);
  }

  void close() {
    if (_abort case final abort? when !abort.isCompleted) abort.complete();
    if (_ownsClient) _client.close();
  }
}
