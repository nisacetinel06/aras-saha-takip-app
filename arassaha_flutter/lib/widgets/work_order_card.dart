import 'package:flutter/material.dart';
import '../models/work_order.dart';
import 'app_card.dart';
import 'status_badge.dart';

/// "2 saat önce" gibi basit bir göreceli zaman metni üretir.
String formatRelativeTime(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);

  if (diff.inMinutes < 1) return 'Az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dakika önce';
  if (diff.inHours < 24) return '${diff.inHours} saat önce';
  if (diff.inDays < 30) return '${diff.inDays} gün önce';

  final months = (diff.inDays / 30).floor();
  return '$months ay önce';
}

class WorkOrderCard extends StatelessWidget {
  final WorkOrder workOrder;
  final VoidCallback onTap;

  const WorkOrderCard({super.key, required this.workOrder, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: AppCard(
        onTap: onTap,
        statusStripeColor: statusColor(context, workOrder.status),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    workOrder.title,
                    style: Theme.of(context).textTheme.headlineSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                PriorityBadge(priority: workOrder.priority),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on_outlined, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    workOrder.locationName,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                StatusBadge(status: workOrder.status),
                Text(
                  formatRelativeTime(workOrder.createdAt),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
            Divider(height: 24, color: scheme.outlineVariant.withValues(alpha: 0.5)),
            Row(
              children: [
                Icon(Icons.person_outline, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    workOrder.assignedUser?.name ?? 'Atanmamış',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Text(
                  'Detaylar',
                  style: TextStyle(color: scheme.primary, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                Icon(Icons.arrow_forward, size: 16, color: scheme.primary),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
