import 'work_order.dart';

/// Dashboard'daki "Son Aktiviteler" listesindeki tek bir kayıt.
class RecentActivityItem {
  final int id;
  final String title;
  final WorkOrderStatus status;
  final DateTime updatedAt;

  RecentActivityItem({
    required this.id,
    required this.title,
    required this.status,
    required this.updatedAt,
  });

  factory RecentActivityItem.fromJson(Map<String, dynamic> json) {
    return RecentActivityItem(
      id: json['id'] as int,
      title: json['title'] as String,
      status: WorkOrderStatus.fromJson(json['status'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

/// GET /api/dashboard/summary yanıtının Dart karşılığı.
class DashboardSummary {
  final int openCount;
  final int resolvedTodayCount;
  final double avgResolutionHours;
  final Map<WorkOrderStatus, int> statusBreakdown;
  final Map<WorkOrderPriority, int> priorityBreakdown;
  final List<RecentActivityItem> recentActivity;

  DashboardSummary({
    required this.openCount,
    required this.resolvedTodayCount,
    required this.avgResolutionHours,
    required this.statusBreakdown,
    required this.priorityBreakdown,
    required this.recentActivity,
  });

  factory DashboardSummary.fromJson(Map<String, dynamic> json) {
    final statusJson = json['status_breakdown'] as Map<String, dynamic>? ?? {};
    final priorityJson = json['priority_breakdown'] as Map<String, dynamic>? ?? {};

    return DashboardSummary(
      openCount: json['open_count'] as int? ?? 0,
      resolvedTodayCount: json['resolved_today_count'] as int? ?? 0,
      avgResolutionHours: (json['avg_resolution_hours'] as num?)?.toDouble() ?? 0.0,
      statusBreakdown: {
        for (final status in WorkOrderStatus.values)
          status: (statusJson[status.toJson()] as num?)?.toInt() ?? 0,
      },
      priorityBreakdown: {
        for (final priority in WorkOrderPriority.values)
          priority: (priorityJson[priority.toJson()] as num?)?.toInt() ?? 0,
      },
      recentActivity: (json['recent_activity'] as List<dynamic>? ?? [])
          .map((e) => RecentActivityItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
