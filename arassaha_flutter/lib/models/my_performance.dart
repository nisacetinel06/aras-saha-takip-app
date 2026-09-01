import 'work_order.dart';

/// GET /api/dashboard/my-performance'ın "Aylık Tamamlama Trendi" satırı —
/// Raporlar'daki (Modül 14) MonthlyFaultCount ile AYNI "year_month" alan
/// adlandırması ve kısa Türkçe ay etiketi mantığı (bkz. models/report.dart)
/// tutarlılık için birebir korundu.
class MonthlyCompletionCount {
  final String yearMonth;
  final int completedCount;

  MonthlyCompletionCount({
    required this.yearMonth,
    required this.completedCount,
  });

  String get shortLabel {
    final month = int.tryParse(yearMonth.split('-').last) ?? 1;
    return _trendMonthLabels[(month - 1).clamp(0, 11)];
  }

  factory MonthlyCompletionCount.fromJson(Map<String, dynamic> json) {
    return MonthlyCompletionCount(
      yearMonth: json['year_month'] as String,
      completedCount: json['completed_count'] as int? ?? 0,
    );
  }
}

const _trendMonthLabels = [
  'Oca',
  'Şub',
  'Mar',
  'Nis',
  'May',
  'Haz',
  'Tem',
  'Ağu',
  'Eyl',
  'Eki',
  'Kas',
  'Ara',
];

/// GET /api/dashboard/my-performance yanıtının Dart karşılığı — Modül 16
/// "Performansım". Yeni bir veri kaynağı DEĞİL, DashboardSummary'nin
/// (Modül 2) yeniden sorguladığı work_orders/isg_reports üzerinden, yalnızca
/// giriş yapmış kullanıcıya özel bir görünüm.
class MyPerformanceSummary {
  final int completedThisMonth;
  final int totalCompletedAllTime;

  /// Hiç tamamlanmış iş yoksa backend `null` döner (sahte bir "0 saat"
  /// göstermek yerine dürüstçe "veri yok" — bkz. routes/dashboard.js).
  final double? avgResolutionHours;
  final Map<WorkOrderPriority, int> priorityBreakdown;
  final int isgReportsCount;
  final List<MonthlyCompletionCount> monthlyTrend;

  MyPerformanceSummary({
    required this.completedThisMonth,
    required this.totalCompletedAllTime,
    required this.avgResolutionHours,
    required this.priorityBreakdown,
    required this.isgReportsCount,
    required this.monthlyTrend,
  });

  factory MyPerformanceSummary.fromJson(Map<String, dynamic> json) {
    final priorityJson =
        json['priority_breakdown'] as Map<String, dynamic>? ?? {};

    return MyPerformanceSummary(
      completedThisMonth: json['completed_this_month'] as int? ?? 0,
      totalCompletedAllTime: json['total_completed_all_time'] as int? ?? 0,
      avgResolutionHours: (json['avg_resolution_hours'] as num?)?.toDouble(),
      priorityBreakdown: {
        for (final priority in WorkOrderPriority.values)
          priority: (priorityJson[priority.toJson()] as num?)?.toInt() ?? 0,
      },
      isgReportsCount: json['isg_reports_count'] as int? ?? 0,
      monthlyTrend: (json['monthly_trend'] as List<dynamic>? ?? [])
          .map(
            (e) => MonthlyCompletionCount.fromJson(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
