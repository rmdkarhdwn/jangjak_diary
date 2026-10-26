import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diary/diary_store.dart';
import '../theme/diary_theme.dart';
import 'animated_fireplace.dart';
import 'home_widgets.dart';

class CategoryOverview extends StatefulWidget {
  const CategoryOverview({
    super.key,
    required this.interests,
    required this.selectedId,
    required this.clock,
  });

  static const createNew = '__new_interest__';
  final List<Interest> interests;
  final String? selectedId;
  final DateTime Function() clock;

  @override
  State<CategoryOverview> createState() => _CategoryOverviewState();
}

class _CategoryOverviewState extends State<CategoryOverview>
    with WidgetsBindingObserver {
  late DateTime _now;
  late final List<Interest> _interests = List.of(widget.interests);
  Timer? _timer;
  final _scroll = ScrollController();
  int? _pullPointer;
  Offset _pullTravel = Offset.zero;
  double _wheelTravel = 0;
  bool _returning = false;
  bool get _atTop =>
      _scroll.hasClients &&
      _scroll.position.pixels <= _scroll.position.minScrollExtent + .5;

  void _returnHome() {
    if (_returning || ModalRoute.of(context)?.isCurrent != true) return;
    _returning = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        Navigator.pop(context);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _startPull(PointerDownEvent event) {
    _pullTravel = Offset.zero;
    _pullPointer = _atTop && event.buttons == kPrimaryButton
        ? event.pointer
        : null;
  }

  void _movePull(PointerMoveEvent event) {
    if (event.pointer == _pullPointer) _pullTravel += event.delta;
  }

  void _endPull(PointerUpEvent event) {
    if (event.pointer != _pullPointer) return;
    _pullPointer = null;
    if (_atTop &&
        _pullTravel.dy >= 72 &&
        _pullTravel.dy > _pullTravel.dx.abs() * 1.2) {
      _returnHome();
    }
  }

  void _handleWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!_atTop || event.scrollDelta.dy >= 0) {
      _wheelTravel = 0;
      return;
    }
    _wheelTravel -= event.scrollDelta.dy;
    if (_wheelTravel >= 24) _returnHome();
  }

  @override
  void initState() {
    super.initState();
    _now = widget.clock();
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
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final visible = _interests;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: DiaryTheme.background),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _startPull,
                  onPointerMove: _movePull,
                  onPointerUp: _endPull,
                  onPointerCancel: (_) => _pullPointer = null,
                  onPointerSignal: _handleWheel,
                  child: CustomScrollView(
                    key: const Key('category-page'),
                    controller: _scroll,
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const DesignIcon(
                                    'brand_flame',
                                    width: 15,
                                    height: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text(
                                    '장작일기',
                                    style: TextStyle(
                                      color: DiaryTheme.cream,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton.outlined(
                                    tooltip: '내 불로 돌아가기',
                                    onPressed: () => Navigator.pop(context),
                                    style: IconButton.styleFrom(
                                      foregroundColor: DiaryTheme.cream,
                                      side: const BorderSide(
                                        color: Color(0x40F4EDE1),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.keyboard_arrow_up_rounded,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Expanded(
                                    child: Text(
                                      '전체 분류',
                                      style: DiaryTheme.title,
                                    ),
                                  ),
                                  Text(
                                    '${visible.length}개의 불',
                                    style: TextStyle(
                                      color: DiaryTheme.cream.withValues(
                                        alpha: .68,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '마음이 머무는 곳을 한눈에.\n불을 누르면 그 관심사로 돌아가요.',
                                style: TextStyle(
                                  color: DiaryTheme.cream.withValues(alpha: .7),
                                  fontSize: 12,
                                  height: 1.8,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                        sliver: SliverGrid.builder(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: textScale > 1.35 ? 1 : 2,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 14,
                                mainAxisExtent:
                                    238 + math.max(0, textScale - 1) * 72,
                              ),
                          itemCount: visible.length + 1,
                          itemBuilder: (context, index) {
                            if (index == visible.length) {
                              return _NewCategory(
                                onTap: () => Navigator.pop(
                                  context,
                                  CategoryOverview.createNew,
                                ),
                              );
                            }
                            final interest = visible[index];
                            return _CategoryCard(
                              interest: interest,
                              level: interest.levelAt(_now),
                              selected: interest.id == widget.selectedId,
                              onTap: () => Navigator.pop(context, interest.id),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.interest,
    required this.level,
    required this.selected,
    required this.onTap,
  });
  final Interest interest;
  final FireLevel level;
  final bool selected;
  final VoidCallback onTap;

  String get _status => '${level.index}단계 · ${level.label}';

  @override
  Widget build(BuildContext context) => _TileSurface(
    selected: selected,
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            interest.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: DiaryTheme.cream,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            height: 32 * (MediaQuery.textScalerOf(context).scale(12) / 12),
            child: Text(
              _status,
              maxLines: 2,
              style: TextStyle(
                color: DiaryTheme.cream.withValues(alpha: .7),
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (_, constraints) => Center(
                child: AnimatedFireplace(
                  level: level,
                  animate: false,
                  scale: math.min(
                    constraints.maxWidth / 300,
                    constraints.maxHeight / 320,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${interest.entries.length}개의 장작',
                  style: TextStyle(
                    color: DiaryTheme.cream.withValues(alpha: .7),
                    fontSize: 11,
                  ),
                ),
              ),
              Icon(
                Icons.north_east_rounded,
                size: 16,
                color: DiaryTheme.cream.withValues(alpha: .65),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _NewCategory extends StatelessWidget {
  const _NewCategory({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _TileSurface(
    onTap: onTap,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0x40F4EDE1)),
          ),
          child: const Center(child: DesignIcon('plus', width: 18, height: 18)),
        ),
        const SizedBox(height: 18),
        const Text(
          '새 불 피우기',
          style: TextStyle(color: DiaryTheme.cream, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Text(
          '새로운 관심사 추가',
          style: TextStyle(
            color: DiaryTheme.cream.withValues(alpha: .6),
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

class _TileSurface extends StatelessWidget {
  const _TileSurface({
    required this.onTap,
    required this.child,
    this.selected = false,
  });
  final VoidCallback onTap;
  final Widget child;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: DiaryTheme.cream.withValues(alpha: selected ? .12 : .045),
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: BorderSide(
        color: DiaryTheme.cream.withValues(alpha: selected ? .6 : .18),
      ),
    ),
    child: InkWell(onTap: onTap, child: child),
  );
}
