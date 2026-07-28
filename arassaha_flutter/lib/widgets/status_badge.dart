import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../theme/app_theme.dart';

/// Statü/öncelik renkleri tek yerden tanımlanır; Dashboard'daki grafikler de
/// (pasta/çubuk) aynı renkleri kullanır ki rozetlerle birebir tutarlı olsun.
/// Mümkün olduğunda tema renklerinden (colorScheme) beslenir; "yolda"/"sahada"
/// gibi marka paletinde karşılığı olmayan iki ton için sabit vurgu rengi
/// kullanılır (AppTheme.accentOrange/accentPurple).
Color statusColor(BuildContext context, WorkOrderStatus status) {
  final scheme = Theme.of(context).colorScheme;
  switch (status) {
    case WorkOrderStatus.acik:
      return scheme.primary;
    case WorkOrderStatus.yolda:
      return AppTheme.accentOrange;
    case WorkOrderStatus.sahada:
      return AppTheme.accentPurple;
    case WorkOrderStatus.cozuldu:
      return scheme.secondary;
  }
}

Color onStatusColor(BuildContext context, WorkOrderStatus status) {
  // Turuncu zemin üzerinde beyaz yazı düşük kontrastta kalıyor; o yüzden
  // "yolda" durumunda koyu metin kullanılır.
  if (status == WorkOrderStatus.yolda) return const Color(0xFF3A2500);
  return Colors.white;
}

Color priorityColor(BuildContext context, WorkOrderPriority priority) {
  final scheme = Theme.of(context).colorScheme;
  switch (priority) {
    case WorkOrderPriority.acil:
      return scheme.error;
    case WorkOrderPriority.normal:
      return scheme.surfaceContainerHighest;
    case WorkOrderPriority.dusuk:
      return scheme.surfaceContainerHigh;
  }
}

/// Öncelik rozetlerindeki nötr (gri) tonlar bir çubuk grafikte görünürlüğü
/// düşürür; grafik için ayrı, her zaman ayırt edilebilir bir palet kullanılır.
Color priorityChartColor(BuildContext context, WorkOrderPriority priority) {
  final scheme = Theme.of(context).colorScheme;
  switch (priority) {
    case WorkOrderPriority.acil:
      return scheme.error;
    case WorkOrderPriority.normal:
      return AppTheme.accentOrange;
    case WorkOrderPriority.dusuk:
      return scheme.outline;
  }
}

Color onPriorityColor(BuildContext context, WorkOrderPriority priority) {
  final scheme = Theme.of(context).colorScheme;
  switch (priority) {
    case WorkOrderPriority.acil:
      return scheme.onError;
    case WorkOrderPriority.normal:
    case WorkOrderPriority.dusuk:
      return scheme.onSurfaceVariant;
  }
}

/// Ortak dolu (solid) pill rozet görünümü.
class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _Pill({required this.label, required this.color, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  final WorkOrderStatus status;

  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return _Pill(
      label: status.label,
      color: statusColor(context, status),
      textColor: onStatusColor(context, status),
    );
  }
}

class PriorityBadge extends StatelessWidget {
  final WorkOrderPriority priority;

  const PriorityBadge({super.key, required this.priority});

  @override
  Widget build(BuildContext context) {
    return _Pill(
      label: priority.label,
      color: priorityColor(context, priority),
      textColor: onPriorityColor(context, priority),
    );
  }
}
