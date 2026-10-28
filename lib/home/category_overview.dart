import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../diary/diary_store.dart';
import '../theme/diary_theme.dart';
import 'animated_fireplace.dart';
import 'home_widgets.dart';
import 'archived_fire_sheet.dart';
import 'diary_sheets.dart';

class CategoryOverview extends StatefulWidget {
  const CategoryOverview({
    super.key,
    required this.interests,
    required this.selectedId,
    required this.clock,
    required this.onManage,
    required this.onRekindle,
    required this.onEditEntry,
  });

  static const createNew = '__new_interest__';
  final List<Interest> interests;
  final String? selectedId;
  final DateTime Function() clock;
  final Future<List<Interest>?> Function(Interest) onManage;
  final Future<List<Interest>> Function(Interest) onRekindle;
  final EditDiaryEntry onEditEntry;

  @override
  State<CategoryOverview> createState() => _CategoryOverviewState();
}

class _CategoryOverviewState extends State<CategoryOverview>
    with WidgetsBindingObserver {
  late DateTime _now;
  late final List<Interest> _interests = List.of(widget.interests);
  late String? _selectedId = widget.selectedId;
  Timer? _timer;
  final _tabs = PageController();
  final _scrolls = [ScrollController(), ScrollController()];
  ScrollController get _scroll => _scrolls[_showArchived ? 1 : 0];
  int? _pullPointer;
  Offset _pullTravel = Offset.zero;
  double _wheelTravel = 0;
  bool _returning = false;
  bool _showArchived = false;

  void _replaceInterests(List<Interest> updated) {
    final previousIndex = _interests
        .where((item) => !item.isArchived)
        .toList()
        .indexWhere((item) => item.id == _selectedId);
    setState(() {
      _interests
        ..clear()
        ..addAll(updated);
      final active = _interests.where((item) => !item.isArchived).toList();
      if (_selectedId != null &&
          !active.any((item) => item.id == _selectedId)) {
        _selectedId = active.isEmpty
            ? null
            : active[math.min(math.max(0, previousIndex), active.length - 1)]
                  .id;
      }
    });
  }

  Future<void> _manage(Interest interest) async {
    final updated = await widget.onManage(interest);
    if (mounted && updated != null) _replaceInterests(updated);
  }

  Future<void> _openArchived(Interest interest) async {
    final updated = await showModalBottomSheet<List<Interest>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 460),
      builder: (_) => ArchivedFireSheet(
        interest: interest,
        onRekindle: widget.onRekindle,
        onDelete: widget.onManage,
        onEditEntry: (id, entry, text) async {
          final edited = await widget.onEditEntry(id, entry, text);
          if (mounted) {
            _replaceInterests(
              _interests.map((item) => item.id == id ? edited : item).toList(),
            );
          }
          return edited;
        },
      ),
    );
    if (!mounted || updated == null) return;
    _replaceInterests(updated);
    if (updated.any((item) => item.id == interest.id && !item.isArchived)) {
      Navigator.pop(context, interest.id);
    }
  }

  void _changeTab(bool archived) {
    if (!_tabs.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _tabs.jumpToPage(archived ? 1 : 0);
      return;
    }
    _tabs.animateToPage(
      archived ? 1 : 0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

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
    _tabs.dispose();
    for (final scroll in _scrolls) {
      scroll.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  child: PageView.builder(
                    key: const Key('category-tabs'),
                    controller: _tabs,
                    itemCount: 2,
                    onPageChanged: (index) {
                      setState(() => _showArchived = index == 1);
                      _pullPointer = null;
                      _wheelTravel = 0;
                    },
                    itemBuilder: (context, index) =>
                        _buildPage(context, archived: index == 1),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, {required bool archived}) {
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final visible = _interests
        .where((item) => item.isArchived == archived)
        .toList();
    if (archived) {
      visible.sort(
        (a, b) =>
            b.lastArchive!.occurredAt.compareTo(a.lastArchive!.occurredAt),
      );
    }
    return KeyedSubtree(
      key: PageStorageKey(
        archived ? 'archived-category-scroll' : 'active-category-scroll',
      ),
      child: CustomScrollView(
        key: archived
            ? const Key('archived-category-page')
            : const Key('category-page'),
        controller: _scrolls[archived ? 1 : 0],
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const DesignIcon('brand_flame', width: 15, height: 20),
                      const SizedBox(width: 8),
                      const Text(
                        '장작일기',
                        style: TextStyle(color: DiaryTheme.cream, fontSize: 13),
                      ),
                      const Spacer(),
                      IconButton.outlined(
                        tooltip: '내 불로 돌아가기',
                        onPressed: () => Navigator.pop(context),
                        style: IconButton.styleFrom(
                          foregroundColor: DiaryTheme.cream,
                          side: const BorderSide(color: Color(0x40F4EDE1)),
                        ),
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 28),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Expanded(
                        child: Text('전체 분류', style: DiaryTheme.title),
                      ),
                      Text(
                        '${visible.length}개의 불',
                        style: TextStyle(
                          color: DiaryTheme.cream.withValues(alpha: .68),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    archived
                        ? '꺼진 불도 과거에 실제로 타고 있었어요.\n남긴 장작과 내려놓은 이유를 다시 꺼내봐요.'
                        : '마음이 머무는 곳을 한눈에.\n불을 누르면 그 관심사로 돌아가요.',
                    style: TextStyle(
                      color: DiaryTheme.cream.withValues(alpha: .7),
                      fontSize: 12,
                      height: 1.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _CategoryTab(
                        label: '피워둔 불',
                        selected: !archived,
                        onTap: () => _changeTab(false),
                      ),
                      const SizedBox(width: 8),
                      _CategoryTab(
                        label: '보관한 불',
                        selected: archived,
                        onTap: () => _changeTab(true),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (archived && visible.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  '아직 보관한 불이 없어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: DiaryTheme.cream, fontSize: 13),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: textScale > 1.35 ? 1 : 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 14,
                  mainAxisExtent: 238 + math.max(0, textScale - 1) * 72,
                ),
                itemCount: visible.length + (archived ? 0 : 1),
                itemBuilder: (context, index) {
                  if (index == visible.length) {
                    return _NewCategory(
                      onTap: () =>
                          Navigator.pop(context, CategoryOverview.createNew),
                    );
                  }
                  final interest = visible[index];
                  return _CategoryCard(
                    interest: interest,
                    level: interest.levelAt(_now),
                    selected: interest.id == _selectedId,
                    onTap: () => interest.isArchived
                        ? _openArchived(interest)
                        : Navigator.pop(context, interest.id),
                    onLongPress: () => _manage(interest),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
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
      foregroundColor: DiaryTheme.cream.withValues(alpha: selected ? 1 : .6),
      backgroundColor: DiaryTheme.cream.withValues(alpha: selected ? .12 : .02),
      side: BorderSide(
        color: DiaryTheme.cream.withValues(alpha: selected ? .4 : .15),
      ),
      shape: const StadiumBorder(),
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    child: Text(label, style: const TextStyle(fontSize: 12)),
  );
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.interest,
    required this.level,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });
  final Interest interest;
  final FireLevel level;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  String get _status {
    if (!interest.isArchived) return '${level.index}단계 · ${level.label}';
    final archived = interest.lastArchive!;
    return archived.reason == ArchiveReason.custom
        ? (archived.note ?? '잠시 내려둔 불')
        : (archived.reason?.label ?? '잠시 내려둔 불');
  }

  @override
  Widget build(BuildContext context) => _TileSurface(
    selected: selected,
    onTap: onTap,
    onLongPress: onLongPress,
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
    this.onLongPress,
  });
  final VoidCallback onTap;
  final Widget child;
  final bool selected;
  final VoidCallback? onLongPress;

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
    child: InkWell(onTap: onTap, onLongPress: onLongPress, child: child),
  );
}
