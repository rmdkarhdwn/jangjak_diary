import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum FireLevel { ember, steady }

class DiaryEntry {
  const DiaryEntry({required this.text, required this.createdAt});

  final String text;
  final DateTime createdAt;

  Map<String, Object> toJson() => {
    'text': text,
    'createdAt': createdAt.toIso8601String(),
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
    this.level = FireLevel.ember,
    this.entries = const [],
  });

  final String id;
  final String title;
  final FireLevel level;
  final List<DiaryEntry> entries;

  Interest withEntry(DiaryEntry entry) => Interest(
    id: id,
    title: title,
    level: FireLevel.steady,
    entries: [entry, ...entries],
  );

  Map<String, Object> toJson() => {
    'id': id,
    'title': title,
    'level': level.name,
    'entries': entries.map((entry) => entry.toJson()).toList(),
  };

  factory Interest.fromJson(Map<String, dynamic> json) {
    final title = json['title'] as String;
    if (title.trim().isEmpty) {
      throw const FormatException('관심사 이름이 비어 있습니다.');
    }
    return Interest(
      id: json['id'] as String,
      title: title,
      level: FireLevel.values.byName(json['level'] as String),
      entries: (json['entries'] as List<dynamic>)
          .map((entry) => DiaryEntry.fromJson(entry as Map<String, dynamic>))
          .toList(),
    );
  }
}

class DiaryStore {
  DiaryStore({
    Future<String?> Function()? read,
    Future<void> Function(String)? write,
  }) : _read = read ?? _readPreferences,
       _write = write ?? _writePreferences;

  static const _storageKey = 'jangjak.diary.v1';
  final Future<String?> Function() _read;
  final Future<void> Function(String) _write;

  static Future<String?> _readPreferences() =>
      SharedPreferencesAsync().getString(_storageKey);

  static Future<void> _writePreferences(String value) =>
      SharedPreferencesAsync().setString(_storageKey, value);

  Future<List<Interest>> load() async {
    final raw = await _read();
    if (raw == null) {
      return const [
        Interest(id: 'books', title: '책 읽기'),
        Interest(id: 'guitar', title: '기타 치기', level: FireLevel.steady),
        Interest(id: 'running', title: '달리기'),
      ];
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['version'] != 1) {
      throw const FormatException('지원하지 않는 기록 형식입니다.');
    }
    final interests = (decoded['interests'] as List<dynamic>)
        .map((item) => Interest.fromJson(item as Map<String, dynamic>))
        .toList();
    if (interests.isEmpty) {
      throw const FormatException('관심사를 불러오지 못했습니다.');
    }
    return interests;
  }

  Future<void> save(List<Interest> interests) => _write(
    jsonEncode({
      'version': 1,
      'interests': interests.map((interest) => interest.toJson()).toList(),
    }),
  );
}
