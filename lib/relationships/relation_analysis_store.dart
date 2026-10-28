import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../diary/diary_store.dart';
import 'relation_api.dart';
import 'relationship_data.dart';

String _digest(Object value) =>
    sha256.convert(utf8.encode(jsonEncode(value))).toString();

// Both the demo server and app reset their budgets at midnight in Korea.
String analysisDay(DateTime now) => now
    .toUtc()
    .add(const Duration(hours: 9))
    .toIso8601String()
    .substring(0, 10);

class RelationAnalysisStatus {
  const RelationAnalysisStatus({
    required this.canUpdate,
    required this.message,
    required this.newRecords,
    required this.remaining,
  });
  final bool canUpdate;
  final String message;
  final int newRecords;
  final int remaining;
}

/// Separate from diary storage: no change to the diary format or original logs.
/// A successful empty result is a snapshot too; errors never replace it.
class RelationAnalysisStore {
  RelationAnalysisStore({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? (() => SharedPreferencesAsync().getString(storageKey)),
       _write =
           write ??
           ((value) => SharedPreferencesAsync().setString(storageKey, value));

  static const storageKey = 'jangjak.relations.v1';
  static const dailyLimit = 5;
  static const requiredNewRecords = 3;
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  Future<void>? _loading;
  bool _loaded = false;
  bool _busy = false;
  bool _dirty = false;
  Map<String, dynamic>? _snapshot;
  List<Interest>? _latestInterests;
  String _day = '';
  int _attempts = 0;

  bool get hasResult => _snapshot != null;
  bool get busy => _busy;
  DateTime? get analyzedAt =>
      _snapshot == null ? null : DateTime.parse(_snapshot!['at'] as String);

  Future<void> load() async {
    if (_loaded) return;
    if (_loading != null) return _loading;
    _loading = _load();
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _load() async {
    try {
      final text = await _read();
      if (text != null) {
        final json = jsonDecode(text) as Map<String, dynamic>;
        if (json['version'] != 1 ||
            json['day'] is! String ||
            json['attempts'] is! int ||
            (json['attempts'] as int) < 0) {
          throw const FormatException('Invalid analysis cache');
        }
        final snapshot = json['snapshot'] as Map<String, dynamic>?;
        if (snapshot != null) {
          DateTime.parse(snapshot['at'] as String);
          final digest = RegExp(r'^[a-f0-9]{64}$');
          if (!digest.hasMatch(snapshot['fingerprint'] as String)) {
            throw const FormatException('Invalid fingerprint');
          }
          final ids = <String>{};
          for (final item in snapshot['baseline'] as List) {
            final node = item as Map;
            if (!ids.add(node['id'] as String) ||
                !digest.hasMatch(node['title'] as String)) {
              throw const FormatException('Invalid baseline');
            }
            for (final value in node['entries'] as List) {
              final entry = value as Map;
              DateTime.parse(entry['at'] as String);
              if (!digest.hasMatch(entry['text'] as String)) {
                throw const FormatException('Invalid baseline entry');
              }
            }
          }
          if ((snapshot['relations'] as List).length > 30) {
            throw const FormatException('Invalid relations');
          }
        }
        _day = json['day'] as String;
        _attempts = json['attempts'] as int;
        _snapshot = snapshot;
      }
      _loaded = true;
    } catch (_) {
      throw const RelationApiException(
        'CACHE_READ_FAILED',
        '저장된 관계를 읽지 못했어요. 다시 불러와 주세요.',
      );
    }
  }

  String _encode({
    Map<String, dynamic>? snapshot,
    String? day,
    int? attempts,
  }) => jsonEncode({
    'version': 1,
    'day': day ?? _day,
    'attempts': attempts ?? _attempts,
    'snapshot': snapshot ?? _snapshot,
  });

  static List<Map<String, Object>> _baseline(List<Interest> interests) => [
    for (final interest in interests)
      {
        'id': interest.id,
        'title': _digest(interest.title),
        'entries': [
          for (final entry in interest.entries.where(
            (entry) => entry.text.trim().isNotEmpty,
          ))
            {
              'at': entry.createdAt.toUtc().toIso8601String(),
              'text': _digest(entry.text),
            },
        ],
      },
  ];

  static String _fingerprint(List<Interest> interests) {
    final request = RelationApi.buildRequest(interests);
    final nodes = [
      for (final item in request['interests'] as List)
        {
          'id': (item as Map)['id'],
          'title': item['title'],
          'logs': (List<String>.from(item['logs'] as List)..sort()),
        },
      for (final item in request['candidateInterests'] as List? ?? [])
        {'id': (item as Map)['id'], 'title': item['title'], 'logs': <String>[]},
    ]..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    return _digest(nodes);
  }

  RelationAnalysisStatus status(List<Interest> interests, DateTime now) {
    final remaining = analysisDay(now) == _day
        ? (dailyLimit - _attempts).clamp(0, dailyLimit)
        : dailyLimit;
    RelationAnalysisStatus result(
      bool allowed,
      String message, [
      int added = 0,
    ]) => RelationAnalysisStatus(
      canUpdate: allowed && remaining > 0 && !_busy,
      newRecords: added,
      remaining: remaining,
      message: remaining == 0
          ? '오늘 분석 5회를 모두 사용했어요. 내일 다시 업데이트할 수 있어요.'
          : message,
    );
    if (interests.length < 2 ||
        !interests.any(
          (item) => item.entries.any((entry) => entry.text.trim().isNotEmpty),
        )) {
      return result(false, '불 2개와 장작 기록 1개 이상이 필요해요.');
    }
    final fingerprint = _fingerprint(interests);
    if (_snapshot == null) return result(true, '최근 장작 원문을 AI 서버로 보내 관계를 찾아요.');
    if (_snapshot!['invalidated'] == true) {
      return result(true, '근거 기록이 변경되어 저장된 연결을 정리했어요. 관계를 업데이트할 수 있어요.');
    }
    if (fingerprint == _snapshot!['fingerprint']) {
      return result(false, '마지막 분석 이후 바뀐 기록이 없어요. 저장된 관계를 보여드려요.');
    }

    final before = {
      for (final item in _snapshot!['baseline'] as List)
        (item as Map)['id'] as String: item,
    };
    var added = 0;
    var revised = false;
    final current = _baseline(interests);
    for (final item in current) {
      final old = before.remove(item['id']);
      if (old == null) {
        revised = true;
        continue;
      }
      if (old['title'] != item['title']) revised = true;
      // Timestamps survive edits. Multisets handle simultaneous records without
      // mistaking an edited record for a newly added one.
      Map<String, List<String>> groups(List entries) {
        final values = <String, List<String>>{};
        for (final entry in entries) {
          values
              .putIfAbsent((entry as Map)['at'] as String, () => [])
              .add(entry['text'] as String);
        }
        return values;
      }

      final previous = groups(old['entries'] as List);
      final latest = groups(item['entries'] as List);
      for (final time in {...previous.keys, ...latest.keys}) {
        final a = List<String>.of(previous[time] ?? []);
        final b = List<String>.of(latest[time] ?? []);
        for (final text in List<String>.of(b)) {
          if (a.remove(text)) b.remove(text);
        }
        if (a.isNotEmpty) revised = true;
        if (b.length > a.length) added += b.length - a.length;
      }
    }
    if (before.isNotEmpty) revised = true;
    if (revised) return result(true, '관심사나 기록이 변경되어 관계를 업데이트할 수 있어요.', added);
    return result(
      added >= requiredNewRecords,
      '새 장작 $added/3개 · 3개가 쌓이면 관계를 업데이트할 수 있어요.',
      added,
    );
  }

  /// Rebind saved IDs to today's nodes and drop each invalid edge separately.
  /// Deleted/edited quotations are removed from disk as well as from the graph.
  Future<RelationshipMap> restore(List<Interest> interests) async {
    _latestInterests = interests;
    await load();
    final map = cachedMap(interests);
    if (_snapshot != null) {
      final relations = _relations(map);
      final changed =
          jsonEncode(relations) != jsonEncode(_snapshot!['relations']);
      if (_dirty || changed) {
        final pruned = {
          ..._snapshot!,
          'relations': relations,
          if (changed) 'invalidated': true,
        };
        _snapshot = pruned;
        _dirty = true;
        try {
          await _write(_encode(snapshot: pruned));
          _dirty = false;
        } catch (_) {
          throw const RelationApiException(
            'CACHE_WRITE_FAILED',
            '관계 캐시를 저장하지 못했어요. 저장 공간을 확인해 주세요.',
          );
        }
      }
    }
    return map;
  }

  RelationshipMap cachedMap(List<Interest> interests) {
    final request = <String, Object>{
      'interests': [
        for (final item in interests.where(
          (item) => item.entries.any((entry) => entry.text.trim().isNotEmpty),
        ))
          {
            'id': item.id,
            'title': item.title,
            'logs': item.entries
                .where((entry) => entry.text.trim().isNotEmpty)
                .map((entry) => entry.text)
                .toList(),
          },
      ],
      'candidateInterests': [
        for (final item in interests.where(
          (item) => !item.entries.any((entry) => entry.text.trim().isNotEmpty),
        ))
          {'id': item.id, 'title': item.title},
      ],
    };
    final edges = <InterestConnection>[];
    for (final relation in _snapshot?['relations'] as List? ?? []) {
      try {
        edges.addAll(
          RelationApi.parseResponse(
            {
              'relations': [relation],
            },
            interests,
            request,
          ).connections,
        );
      } on RelationApiException {
        /* A removed quotation or node invalidates only its own edge. */
      }
    }
    return RelationshipMap(interests: interests, connections: edges);
  }

  static List<Map<String, Object?>> _relations(RelationshipMap map) => [
    for (final edge in map.connections)
      {
        'source': edge.left.id,
        'target': edge.right.id,
        'score': edge.strength,
        'type': edge.type!.name,
        'basis': edge.basis.apiValue,
        'summary': edge.summary,
        'evidence': edge.evidence
            .map((item) => item.entry.text)
            .toSet()
            .toList(),
        'suggestion': edge.suggestion,
      },
  ];

  Future<RelationshipMap> analyze(
    List<Interest> interests,
    RelationApi api,
    DateTime Function() clock,
  ) async {
    await load();
    if (_busy) {
      throw const RelationApiException('IN_PROGRESS', '이미 관계를 업데이트하고 있어요.');
    }
    final policy = status(interests, clock());
    if (!policy.canUpdate) {
      if (hasResult) return cachedMap(interests);
      throw RelationApiException('ANALYSIS_NOT_READY', policy.message);
    }
    _busy = true;
    _latestInterests = interests;
    try {
      final day = analysisDay(clock());
      final attempts = day == _day ? _attempts + 1 : 1;
      // Reserve durably before HTTP; even failed requests may cost the provider.
      try {
        await _write(_encode(day: day, attempts: attempts));
      } catch (_) {
        throw const RelationApiException(
          'CACHE_WRITE_FAILED',
          '사용 횟수를 저장하지 못해 분석을 시작하지 않았어요.',
        );
      }
      _day = day;
      _attempts = attempts;
      final result = await api.analyze(interests);
      final snapshot = <String, dynamic>{
        'at': clock().toUtc().toIso8601String(),
        'fingerprint': _fingerprint(interests),
        'baseline': _baseline(interests),
        'relations': _relations(result),
        'invalidated': false,
      };
      // Keep a valid response in memory even if the disk write fails, avoiding
      // another paid request in this session. The UI reports persistence failure.
      _snapshot = snapshot;
      final visible = cachedMap(_latestInterests ?? interests);
      _snapshot!['relations'] = _relations(visible);
      if (visible.connections.length != result.connections.length) {
        _snapshot!['invalidated'] = true;
      }
      _dirty = true;
      try {
        await _write(_encode());
        _dirty = false;
      } catch (_) {
        throw const RelationApiException(
          'CACHE_WRITE_FAILED',
          '분석은 완료했지만 기기에 저장하지 못했어요. 앱을 닫기 전에 저장 공간을 확인해 주세요.',
        );
      }
      return visible;
    } finally {
      _busy = false;
    }
  }
}
