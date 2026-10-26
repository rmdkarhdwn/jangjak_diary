import 'package:flutter/material.dart';

import '../diary/diary_store.dart';
import '../theme/diary_theme.dart';
import 'home_widgets.dart';
import 'entry_date.dart';

class DiaryComposer extends StatefulWidget {
  const DiaryComposer({
    super.key,
    required this.title,
    required this.description,
    required this.hint,
    required this.submitLabel,
    required this.onSave,
    this.multiline = false,
  });

  final String title;
  final String description;
  final String hint;
  final String submitLabel;
  final Future<void> Function(String) onSave;
  final bool multiline;

  @override
  State<DiaryComposer> createState() => _DiaryComposerState();
}

class _DiaryComposerState extends State<DiaryComposer> {
  final _text = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _text.text.trim();
    if (_saving || value.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(value);
      if (mounted) Navigator.pop(context);
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '저장하지 못했어요. 작성한 마음은 그대로 있으니 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: SheetSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeading(title: widget.title, description: widget.description),
          const SizedBox(height: 24),
          TextField(
            controller: _text,
            autofocus: true,
            enabled: !_saving,
            minLines: widget.multiline ? 4 : 1,
            maxLines: widget.multiline ? 7 : 1,
            maxLength: widget.multiline ? 2000 : 30,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: widget.multiline
                ? TextInputAction.newline
                : TextInputAction.done,
            onSubmitted: widget.multiline ? null : (_) => _save(),
            onChanged: (_) => setState(() => _error = null),
            decoration: InputDecoration(
              hintText: widget.hint,
              errorText: _error,
              errorMaxLines: 3,
              counterStyle: TextStyle(
                color: DiaryTheme.ink.withValues(alpha: .45),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving || _text.text.trim().isEmpty ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DiaryTheme.cream,
                    ),
                  )
                : Text(widget.submitLabel),
          ),
        ],
      ),
    ),
  );
}

class EntryHistory extends StatelessWidget {
  const EntryHistory({super.key, required this.interest});

  final Interest interest;

  @override
  Widget build(BuildContext context) => SheetSurface(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SheetHeading(
          title: '${interest.title}의 기록',
          description: '작은 마음들이 모여, 나만의 온기가 돼요.',
        ),
        const SizedBox(height: 28),
        if (interest.entries.isEmpty && interest.events.isEmpty) ...[
          Center(
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: DiaryTheme.ink,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: DesignIcon('brand_flame', width: 15, height: 20),
                  ),
                ),
                const SizedBox(height: 20),
                const Text('아직 쌓인 장작이 없어요', style: TextStyle(fontSize: 15)),
                const SizedBox(height: 8),
                Text(
                  '오늘의 첫 마음을 남겨볼까요?',
                  style: TextStyle(
                    fontSize: 13,
                    color: DiaryTheme.ink.withValues(alpha: .65),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('장작 넣기'),
          ),
        ] else ...[
          Text(
            '${interest.entries.length}개의 장작',
            style: TextStyle(
              fontSize: 12,
              color: DiaryTheme.ink.withValues(alpha: .6),
            ),
          ),
          const SizedBox(height: 14),
          InterestTimeline(interest: interest),
        ],
      ],
    ),
  );
}

class InterestTimeline extends StatelessWidget {
  const InterestTimeline({super.key, required this.interest});
  final Interest interest;

  @override
  Widget build(BuildContext context) {
    final items = <({DateTime at, DiaryEntry? entry, FireEvent? event})>[
      for (final entry in interest.entries)
        (at: entry.createdAt, entry: entry, event: null),
      for (final event in interest.events)
        (at: event.occurredAt, entry: null, event: event),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return Column(
      children: [
        for (final item in items)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: item.event == null ? .4 : .2,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: DiaryTheme.ink.withValues(alpha: .08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entryDateLabel(item.at),
                  style: TextStyle(
                    fontSize: 11,
                    color: DiaryTheme.ink.withValues(alpha: .6),
                  ),
                ),
                const SizedBox(height: 10),
                if (item.entry != null)
                  SelectableText(
                    item.entry!.text,
                    style: const TextStyle(fontSize: 14, height: 1.8),
                  )
                else ...[
                  Row(
                    children: [
                      Icon(
                        item.event!.kind == FireEventKind.archived
                            ? Icons.inventory_2_outlined
                            : Icons.local_fire_department_outlined,
                        size: 17,
                        color: DiaryTheme.ink,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.event!.kind == FireEventKind.archived
                              ? '불을 보관했어요'
                              : '다시 불을 붙였어요',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (item.event!.reason != null &&
                      item.event!.reason != ArchiveReason.custom) ...[
                    const SizedBox(height: 8),
                    Text(
                      item.event!.reason!.label,
                      style: const TextStyle(fontSize: 12, height: 1.7),
                    ),
                  ],
                  if (item.event!.note != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      item.event!.note!,
                      style: const TextStyle(fontSize: 13, height: 1.8),
                    ),
                  ],
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class SheetSurface extends StatelessWidget {
  const SheetSurface({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope(
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .88,
        ),
        decoration: const BoxDecoration(
          color: DiaryTheme.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 34,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(
                      color: DiaryTheme.ink.withValues(alpha: .2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class SheetHeading extends StatelessWidget {
  const SheetHeading({
    super.key,
    required this.title,
    required this.description,
  });
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: DiaryTheme.title.copyWith(
                fontSize: 24,
                color: DiaryTheme.ink,
              ),
            ),
          ),
          IconButton(
            tooltip: '닫기',
            onPressed: () => Navigator.maybePop(context),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        description,
        style: TextStyle(
          fontSize: 13,
          height: 1.7,
          color: DiaryTheme.ink.withValues(alpha: .65),
        ),
      ),
    ],
  );
}
