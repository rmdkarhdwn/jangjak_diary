import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diary/diary_store.dart';
import '../theme/diary_theme.dart';
import 'connection_sheet.dart';
import 'relationship_data.dart';
import 'relationship_graph.dart';
import 'relation_api.dart';

class RelationshipScreen extends StatefulWidget {
  const RelationshipScreen({
    super.key,
    required this.interests,
    required this.clock,
    this.api,
  });
  final List<Interest> interests;
  final DateTime Function() clock;
  final RelationApi? api;

  @override
  State<RelationshipScreen> createState() => _RelationshipScreenState();
}

class _RelationshipScreenState extends State<RelationshipScreen>
    with WidgetsBindingObserver {
  final _graph = GlobalKey<RelationshipGraphState>();
  late RelationshipMap _mine = RelationshipMap(
    interests: widget.interests,
    connections: const [],
  );
  late final _api = widget.api ?? RelationApi();
  bool _loading = false;
  bool _analyzed = false;
  RelationApiException? _error;
  late final _example = exampleRelationshipMap(widget.clock());
  late DateTime _now = widget.clock();
  bool _showExample = false;
  String? _selectedId;
  Timer? _timer;
  RelationshipMap get _map => _showExample ? _example : _mine;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  void _refresh() {
    if (mounted) setState(() => _now = widget.clock());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    if (widget.api == null) _api.close();
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _analyze() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _analyzed = false;
      _error = null;
      _selectedId = null;
      _mine = RelationshipMap(
        interests: widget.interests,
        connections: const [],
      );
    });
    try {
      final result = await _api.analyze(widget.interests);
      if (mounted) {
        setState(() {
          _mine = result;
          _analyzed = true;
        });
      }
    } on RelationApiException catch (error) {
      if (mounted) setState(() => _error = error);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = const RelationApiException(
            'UNEXPECTED',
            '관계 분석을 마치지 못했어요. 다시 시도해 주세요.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _analysisPanel() => Padding(
    padding: const EdgeInsets.fromLTRB(28, 8, 28, 4),
    child: Row(
      children: [
        if (_loading) ...[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFFE3BD95),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _loading
                      ? '관계를 분석하고 있어요…'
                      : _error != null
                      ? '관계 분석에 실패했어요'
                      : _analyzed
                      ? '관계 분석을 마쳤어요'
                      : '기록으로 불 사이의 관계를 찾아봐요.',
                  style: const TextStyle(color: DiaryTheme.cream, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  _error != null
                      ? '${_error!.message} (${_error!.code})'
                      : _loading
                      ? '잠시만 기다려 주세요. 최대 55초 정도 걸릴 수 있어요.'
                      : _analyzed && _mine.connections.isEmpty
                      ? '이번 분석에서는 충분한 근거가 있는 연결을 찾지 못했어요.'
                      : '분석을 누르면 최근 장작 원문을 AI 분석 서버로 보내요. 관심사별 최대 30개, 관심사 최대 12개예요.',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFB9ADBD),
                    fontSize: 10,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: _loading ? null : _analyze,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFFE3BD95),
            disabledForegroundColor: const Color(0xFF8F879D),
          ),
          child: Text(
            _loading
                ? '분석 중'
                : _error != null
                ? '다시 시도'
                : _analyzed
                ? '다시 분석'
                : '관계 분석하기',
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ],
    ),
  );

  Future<void> _openConnection(InterestConnection connection) async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0xB313121D),
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => ConnectionSheet(map: _map, connection: connection),
    );
    if (mounted && id != null && !_showExample) Navigator.pop(context, id);
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF242330), Color(0xFF353141), Color(0xFF302D3D)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 780),
              child: LayoutBuilder(
                builder: (context, box) {
                  final compact = box.maxHeight < 650;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                        child: Row(
                          children: [
                            IconButton.outlined(
                              tooltip: '내 불로 돌아가기',
                              onPressed: () => Navigator.pop(context),
                              style: IconButton.styleFrom(
                                foregroundColor: DiaryTheme.cream,
                                side: const BorderSide(
                                  color: Color(0x33F4EDE1),
                                ),
                              ),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 18,
                              ),
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.blur_on_rounded,
                              color: Color(0xFFE0BE9A),
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '나의 작은 별자리',
                              style: TextStyle(
                                color: Color(0xFFB9ADBD),
                                fontSize: 11,
                                letterSpacing: .5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          28,
                          compact ? 8 : 20,
                          28,
                          compact ? 10 : 18,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '관계도',
                              style: DiaryTheme.title.copyWith(
                                fontSize: compact ? 28 : 32,
                              ),
                            ),
                            if (!compact) ...[
                              const SizedBox(height: 6),
                              const Text(
                                '따로 피운 불들이, 서로의 온기가 되어.',
                                style: TextStyle(
                                  color: Color(0xFFB9ADBD),
                                  fontSize: 12,
                                  height: 1.7,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Row(
                          children: [
                            _ModePill(
                              label: '내 관심사',
                              selected: !_showExample,
                              onTap: () => setState(() {
                                _showExample = false;
                                _selectedId = null;
                              }),
                            ),
                            const SizedBox(width: 8),
                            _ModePill(
                              label: '예시 관계도',
                              selected: _showExample,
                              onTap: () => setState(() {
                                _showExample = true;
                                _selectedId = null;
                              }),
                            ),
                            const Spacer(),
                            if (!compact)
                              IconButton(
                                tooltip: '전체 배치로 돌아가기',
                                onPressed: () {
                                  _graph.currentState?.resetView();
                                  setState(() => _selectedId = null);
                                },
                                icon: const Icon(
                                  Icons.center_focus_weak_rounded,
                                  size: 20,
                                  color: Color(0xFFB9ADBD),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!_showExample) _analysisPanel(),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: RepaintBoundary(
                                child: RelationshipGraph(
                                  key: _graph,
                                  map: _map,
                                  now: _now,
                                  selectedId: _selectedId,
                                  onSelect: (id) =>
                                      setState(() => _selectedId = id),
                                  onConnection: _openConnection,
                                ),
                              ),
                            ),
                            Positioned(
                              top: 14,
                              left: 28,
                              child: IgnorePointer(
                                child: Text(
                                  '${_map.interests.length}개의 불  ·  ${_map.connections.length}개의 연결',
                                  style: const TextStyle(
                                    color: Color(0xFF8F879D),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 4,
                              right: 22,
                              child: Row(
                                children: [
                                  _GraphControl(
                                    tooltip: '관계도 축소',
                                    icon: Icons.remove_rounded,
                                    onTap: () =>
                                        _graph.currentState?.zoom(1 / 1.2),
                                  ),
                                  _GraphControl(
                                    tooltip: '관계도 확대',
                                    icon: Icons.add_rounded,
                                    onTap: () => _graph.currentState?.zoom(1.2),
                                  ),
                                  if (compact)
                                    _GraphControl(
                                      tooltip: '전체 배치로 돌아가기',
                                      icon: Icons.center_focus_weak_rounded,
                                      onTap: () =>
                                          _graph.currentState?.resetView(),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                        child: _selectionPanel(compact),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(28, 12, 28, 16),
                        child: Text(
                          _showExample
                              ? '예시 관심사와 기록으로 둘러보는 중이에요.'
                              : 'AI가 기록을 바탕으로 제안한 관계이며, 확정적인 판단은 아니에요.',
                          style: const TextStyle(
                            color: Color(0xFF8F879D),
                            fontSize: 10,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _selectionPanel(bool compact) {
    final interest = _selectedId == null
        ? null
        : _map.interests.firstWhere((item) => item.id == _selectedId);
    final edges = interest == null
        ? <InterestConnection>[]
        : _map.connectionsFor(interest.id).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0x14F4EDE1)),
      ),
      child: interest == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.hub_outlined,
                      size: 16,
                      color: Color(0xFFDDB991),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        !_showExample && _loading
                            ? '분석 결과를 기다리고 있어요'
                            : !_showExample && _error != null
                            ? '분석 결과를 불러오지 못했어요'
                            : !_showExample && !_analyzed
                            ? '아직 관계를 분석하지 않았어요'
                            : _map.connections.isEmpty
                            ? '아직 발견된 연결이 없어요'
                            : '서로 닿아 있는 마음을 찾아보세요',
                        style: const TextStyle(
                          color: DiaryTheme.cream,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _map.connections.isEmpty
                      ? '각 불의 기록을 더 남기거나 예시 관계도를 둘러볼 수 있어요.'
                      : '불을 누르면 가까운 관계가, 선을 누르면 연결의 이유가 보여요.',
                  style: const TextStyle(
                    color: Color(0xFFB9ADBD),
                    fontSize: 10,
                    height: 1.7,
                  ),
                ),
                if (!compact && _map.connections.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Row(
                    children: [
                      Icon(Icons.circle, size: 7, color: Color(0xFFE8BD8D)),
                      SizedBox(width: 5),
                      Text(
                        '불의 세기 = 노드 크기',
                        style: TextStyle(color: Color(0xFF8F879D), fontSize: 9),
                      ),
                      Spacer(),
                      SizedBox(
                        width: 22,
                        child: Divider(color: Color(0xFFD8B18B), thickness: 2),
                      ),
                      SizedBox(width: 5),
                      Text(
                        '밀접도 = 선의 굵기',
                        style: TextStyle(color: Color(0xFF8F879D), fontSize: 9),
                      ),
                    ],
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${interest.title} · ${interest.isArchived ? '보관한 불' : interest.levelAt(_now).label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: DiaryTheme.cream,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!_showExample)
                      TextButton(
                        onPressed: () => Navigator.pop(context, interest.id),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFE3BD95),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          interest.isArchived ? '기록 보기 ↗' : '이 불로 가기 ↗',
                          style: const TextStyle(fontSize: 10),
                        ),
                      ),
                    IconButton(
                      tooltip: '선택 해제',
                      onPressed: () => setState(() => _selectedId = null),
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Color(0xFFB9ADBD),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                if (edges.isEmpty)
                  const Text(
                    '아직 직접 연결된 기록이 없어요.',
                    style: TextStyle(color: Color(0xFFB9ADBD), fontSize: 11),
                  )
                else
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: edges.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, index) {
                        final edge = edges[index];
                        final other = edge.left.id == interest.id
                            ? edge.right
                            : edge.left;
                        return TextButton.icon(
                          onPressed: () => _openConnection(edge),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFE3BD95),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            side: const BorderSide(color: Color(0x26E3BD95)),
                          ),
                          icon: const Icon(Icons.link_rounded, size: 13),
                          label: Text(
                            other.title,
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: selected
          ? const Color(0xFFE9C29C)
          : const Color(0xFF9A90A7),
      backgroundColor: selected ? const Color(0x13E9C29C) : Colors.transparent,
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      side: BorderSide(
        color: selected ? const Color(0x48E9C29C) : const Color(0x1AF4EDE1),
      ),
      shape: const StadiumBorder(),
    ),
    child: Text(label, style: const TextStyle(fontSize: 11)),
  );
}

class _GraphControl extends StatelessWidget {
  const _GraphControl({
    required this.tooltip,
    required this.icon,
    required this.onTap,
  });
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    color: const Color(0xFFB9ADBD),
    icon: Icon(icon, size: 18),
  );
}
