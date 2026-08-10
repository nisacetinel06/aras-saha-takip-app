import 'package:flutter/material.dart';
import '../theme/app_text_styles.dart';

/// "Yeniden Eskiye / Eskiden Yeniye" sıralama kontrolü — Ana Sayfa'daki
/// "Tamamlanan İş Emirlerim" önizlemesi ([CompletedWorkOrdersSection]) ile
/// tam liste ekranı ([CompletedWorkOrdersScreen]) AYNI kontrolü kullanır,
/// iki ayrı kopya tutulmaz. Provider'a bağımlı DEĞİLDİR — `descending` +
/// `onChanged` ile herhangi bir liste için yeniden kullanılabilir.
class SortDirectionControl extends StatelessWidget {
  final bool descending;
  final ValueChanged<bool> onChanged;

  const SortDirectionControl({
    super.key,
    required this.descending,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<bool>(
      tooltip: 'Sıralama',
      onSelected: onChanged,
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: true,
          checked: descending,
          child: const Text('Yeniden Eskiye'),
        ),
        CheckedPopupMenuItem(
          value: false,
          checked: !descending,
          child: const Text('Eskiden Yeniye'),
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sort, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            descending ? 'Yeniden Eskiye' : 'Eskiden Yeniye',
            style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
