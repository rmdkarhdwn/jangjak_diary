import 'package:flutter/material.dart';

import '../diary/diary_store.dart';
import '../theme/diary_theme.dart';
import 'diary_sheets.dart';

class ArchivedFireSheet extends StatefulWidget {
  const ArchivedFireSheet({
    super.key,
    required this.interest,
    required this.onRekindle,
    required this.onDelete,
    required this.onEditEntry,
  });
  final Interest interest;
  final Future<List<Interest>> Function(Interest) onRekindle;
  final Future<List<Interest>?> Function(Interest) onDelete;
  final EditDiaryEntry onEditEntry;

  @override
  State<ArchivedFireSheet> createState() => _ArchivedFireSheetState();
}

class _ArchivedFireSheetState extends State<ArchivedFireSheet> {
  late Interest _interest = widget.interest;
  bool _busy = false;
  bool _restoring = false;
  String? _error;

  Future<void> _perform({required bool restore}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _restoring = restore;
      _error = null;
    });
    try {
      final updated = restore
          ? await widget.onRekindle(_interest)
          : await widget.onDelete(_interest);
      if (mounted && updated != null) Navigator.pop(context, updated);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '변경하지 못했어요. 기록은 그대로 있으니 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(DiaryEntry entry) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await showDiaryEntryEditor(
        context,
        entry: entry,
        onSave: (text) async {
          final updated = await widget.onEditEntry(_interest.id, entry, text);
          if (mounted) setState(() => _interest = updated);
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: SheetSurface(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetHeading(
            title: '${_interest.title}의 기록',
            description: '꺼진 불도 과거에 실제로 타고 있었어요.\n이곳에 남은 장작은 언제든 다시 꺼내볼 수 있어요.',
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () => _perform(restore: true),
            child: _busy && _restoring
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DiaryTheme.cream,
                    ),
                  )
                : const Text('다시 불붙이기'),
          ),
          const SizedBox(height: 6),
          Center(
            child: TextButton(
              onPressed: _busy ? null : () => _perform(restore: false),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF9C574F),
              ),
              child: const Text('완전히 삭제하기', style: TextStyle(fontSize: 12)),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFF9C574F), fontSize: 12),
              ),
            ),
          const SizedBox(height: 20),
          Text(
            '${_interest.entries.length}개의 장작 · 불의 타임라인',
            style: TextStyle(
              color: DiaryTheme.ink.withValues(alpha: .65),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          InterestTimeline(
            interest: _interest,
            onEditEntry: _busy ? null : _edit,
          ),
        ],
      ),
    ),
  );
}
