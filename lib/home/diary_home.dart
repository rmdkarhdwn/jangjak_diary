import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diary/diary_store.dart';
import '../theme/diary_theme.dart';
import '../relationships/relationship_screen.dart';
import 'diary_sheets.dart';
import 'home_widgets.dart';
import 'animated_fireplace.dart';
import 'category_overview.dart';
import 'fire_actions_dialog.dart';
import 'archived_fire_sheet.dart';

class DiaryHome extends StatefulWidget {
  const DiaryHome({super.key, required this.store});
  final DiaryStore store;

  @override
  State<DiaryHome> createState() => _DiaryHomeState();
}

class _DiaryHomeState extends State<DiaryHome> with WidgetsBindingObserver {
  List<Interest>? _allInterests;
  List<Interest>? get _interests =>
      _allInterests?.where((item) => !item.isArchived).toList();
  bool _loadFailed = false;
  int _selected = 1;
  late DateTime _now;
  Timer? _clockTimer;
  bool _overviewOpen = false;
  bool _deleteOpen = false;
  double _verticalTravel = 0;
  double _wheelTravel = 0;
  bool _appActive = true;
  PageController _pager = PageController(
    initialPage: 1,
    viewportFraction: 282 / 393,
  );

  bool get _isNewFire => _selected == _interests!.length;
  Interest? get _current => _isNewFire ? null : _interests![_selected];

  @override
  void initState() {
    super.initState();
    _now = widget.store.now;
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_appActive && !_overviewOpen) _refreshClock();
    });
    _load();
  }

  void _refreshClock() {
    if (mounted) setState(() => _now = widget.store.now);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _appActive = state == AppLifecycleState.resumed;
      if (_appActive) _now = widget.store.now;
    });
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final interests = await widget.store.load();
      if (!mounted) return;
      _pager.dispose();
      final active = interests.where((item) => !item.isArchived).toList();
      _selected = active.isEmpty ? 0 : math.min(1, active.length - 1);
      _pager = PageController(
        initialPage: _selected,
        viewportFraction: 282 / 393,
      );
      setState(() {
        _allInterests = interests;
        _now = widget.store.now;
      });
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _pager.dispose();
    super.dispose();
  }

  Future<T?> _sheet<T>(Widget child) => showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66333040),
    constraints: const BoxConstraints(maxWidth: 460),
    builder: (_) => child,
  );

  Future<void> _newFire() => _sheet<void>(
    DiaryComposer(
      title: '새 불을 피워볼까요?',
      description: '요즘 마음이 가는 것, 무엇이든 좋아요.',
      hint: '예: 산책하기, 그림 그리기',
      submitLabel: '불 피우기',
      onSave: (title) async {
        if (_allInterests!.any(
          (item) => item.title.toLowerCase() == title.toLowerCase(),
        )) {
          throw const FormatException('이미 있거나 보관한 불이에요. 전체 분류에서 확인해 주세요.');
        }
        final updated = [
          ..._allInterests!,
          Interest(
            id: widget.store.now.microsecondsSinceEpoch.toString(),
            title: title,
            heatUpdatedAt: widget.store.now,
          ),
        ];
        await widget.store.save(updated);
        if (!mounted) return;
        setState(() => _allInterests = updated);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_pager.hasClients) return;
        await _pager.animateToPage(
          _interests!.length - 1,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      },
    ),
  );

  Future<void> _addEntry() async {
    final current = _current;
    if (current == null) {
      await _newFire();
      return;
    }
    await _sheet<void>(
      DiaryComposer(
        title: '오늘의 장작',
        description: '${current.title}에 어떤 마음을 더해볼까요?',
        hint: '작은 시도도, 잠깐 스친 마음도 괜찮아요.',
        submitLabel: '마음 남기기',
        multiline: true,
        onSave: (text) async {
          final entry = DiaryEntry(text: text, createdAt: widget.store.now);
          final updated = _allInterests!
              .map(
                (item) => item.id == current.id ? item.withEntry(entry) : item,
              )
              .toList();
          await widget.store.save(updated);
          if (mounted) {
            setState(() {
              _allInterests = updated;
              _now = widget.store.now;
            });
          }
        },
      ),
    );
  }

  Future<void> _history() async {
    final current = _current;
    if (current == null) return;
    final addEntry = await _sheet<bool>(EntryHistory(interest: current));
    if (addEntry == true && mounted) await _addEntry();
  }

  Future<void> _saveMutation(List<Interest> updated, {String? selectId}) async {
    final currentId = selectId ?? _current?.id;
    final active = updated.where((item) => !item.isArchived).toList();
    final preserved = active.indexWhere((item) => item.id == currentId);
    final nextIndex = currentId == null
        ? active.length
        : preserved >= 0
        ? preserved
        : math.min(_selected, math.max(0, active.length - 1));
    await widget.store.save(updated);
    if (!mounted) return;
    setState(() {
      _allInterests = updated;
      _selected = nextIndex;
      _now = widget.store.now;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _pager.hasClients) _pager.jumpToPage(nextIndex);
  }

  Future<List<Interest>> _rekindle(Interest interest) async {
    final updated = _allInterests!
        .map(
          (item) =>
              item.id == interest.id ? item.rekindle(widget.store.now) : item,
        )
        .toList();
    await _saveMutation(updated, selectId: interest.id);
    return updated;
  }

  Future<List<Interest>?> _manageInterest(Interest interest) async {
    if (_deleteOpen || !_allInterests!.any((item) => item.id == interest.id)) {
      return null;
    }
    _deleteOpen = true;
    try {
      final changed =
          await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => FireActionsDialog(
              interest: interest,
              permanentOnly: interest.isArchived,
              onArchive: (reason, note) => _saveMutation(
                _allInterests!
                    .map(
                      (item) => item.id == interest.id
                          ? item.archive(
                              widget.store.now,
                              reason: reason,
                              note: note,
                            )
                          : item,
                    )
                    .toList(),
              ),
              onDelete: () async {
                await _saveMutation(
                  _allInterests!
                      .where((item) => item.id != interest.id)
                      .toList(),
                );
              },
            ),
          ) ??
          false;
      return changed ? List.of(_allInterests!) : null;
    } finally {
      _deleteOpen = false;
    }
  }

  Future<void> _goTo(int index) => _pager.animateToPage(
    index,
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOutCubic,
  );

  Future<void> _showRelationships() async {
    if (_overviewOpen || _interests == null) return;
    setState(() => _overviewOpen = true);
    final id = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => RelationshipScreen(
          interests: _allInterests!,
          clock: () => widget.store.now,
        ),
      ),
    );
    if (!mounted) return;
    setState(() {
      _overviewOpen = false;
      _now = widget.store.now;
    });
    final index = _interests!.indexWhere((item) => item.id == id);
    if (index >= 0) {
      await WidgetsBinding.instance.endOfFrame;
      if (mounted && _pager.hasClients) await _goTo(index);
    } else if (id != null) {
      final matches = _allInterests!.where((item) => item.id == id);
      if (matches.isNotEmpty && matches.first.isArchived) {
        await _sheet<List<Interest>>(
          ArchivedFireSheet(
            interest: matches.first,
            onRekindle: _rekindle,
            onDelete: _manageInterest,
          ),
        );
      }
    }
  }

  Future<void> _showCategories() async {
    if (_overviewOpen || _interests == null) return;
    setState(() => _overviewOpen = true);
    String? result;
    try {
      result = await Navigator.of(context).push<String>(
        PageRouteBuilder(
          transitionDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 420),
          reverseTransitionDuration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 320),
          pageBuilder: (_, animation, secondaryAnimation) => CategoryOverview(
            interests: _allInterests!,
            selectedId: _current?.id,
            clock: () => widget.store.now,
            onManage: _manageInterest,
            onRekindle: _rekindle,
          ),
          transitionsBuilder: (_, animation, secondaryAnimation, child) =>
              SlideTransition(
                position: Tween(begin: const Offset(0, 1), end: Offset.zero)
                    .animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      ),
                    ),
                child: child,
              ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _overviewOpen = false;
          _now = widget.store.now;
        });
      }
    }
    if (!mounted) return;
    if (result == CategoryOverview.createNew) {
      await _newFire();
      return;
    }
    final index = result == null
        ? _selected
        : _interests!.indexWhere((item) => item.id == result);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _pager.hasClients && index >= 0) await _goTo(index);
  }

  void _handleWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || _overviewOpen) return;
    _wheelTravel = (_wheelTravel + event.scrollDelta.dy).clamp(0, 100);
    if (_wheelTravel >= 24) {
      _wheelTravel = 0;
      _showCategories();
    }
  }

  Widget _header(double scale) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 28 * scale),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            DesignIcon('brand_flame', width: 15 * scale, height: 20 * scale),
            SizedBox(width: 8 * scale),
            Text(
              '장작일기',
              style: TextStyle(
                color: DiaryTheme.cream,
                fontSize: 13 * scale,
                height: 22 / 13,
                fontWeight: FontWeight.w500,
                letterSpacing: .3,
              ),
            ),
          ],
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: _showRelationships,
              style: TextButton.styleFrom(
                foregroundColor: DiaryTheme.cream,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                side: const BorderSide(color: Color(0x2BEFE7DF)),
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.hub_outlined, size: 16),
              label: const Text('관계', style: TextStyle(fontSize: 11)),
            ),
            SizedBox(width: 10 * scale),
            Tooltip(
              message: '새 불 만들기',
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: _newFire,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: math.max(44, 44 * scale),
                    height: math.max(44, 44 * scale),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x2BEFE7DF)),
                    ),
                    child: Center(
                      child: DesignIcon(
                        'plus',
                        width: 18 * scale,
                        height: 18 * scale,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _heading(double scale, {bool compact = false}) {
    final title = _current?.title ?? '새로운 불';
    final level = _current?.levelAt(_now);
    final status = _current == null
        ? '마음이 가는 것을 찾아보세요'
        : '${level!.index}단계 · ${level.label}';
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 28 * scale),
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              title,
              key: ValueKey(title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DiaryTheme.title.copyWith(
                fontSize: (compact ? 26 : 32) * scale,
              ),
            ),
          ),
          SizedBox(height: (compact ? 4 : 9) * scale),
          SizedBox(
            height: 24 * scale,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DesignIcon('status_dot', width: 4 * scale, height: 4 * scale),
                SizedBox(width: 7 * scale),
                Flexible(
                  child: Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: DiaryTheme.cream.withValues(alpha: .87),
                      fontSize: 13 * scale,
                      height: 22 / 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!compact)
            Text(
              level?.description ?? '작은 관심도 좋은 시작이에요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: DiaryTheme.cream.withValues(alpha: .58),
                fontSize: 11 * scale,
                height: 18 / 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _carousel(double scale) => SizedBox(
    height: 344 * scale,
    child: ClipRect(
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: EdgeInsets.only(top: 4 * scale),
            child: Opacity(
              opacity: ((_current?.levelAt(_now).index ?? 0) / 3).clamp(0, 1),
              child: DesignIcon(
                'ambient_glow',
                width: 295 * scale,
                height: 332 * scale,
              ),
            ),
          ),
          ScrollConfiguration(
            behavior: const MaterialScrollBehavior().copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: PageView.builder(
              key: const Key('interest-carousel'),
              controller: _pager,
              itemCount: _interests!.length + 1,
              onPageChanged: (index) => setState(() => _selected = index),
              itemBuilder: (context, index) => AnimatedBuilder(
                animation: _pager,
                builder: (context, child) {
                  final page =
                      _pager.hasClients && _pager.position.haveDimensions
                      ? _pager.page ?? _selected.toDouble()
                      : _selected.toDouble();
                  final distance = (page - index).abs().clamp(0.0, 1.0);
                  final interest = index < _interests!.length
                      ? _interests![index]
                      : null;
                  return Semantics(
                    label: interest?.title ?? '새 불 만들기',
                    button: true,
                    hint: interest == null ? null : '길게 눌러 보관 또는 완전 삭제',
                    child: GestureDetector(
                      onLongPress: interest == null
                          ? null
                          : () => _manageInterest(interest),
                      onTap: () {
                        if (index != _selected) {
                          _goTo(index);
                        } else if (interest == null) {
                          _newFire();
                        } else {
                          _history();
                        }
                      },
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: OverflowBox(
                          alignment: Alignment.topCenter,
                          minWidth: 300 * scale,
                          maxWidth: 300 * scale,
                          minHeight: 320 * scale,
                          maxHeight: 320 * scale,
                          child: Transform.translate(
                            offset: Offset(0, 30 * scale * distance),
                            child: Transform.scale(
                              scale: 1 - .13 * distance,
                              alignment: Alignment.topCenter,
                              child: Opacity(
                                opacity: 1 - .62 * distance,
                                child: interest == null
                                    ? FireplaceArt(
                                        name: 'fireplace_shell',
                                        scale: scale,
                                      )
                                    : AnimatedFireplace(
                                        key: ValueKey(interest.id),
                                        level: interest.levelAt(_now),
                                        scale: scale,
                                        animate:
                                            index == _selected &&
                                            !_overviewOpen &&
                                            _appActive,
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _content(BoxConstraints constraints) {
    final scale = constraints.maxWidth / 393;
    final compact = constraints.maxHeight < 700;
    final padding = MediaQuery.paddingOf(context);
    final top = math.max((compact ? 16 : 72) * scale, padding.top + 12);
    final bottom = math.max(8 * scale, padding.bottom + 8);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: _handleWheel,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (_) => _verticalTravel = 0,
        onVerticalDragUpdate: (event) => _verticalTravel += event.delta.dy,
        onVerticalDragEnd: (event) {
          if (_verticalTravel < -64 || (event.primaryVelocity ?? 0) < -400) {
            _showCategories();
          }
        },
        child: Column(
          children: [
            SizedBox(height: top),
            _header(scale),
            SizedBox(height: (compact ? 14 : 45) * scale),
            _heading(scale, compact: compact),
            SizedBox(height: (compact ? 8 : 27) * scale),
            Expanded(
              child: LayoutBuilder(
                builder: (_, space) {
                  final artScale = math.min(scale, space.maxHeight / 344);
                  return Center(child: _carousel(artScale));
                },
              ),
            ),
            InterestIndicator(
              count: _interests!.length + 1,
              selected: _selected,
              scale: scale,
              onSelected: _goTo,
            ),
            SizedBox(height: (compact ? 6 : 12) * scale),
            if (!compact) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  _isNewFire ? '나만의 작은 불을 하나 더 피워보세요.' : '오늘은 어떤 마음을 더해볼까요?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: DiaryTheme.cream.withValues(alpha: .76),
                    fontSize: 12 * scale,
                    height: 20 / 12,
                  ),
                ),
              ),
              SizedBox(height: 10 * scale),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                HomeAction(
                  label: _isNewFire ? '불 피우기' : '장작 넣기',
                  onTap: _addEntry,
                  primary: true,
                  scale: scale,
                ),
                if (!_isNewFire) ...[
                  SizedBox(width: 28 * scale),
                  HomeAction(label: '기록 보기', onTap: _history, scale: scale),
                ],
              ],
            ),
            SizedBox(height: 4 * scale),
            TextButton.icon(
              onPressed: _showCategories,
              style: TextButton.styleFrom(
                foregroundColor: DiaryTheme.cream.withValues(alpha: .65),
                minimumSize: const Size(0, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              label: const Text('전체 분류 보기', style: TextStyle(fontSize: 11)),
            ),
            SizedBox(height: bottom),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light.copyWith(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
    child: Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(gradient: DiaryTheme.background),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _loadFailed
                ? Padding(
                    padding: const EdgeInsets.all(36),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '기록을 불러오지 못했어요',
                          style: TextStyle(
                            color: DiaryTheme.cream,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '잠시 후 다시 시도해 주세요.',
                          style: TextStyle(color: DiaryTheme.cream),
                        ),
                        const SizedBox(height: 24),
                        OutlinedButton(
                          onPressed: _load,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: DiaryTheme.cream,
                          ),
                          child: const Text('다시 불러오기'),
                        ),
                      ],
                    ),
                  )
                : _interests == null
                ? const Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DiaryTheme.cream,
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (_, constraints) => _content(constraints),
                  ),
          ),
        ),
      ),
    ),
  );
}
