import 'package:flutter/material.dart';

import '../home/entry_date.dart';
import '../theme/diary_theme.dart';
import 'relationship_data.dart';

class ConnectionSheet extends StatefulWidget {
  const ConnectionSheet({
    super.key,
    required this.map,
    required this.connection,
  });
  final RelationshipMap map;
  final InterestConnection connection;

  @override
  State<ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<ConnectionSheet> {
  late InterestConnection _current = widget.connection;
  final _previous = <InterestConnection>[];
  final _scroll = ScrollController();

  void _changeConnection(InterestConnection connection) {
    FocusScope.of(context).unfocus();
    setState(() => _current = connection);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.map
        .suggestionsFor(_current)
        .where((item) => item.id != _current.id)
        .toList();
    const soft = Color(0xFFBAB3C3);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF302E3D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: Color(0x33EDD6BC))),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          controller: _scroll,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 3,
                  decoration: BoxDecoration(
                    color: soft.withValues(alpha: .3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_previous.isNotEmpty)
                    IconButton(
                      tooltip: '이전 연결',
                      color: DiaryTheme.cream,
                      onPressed: () =>
                          _changeConnection(_previous.removeLast()),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    ),
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: const Color(0xFFE4B989).withValues(alpha: .9),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.map.isExample ? '예시 기록에서 찾은 연결' : 'AI가 기록에서 찾은 연결',
                      style: const TextStyle(color: soft, fontSize: 11),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    color: soft,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              Text(
                _current.themes.first,
                style: DiaryTheme.title.copyWith(fontSize: 24),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _NamePill(_current.left.title),
                  Icon(
                    _current.type == RelationType.transition
                        ? Icons.arrow_forward_rounded
                        : Icons.more_horiz_rounded,
                    color: Color(0xFFE3B98F),
                    size: 20,
                  ),
                  _NamePill(_current.right.title),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 26,
                    height: 2.5,
                    color: const Color(0xFFE3B98F),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _current.type == null
                        ? _current.closeness
                        : '밀접도 ${_current.strength}',
                    style: const TextStyle(
                      color: Color(0xFFE3B98F),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _current.explanation,
                style: const TextStyle(
                  color: DiaryTheme.cream,
                  fontSize: 13,
                  height: 1.9,
                ),
              ),
              for (final interest in [
                _current.left,
                _current.right,
              ].where((item) => item.isArchived))
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .035),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${interest.title} · 보관한 불',
                          style: const TextStyle(
                            color: Color(0xFFE3C09C),
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          interest.lastArchive!.reason?.label ??
                              '이유를 남기지 않고 보관했어요.',
                          style: const TextStyle(
                            color: soft,
                            fontSize: 11,
                            height: 1.7,
                          ),
                        ),
                        if (interest.lastArchive!.note != null)
                          Text(
                            interest.lastArchive!.note!,
                            style: const TextStyle(
                              color: DiaryTheme.cream,
                              fontSize: 12,
                              height: 1.8,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 26),
              const _SectionTitle('근거 기록', icon: Icons.format_quote_rounded),
              const SizedBox(height: 12),
              for (final evidence in _current.evidence)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .035),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .07),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              evidence.interest.title,
                              style: const TextStyle(
                                color: Color(0xFFE3C09C),
                                fontSize: 11,
                              ),
                            ),
                          ),
                          if (!widget.map.isExample)
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(context, evidence.interest.id),
                              style: TextButton.styleFrom(
                                foregroundColor: soft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                evidence.interest.isArchived
                                    ? '기록 보기 ↗'
                                    : '이 불로 가기 ↗',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        evidence.entry.text,
                        style: const TextStyle(
                          color: DiaryTheme.cream,
                          fontSize: 12,
                          height: 1.85,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        entryDateLabel(evidence.entry.createdAt),
                        style: TextStyle(
                          color: soft.withValues(alpha: .65),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              _SectionTitle(
                _current.suggestion == null ? '새로운 연결 제안' : '함께 해볼 행동',
                icon: Icons.add_link_rounded,
              ),
              const SizedBox(height: 8),
              Text(
                _current.suggestion ??
                    (suggestions.isEmpty
                        ? '새로운 공통점이 담긴 기록이 쌓이면, 다른 연결도 함께 살펴볼 수 있어요.'
                        : '이 두 불에서 조금 더 뻗어 나가 볼까요? 아직 펼치지 않은 공통점이에요.'),
                style: const TextStyle(color: soft, fontSize: 11, height: 1.8),
              ),
              const SizedBox(height: 12),
              for (final suggestion in suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: const Color(0x0FE3B98F),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        _previous.add(_current);
                        _changeConnection(suggestion);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.add_rounded,
                              size: 18,
                              color: Color(0xFFE3B98F),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    suggestion.label,
                                    style: const TextStyle(
                                      color: DiaryTheme.cream,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    suggestion.themes.first,
                                    style: const TextStyle(
                                      color: soft,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: soft,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text(
                widget.map.isExample
                    ? '이 화면의 관심사와 기록은 기능을 살펴보기 위한 예시입니다.'
                    : 'AI가 장작 원문을 바탕으로 제안한 연결이에요. 밀접도는 서버의 계산값이며 확률이나 확정적인 판단이 아니에요.',
                style: TextStyle(
                  color: soft.withValues(alpha: .65),
                  fontSize: 10,
                  height: 1.8,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NamePill extends StatelessWidget {
  const _NamePill(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0x33E3B98F)),
      borderRadius: BorderRadius.circular(24),
    ),
    child: Text(
      name,
      style: const TextStyle(color: DiaryTheme.cream, fontSize: 11),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.icon});
  final String title;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: const Color(0xFFE3C09C), size: 16),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          color: DiaryTheme.cream,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  );
}
