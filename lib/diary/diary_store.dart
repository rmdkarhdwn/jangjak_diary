import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum FireLevel {
  ash('재', '잠시 쉬어가는 중', 0),
  faintEmber('작은 불씨', '거의 꺼진 상태', 1),
  revivedEmber('살아난 불씨', '관심이 다시 생김', 3),
  smallFire('작은 불', '꾸준히 생각나는 상태', 5),
  largeFire('큰 불', '현재 꽤 몰입 중', 7),
  blazing('활활 타는 불', '최상위 관심 상태', 9);

  const FireLevel(this.label, this.description, this.requiredLogs);
  final String label;
  final String description;
  final int requiredLogs;

  int get logsForNextLevel =>
      this == blazing ? 0 : values[index + 1].requiredLogs - requiredLogs;
}

enum ArchiveReason {
  cooled('관심이 식었어요'),
  achieved('목표를 달성했어요'),
  transitioned('다른 관심사로 이어졌어요'),
  resting('지금은 쉬고 싶어요'),
  custom('직접 입력');

  const ArchiveReason(this.label);
  final String label;
}

enum FireEventKind { archived, rekindled }

class FireEvent {
  const FireEvent({
    required this.kind,
    required this.occurredAt,
    this.reason,
    this.note,
  });
  final FireEventKind kind;
  final DateTime occurredAt;
  final ArchiveReason? reason;
  final String? note;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'occurredAt': occurredAt.toUtc().toIso8601String(),
    'reason': reason?.name,
    'note': note,
  };

  factory FireEvent.fromJson(Map<String, dynamic> json) {
    try {
      return FireEvent(
        kind: FireEventKind.values.byName(json['kind'] as String),
        occurredAt: DateTime.parse(json['occurredAt'] as String),
        reason: json['reason'] == null
            ? null
            : ArchiveReason.values.byName(json['reason'] as String),
        note: json['note'] as String?,
      );
    } on ArgumentError {
      throw const FormatException('잘못된 불의 이력입니다.');
    }
  }
}

class DiaryEntry {
  const DiaryEntry({required this.text, required this.createdAt});

  final String text;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'text': text,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  factory DiaryEntry.fromJson(Map<String, dynamic> json) => DiaryEntry(
    text: json['text'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}

class Interest {
  const Interest({
    required this.id,
    required this.title,
    required this.heatUpdatedAt,
    this.level = FireLevel.ash,
    this.growthProgress = 0,
    this.entries = const [],
    this.events = const [],
  });

  static const coolingInterval = Duration(days: 3);
  final String id;
  final String title;
  // Level at heatUpdatedAt; elapsed cooling is calculated without mutating it.
  final FireLevel level;
  // Logs earned toward the next level since this snapshot. Cooling resets them.
  final int growthProgress;
  final DateTime heatUpdatedAt;
  final List<DiaryEntry> entries;
  final List<FireEvent> events;

  bool get isArchived =>
      events.isNotEmpty && events.last.kind == FireEventKind.archived;
  FireEvent? get lastArchive {
    for (final event in events.reversed) {
      if (event.kind == FireEventKind.archived) return event;
    }
    return null;
  }

  Interest archive(DateTime at, {ArchiveReason? reason, String? note}) {
    if (isArchived) return this;
    final trimmed = note?.trim();
    return Interest(
      id: id,
      title: title,
      heatUpdatedAt: heatUpdatedAt,
      level: level,
      growthProgress: growthProgress,
      entries: entries,
      events: [
        ...events,
        FireEvent(
          kind: FireEventKind.archived,
          occurredAt: at,
          reason: reason,
          note: trimmed == null || trimmed.isEmpty ? null : trimmed,
        ),
      ],
    );
  }

  Interest rekindle(DateTime at) {
    if (!isArchived) return this;
    return Interest(
      id: id,
      title: title,
      heatUpdatedAt: at,
      level: FireLevel.faintEmber,
      entries: entries,
      events: [
        ...events,
        FireEvent(kind: FireEventKind.rekindled, occurredAt: at),
      ],
    );
  }

  FireLevel levelAt(DateTime now) {
    if (isArchived) return FireLevel.ash;
    final elapsed = now.difference(heatUpdatedAt);
    if (elapsed.isNegative) return level;
    final steps = elapsed.inMicroseconds ~/ coolingInterval.inMicroseconds;
    final cooled = level.index - steps;
    return FireLevel.values[cooled < 0 ? 0 : cooled];
  }

  int growthProgressAt(DateTime now) =>
      !isArchived && levelAt(now) == level ? growthProgress : 0;

  int logsUntilNextLevelAt(DateTime now) =>
      isArchived ? 0 : levelAt(now).logsForNextLevel - growthProgressAt(now);

  Interest withEntry(DiaryEntry entry) {
    if (isArchived) throw StateError('다시 불붙인 뒤 장작을 넣을 수 있어요.');
    var nextLevel = levelAt(entry.createdAt);
    var nextProgress = growthProgressAt(entry.createdAt);
    if (nextLevel != FireLevel.blazing) {
      nextProgress++;
      if (nextProgress >= nextLevel.logsForNextLevel) {
        nextLevel = FireLevel.values[nextLevel.index + 1];
        nextProgress = 0;
      }
    }
    return Interest(
      id: id,
      title: title,
      level: nextLevel,
      growthProgress: nextProgress,
      heatUpdatedAt: entry.createdAt,
      entries: [entry, ...entries],
      events: events,
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'level': level.index,
    'growthProgress': growthProgress,
    'heatUpdatedAt': heatUpdatedAt.toUtc().toIso8601String(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'events': events.map((event) => event.toJson()).toList(),
  };

  factory Interest.fromJson(
    Map<String, dynamic> json, {
    required DateTime now,
    bool legacy = false,
  }) {
    final title = json['title'] as String;
    if (title.trim().isEmpty) {
      throw const FormatException('관심사 이름이 비어 있습니다.');
    }
    final entries = (json['entries'] as List<dynamic>)
        .map((entry) => DiaryEntry.fromJson(entry as Map<String, dynamic>))
        .toList();
    final FireLevel level;
    final DateTime anchor;
    if (legacy) {
      level = switch (json['level']) {
        'ember' => FireLevel.faintEmber,
        'steady' => FireLevel.smallFire,
        _ => throw const FormatException('잘못된 불 상태입니다.'),
      };
      anchor = entries.isEmpty
          ? now
          : entries
                .map((entry) => entry.createdAt)
                .reduce((a, b) => a.isAfter(b) ? a : b);
    } else {
      final value = json['level'];
      if (value is! int || value < 0 || value > 5) {
        throw const FormatException('잘못된 불 단계입니다.');
      }
      level = FireLevel.values[value];
      anchor = DateTime.parse(json['heatUpdatedAt'] as String);
    }
    final progress = json['growthProgress'] ?? 0;
    final progressLimit = level.logsForNextLevel;
    if (progress is! int ||
        progress < 0 ||
        (progressLimit == 0 ? progress != 0 : progress >= progressLimit)) {
      throw const FormatException('잘못된 장작 진행도입니다.');
    }
    return Interest(
      id: json['id'] as String,
      title: title,
      level: level,
      growthProgress: progress,
      heatUpdatedAt: anchor,
      entries: entries,
      events: (json['events'] as List<dynamic>? ?? [])
          .map((event) => FireEvent.fromJson(event as Map<String, dynamic>))
          .toList(),
    );
  }
}

class DiaryStore {
  DiaryStore({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
    DateTime Function()? now,
  }) : _read = read ?? _readPreferences,
       _write = write ?? _writePreferences,
       _now = now ?? DateTime.now;

  // Keep the original storage key so existing installations retain their diary.
  static const _storageKey = 'jangjak.diary.v1';
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;
  final DateTime Function() _now;

  DateTime get now => _now();

  static Future<String?> _readPreferences() =>
      SharedPreferencesAsync().getString(_storageKey);

  static Future<void> _writePreferences(String value) =>
      SharedPreferencesAsync().setString(_storageKey, value);

  Future<List<Interest>> load() async {
    final raw = await _read();
    final timestamp = now;
    if (raw == null) {
      final initial = [
        Interest(id: 'books', title: '책 읽기', heatUpdatedAt: timestamp),
        Interest(id: 'guitar', title: '기타 치기', heatUpdatedAt: timestamp),
        Interest(id: 'running', title: '달리기', heatUpdatedAt: timestamp),
      ];
      // Save the first anchor once; reopening must not reset the cooling clock.
      await save(initial);
      return initial;
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final version = decoded['version'];
    if (version != 1 && version != 2 && version != 3 && version != 4) {
      throw const FormatException('지원하지 않는 기록 형식입니다.');
    }
    final interests = (decoded['interests'] as List<dynamic>)
        .map(
          (item) => Interest.fromJson(
            item as Map<String, dynamic>,
            now: timestamp,
            legacy: version == 1,
          ),
        )
        .toList();
    if (interests.isEmpty && version == 1) {
      throw const FormatException('관심사를 불러오지 못했습니다.');
    }
    if (version != 4) await save(interests);
    return interests;
  }

  Future<void> save(List<Interest> interests) => _write(
    jsonEncode({
      'version': 4,
      'interests': interests.map((interest) => interest.toJson()).toList(),
    }),
  );
}
