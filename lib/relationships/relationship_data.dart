import '../diary/diary_store.dart';

enum RelationType {
  topic('공통 주제'),
  motivation('공통 동기'),
  behavior('비슷한 행동'),
  transition('관심의 전이');

  const RelationType(this.label);
  final String label;
}

class ConnectionEvidence {
  const ConnectionEvidence(this.interest, this.entry);
  final Interest interest;
  final DiaryEntry entry;
}

class InterestConnection {
  const InterestConnection({
    required this.left,
    required this.right,
    required this.strength,
    required this.themes,
    required this.evidence,
    this.type,
    this.summary,
    this.suggestion,
  });
  final Interest left;
  final Interest right;
  final double strength;
  final List<String> themes;
  final List<ConnectionEvidence> evidence;
  final RelationType? type;
  final String? summary;
  final String? suggestion;
  String get id => '${left.id}::${right.id}';
  bool contains(String id) => left.id == id || right.id == id;
  String get label =>
      '${left.title}${type == RelationType.transition ? ' → ' : ' · '}${right.title}';
  String get closeness => strength >= .75
      ? '깊은 연결'
      : strength >= .6
      ? '가까운 연결'
      : '작은 연결';
  String get explanation =>
      summary ??
      '두 관심사의 기록에서 ${themes.map((theme) => '‘$theme’').join(', ')}에 관한 표현이 함께 발견됐어요. '
          '서로 다른 활동 속에 비슷한 마음이 머물러 있을 수 있어요.';
}

class RelationshipMap {
  const RelationshipMap({
    required this.interests,
    required this.connections,
    this.candidates = const [],
    this.isExample = false,
  });
  final List<Interest> interests;
  final List<InterestConnection> connections;
  final List<InterestConnection> candidates;
  final bool isExample;

  Iterable<InterestConnection> connectionsFor(String id) =>
      connections.where((connection) => connection.contains(id));

  List<InterestConnection> suggestionsFor(InterestConnection current) =>
      candidates
          .where(
            (candidate) =>
                candidate.id != current.id &&
                (candidate.contains(current.left.id) ||
                    candidate.contains(current.right.id)),
          )
          .take(2)
          .toList();
}

/// A transparent local preview, not an AI inference. Both ends must have an
/// actual matching diary entry; titles alone never create a relationship.
class RecordRelationshipAnalyzer {
  static const _themes = {
    '영감과 표현': ['영감', '표현', '이야기', '문장', '가사', '멜로디', '그림'],
    '자연을 만나는 시간': ['산책', '공원', '숲', '바람', '풍경', '나무'],
    '나만의 리듬': ['리듬', '호흡', '박자', '페이스', '템포'],
    '마음의 휴식': ['위로', '차분', '고요', '휴식', '명상', '편안'],
    '조금씩 쌓는 습관': ['연습', '꾸준', '반복', '루틴', '매일', '습관'],
    '새롭게 바라보기': ['관찰', '색감', '빛', '사진', '구도'],
  };

  RelationshipMap analyze(List<Interest> interests, {bool isExample = false}) {
    final matches = <String, Map<String, List<DiaryEntry>>>{};
    for (final interest in interests) {
      matches[interest.id] = {
        for (final theme in _themes.entries)
          theme.key: interest.entries
              .where(
                (entry) => theme.value.any(entry.text.toLowerCase().contains),
              )
              .toList(),
      };
    }
    final pairs = <InterestConnection>[];
    for (var i = 0; i < interests.length; i++) {
      for (var j = i + 1; j < interests.length; j++) {
        final left = interests[i], right = interests[j];
        final shared = _themes.keys
            .where(
              (theme) =>
                  matches[left.id]![theme]!.isNotEmpty &&
                  matches[right.id]![theme]!.isNotEmpty,
            )
            .toList();
        if (shared.isEmpty) continue;
        final evidence = <ConnectionEvidence>[];
        for (final interest in [left, right]) {
          final entries =
              shared
                  .expand((theme) => matches[interest.id]![theme]!)
                  .toSet()
                  .toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          evidence.addAll(
            entries.take(2).map((entry) => ConnectionEvidence(interest, entry)),
          );
        }
        pairs.add(
          InterestConnection(
            left: left,
            right: right,
            strength: (.32 + shared.length * .13 + evidence.length * .045)
                .clamp(.35, .94),
            themes: shared,
            evidence: evidence,
          ),
        );
      }
    }
    pairs.sort((a, b) {
      final strength = b.strength.compareTo(a.strength);
      return strength != 0 ? strength : a.id.compareTo(b.id);
    });
    final connections = <InterestConnection>[],
        candidates = <InterestConnection>[];
    final degree = <String, int>{};
    for (final pair in pairs) {
      if ((degree[pair.left.id] ?? 0) < 3 && (degree[pair.right.id] ?? 0) < 3) {
        connections.add(pair);
        degree.update(pair.left.id, (count) => count + 1, ifAbsent: () => 1);
        degree.update(pair.right.id, (count) => count + 1, ifAbsent: () => 1);
      } else {
        candidates.add(pair);
      }
    }
    return RelationshipMap(
      interests: interests,
      connections: connections,
      candidates: candidates,
      isExample: isExample,
    );
  }
}

RelationshipMap exampleRelationshipMap(DateTime now) {
  Interest fire(String id, String title, FireLevel level, List<String> notes) =>
      Interest(
        id: id,
        title: title,
        level: level,
        heatUpdatedAt: now,
        entries: [
          for (var i = 0; i < notes.length; i++)
            DiaryEntry(
              text: notes[i],
              createdAt: now.subtract(Duration(days: i, hours: 2)),
            ),
        ],
      );
  return RecordRelationshipAnalyzer().analyze([
    fire('example-books', '책 읽기', FireLevel.blazing, [
      '책 속 문장에서 위로를 받았다. 고요한 밤, 이야기의 리듬을 천천히 따라갔다.',
      '매일 몇 쪽씩 읽으며 표현을 모은다. 이 문장을 가사로 바꿔보고 싶은 영감이 생겼다.',
    ]),
    fire('example-guitar', '기타 치기', FireLevel.largeFire, [
      '오늘도 꾸준히 연습했다. 멜로디의 리듬에 맞춰 책에서 받은 위로를 표현해 봤다.',
      '차분한 가사를 쓰며 나만의 박자를 찾는 시간.',
    ]),
    fire('example-walk', '산책하기', FireLevel.smallFire, [
      '공원의 나무 사이를 걸었다. 고요한 바람에 호흡을 맞추니 마음이 편안해졌다.',
    ]),
    fire('example-photo', '사진 찍기', FireLevel.revivedEmber, [
      '산책 중 나무 사이로 드는 빛을 관찰했다. 풍경의 색감에서 그림의 영감을 얻었다.',
    ]),
    fire('example-run', '달리기', FireLevel.largeFire, [
      '매일 공원에서 달리는 루틴. 호흡과 페이스를 맞추며 나만의 리듬을 찾았다.',
    ]),
    fire('example-draw', '그림 그리기', FireLevel.faintEmber, [
      '책 속 이야기에서 떠오른 그림. 사진의 빛과 색감을 관찰하며 표현을 연습했다.',
    ]),
    fire('example-rest', '명상하기', FireLevel.ash, [
      '고요한 아침에 호흡을 가다듬었다. 휴식의 리듬이 편안하게 느껴졌다.',
    ]),
  ], isExample: true);
}
