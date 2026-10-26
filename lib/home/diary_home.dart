import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diary/diary_store.dart';
import '../theme/diary_theme.dart';
import 'diary_sheets.dart';
import 'home_widgets.dart';
import 'animated_fireplace.dart';

class DiaryHome extends StatefulWidget {
  const DiaryHome({super.key, required this.store});
  final DiaryStore store;

  @override
  State<DiaryHome> createState() => _DiaryHomeState();
}

class _DiaryHomeState extends State<DiaryHome> with WidgetsBindingObserver {
  List<Interest>? _interests;
  bool _loadFailed = false;
  int _selected = 1;
  late DateTime _now;
  Timer? _clockTimer;
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
      if (_appActive) _refreshClock();
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
      _selected = interests.isEmpty ? 0 : math.min(1, interests.length - 1);
      _pager = PageController(
        initialPage: _selected,
        viewportFraction: 282 / 393,
      );
      setState(() {
        _interests = interests;
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
        if (_interests!.any(
          (item) => item.title.toLowerCase() == title.toLowerCase(),
        )) {
          throw const FormatException('이미 피워둔 불이에요. 다른 이름을 적어주세요.');
        }
        final updated = [
          ..._interests!,
          Interest(
            id: widget.store.now.microsecondsSinceEpoch.toString(),
            title: title,
            heatUpdatedAt: widget.store.now,
          ),
        ];
        await widget.store.save(updated);
        if (!mounted) return;
        setState(() => _interests = updated);
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
          final updated = _interests!
              .map(
                (item) => item.id == current.id ? item.withEntry(entry) : item,
              )
              .toList();
          await widget.store.save(updated);
          if (mounted) {
            setState(() {
              _interests = updated;
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

  Future<void> _goTo(int index) => _pager.animateToPage(
    index,
    duration: const Duration(milliseconds: 350),
    curve: Curves.easeOutCubic,
  );

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
        Tooltip(
          message: '새 불 만들기',
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: _newFire,
              customBorder: const CircleBorder(),
              child: Container(
                width: 44 * scale,
                height: 44 * scale,
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
                    child: GestureDetector(
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
                                            index == _selected && _appActive,
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
    return Column(
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
        SizedBox(height: bottom),
      ],
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
