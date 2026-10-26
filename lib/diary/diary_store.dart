import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum FireLevel {
  ash('재', '잠시 쉬어가는 중'),
  faintEmber('작은 불씨', '거의 꺼진 상태'),
  revivedEmber('살아난 불씨', '관심이 다시 생김'),
  smallFire('작은 불', '꾸준히 생각나는 상태'),
  largeFire('큰 불', '현재 꽤 몰입 중'),
  blazing('활활 타는 불', '최상위 관심 상태');

  const FireLevel(this.label, this.description);
  final String label;
  final String description;
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
    this.level = FireLevel.faintEmber,
    this.entries = const [],
  });

  static const coolingInterval = Duration(days: 3);
  final String id;
  final String title;
  // Level at heatUpdatedAt; elapsed cooling is calculated without mutating it.
  final FireLevel level;
  final DateTime heatUpdatedAt;
  final List<DiaryEntry> entries;
  FireLevel levelAt(DateTime now) {
    final elapsed = now.difference(heatUpdatedAt);
    if (elapsed.isNegative) return level;
    final steps = elapsed.inMicroseconds ~/ coolingInterval.inMicroseconds;
    final cooled = level.index - steps;
    return FireLevel.values[cooled < 0 ? 0 : cooled];
  }

  Interest withEntry(DiaryEntry entry) {
    return Interest(
      id: id,
      title: title,
      level: FireLevel.values[(levelAt(entry.createdAt).index + 1).clamp(0, 5)],
      heatUpdatedAt: entry.createdAt,
      entries: [entry, ...entries],
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'level': level.index,
    'heatUpdatedAt': heatUpdatedAt.toUtc().toIso8601String(),
    'entries': entries.map((entry) => entry.toJson()).toList(),
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
    return Interest(
      id: json['id'] as String,
      title: title,
      level: level,
      heatUpdatedAt: anchor,
      entries: entries,
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
        Interest(
          id: 'guitar',
          title: '기타 치기',
          level: FireLevel.smallFire,
          heatUpdatedAt: timestamp,
        ),
        Interest(id: 'running', title: '달리기', heatUpdatedAt: timestamp),
      ];
      // Save the first anchor once; reopening must not reset the cooling clock.
      await save(initial);
      return initial;
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final version = decoded['version'];
    if (version != 1 && version != 2) {
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
    if (version == 1) await save(interests);
    return interests;
  }

  Future<void> save(List<Interest> interests) => _write(
    jsonEncode({
      'version': 2,
      'interests': interests.map((interest) => interest.toJson()).toList(),
    }),
  );
}
