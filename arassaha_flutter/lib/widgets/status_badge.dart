import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

export '../theme/app_colors.dart'
    show statusColor, onStatusColor, priorityColor, onPriorityColor;

/// Ortak dolu (solid) pill rozet görünümü.
class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _Pill({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
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
