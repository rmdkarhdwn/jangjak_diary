import 'package:flutter/material.dart';

import '../diary/diary_store.dart';
import '../theme/diary_theme.dart';

enum _ActionStage { choice, archive, permanent }

class FireActionsDialog extends StatefulWidget {
  const FireActionsDialog({
    super.key,
    required this.interest,
    required this.onDelete,
    this.onArchive,
    this.permanentOnly = false,
  });
  final Interest interest;
  final Future<void> Function() onDelete;
  final Future<void> Function(ArchiveReason?, String?)? onArchive;
  final bool permanentOnly;

  @override
  State<FireActionsDialog> createState() => _FireActionsDialogState();
}

class _FireActionsDialogState extends State<FireActionsDialog> {
  late _ActionStage _stage = widget.permanentOnly
      ? _ActionStage.permanent
      : _ActionStage.choice;
  final _note = TextEditingController();
  ArchiveReason? _reason;
  bool _saving = false;
  String? _error;
  bool get _hasNote =>
      _reason == ArchiveReason.custom || _reason == ArchiveReason.transitioned;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_stage == _ActionStage.archive) {
        await widget.onArchive!(_reason, _hasNote ? _note.text : null);
      } else {
        await widget.onDelete();
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _stage == _ActionStage.archive
              ? '보관하지 못했어요. 입력한 이유는 그대로 있으니 다시 시도해 주세요.'
              : '삭제하지 못했어요. 잠시 후 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _changeStage(_ActionStage stage) => setState(() {
    _stage = stage;
    _error = null;
  });

  @override
  Widget build(BuildContext context) {
    final choosing = _stage == _ActionStage.choice;
    final archiving = _stage == _ActionStage.archive;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        backgroundColor: DiaryTheme.cream,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          choosing
              ? '이 불을 어떻게 내려놓을까요?'
              : archiving
              ? '이 불을 왜 내려놓나요?'
              : '이 불을 완전히 삭제할까요?',
          style: DiaryTheme.title.copyWith(fontSize: 21, color: DiaryTheme.ink),
        ),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.interest.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                if (choosing) ...[
                  const Text(
                    '꺼진 불도 과거에 실제로 타고 있었으니까요.\n보관하면 장작 기록과 연결의 흔적이 남아요.',
                    style: TextStyle(fontSize: 12, height: 1.8),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    autofocus: true,
                    onPressed: () => _changeStage(_ActionStage.archive),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 17),
                        const SizedBox(width: 8),
                        const Text('보관하기'),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: DiaryTheme.cream.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '추천',
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _changeStage(_ActionStage.permanent),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF9C574F),
                        minimumSize: const Size(0, 46),
                      ),
                      child: const Text('완전히 삭제하기'),
                    ),
                  ),
                ] else if (archiving) ...[
                  Text(
                    '선택 사항입니다.',
                    style: TextStyle(
                      color: DiaryTheme.ink.withValues(alpha: .65),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final reason in ArchiveReason.values)
                        ChoiceChip(
                          label: Text(
                            reason.label,
                            style: const TextStyle(fontSize: 11),
                          ),
                          selected: _reason == reason,
                          onSelected: _saving
                              ? null
                              : (selected) => setState(
                                  () => _reason = selected ? reason : null,
                                ),
                          showCheckmark: false,
                        ),
                    ],
                  ),
                  if (_hasNote) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _note,
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 4,
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText: _reason == ArchiveReason.transitioned
                            ? '어떤 관심사로 이어졌나요? (선택 사항)'
                            : '자유롭게 적어주세요. (선택 사항)',
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text(
                    '기록은 그대로 남고, 언제든 다시 불붙일 수 있어요.',
                    style: TextStyle(fontSize: 11, height: 1.8),
                  ),
                ] else ...[
                  const Text(
                    '관련 장작 기록과 AI 관계 분석도 함께 삭제됩니다.',
                    style: TextStyle(fontSize: 13, height: 1.8),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '장작 ${widget.interest.entries.length}개와 보관·재시작 이력이 모두 지워져요.\n완전히 삭제한 내용은 되돌릴 수 없어요.',
                    style: TextStyle(
                      color: DiaryTheme.ink.withValues(alpha: .7),
                      fontSize: 12,
                      height: 1.8,
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFF9C574F),
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          if (!choosing && !widget.permanentOnly)
            TextButton(
              onPressed: _saving
                  ? null
                  : () => _changeStage(_ActionStage.choice),
              child: const Text('뒤로'),
            ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          if (!choosing)
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: archiving
                    ? DiaryTheme.ink
                    : const Color(0xFF9C574F),
                minimumSize: const Size(96, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DiaryTheme.cream,
                      ),
                    )
                  : Text(archiving ? '보관하기' : '완전히 삭제하기'),
            ),
        ],
      ),
    );
  }
}
