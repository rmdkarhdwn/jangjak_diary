String entryDateLabel(DateTime date) {
  final local = date.toLocal();
  return '${local.year}년 ${local.month}월 ${local.day}일 · '
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}
