import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/equipment.dart';
import '../../models/meter_anomaly.dart';
import '../../providers/anomaly_provider.dart';
import '../../providers/equipment_provider.dart';
import '../../providers/maintenance_provider.dart';
import '../../providers/risk_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/maintenance_recommendation_card.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;
import '../work_order_detail_screen.dart';

/// Ekipman / Envanter (Modül 4) — ekipman detay ekranı.
///
/// Konum/kurulum/bakım/üretici/kapasite bilgisinin yanında, bu ekipmana bağlı
/// geçmiş iş emirlerini (arıza kayıtlarını) GET /api/equipment/:id/history
/// üzerinden ayrıca çeker ve listeler. Bir geçmiş kayda tıklanınca Modül 1'in
/// (İş Emirleri) detay ekranına gidilir — modüller arası gerçek bağlantı.
class EquipmentDetailScreen extends StatefulWidget {
  final int equipmentId;
  const EquipmentDetailScreen({super.key, required this.equipmentId});

  @override
  State<EquipmentDetailScreen> createState() => _EquipmentDetailScreenState();
}

class _EquipmentDetailScreenState extends State<EquipmentDetailScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('EquipmentDetailScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<EquipmentProvider>();
      provider.fetchEquipmentDetail(widget.equipmentId);
      provider.fetchEquipmentHistory(widget.equipmentId);
      context.read<RiskProvider>().fetchEquipmentRisk(widget.equipmentId);
      // Kestirimci Bakım Planlama (Modül 12) — bu ekipman için bekleyen bir
      // öneri varsa bağlam içi kartta göstermek üzere çekilir (bkz. build).
      context.read<MaintenanceProvider>().fetchRecommendations(
        statusFilter: 'onerildi',
      );
    });
  }

  String _installedAgoLabel(DateTime installDate) {
    final days = DateTime.now().difference(installDate).inDays;
    if (days < 30) return '$days gün önce kuruldu';
    final months = (days / 30).floor();
    if (months < 12) return '$months ay önce kuruldu';
    final years = (days / 365).floor();
    return '$years yıl önce kuruldu';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EquipmentProvider>();
    final equipment = provider.selectedEquipment?.id == widget.equipmentId
        ? provider.selectedEquipment
        : null;

    return Scaffold(
      appBar: const AppTopBar(title: 'Ekipman Detayı'),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (equipment == null && provider.detailErrorMessage != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 56,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: AppSpacing.sm + 4),
                      Text(
                        provider.detailErrorMessage!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: 'Tekrar Dene',
                        onPressed: () =>
                            provider.fetchEquipmentDetail(widget.equipmentId),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (equipment == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final riskProvider = context.read<RiskProvider>();
            final anomalyProvider = context.read<AnomalyProvider>();
            final maintenanceProvider = context.read<MaintenanceProvider>();
            return RefreshIndicator(
              onRefresh: () async {
                await provider.fetchEquipmentDetail(widget.equipmentId);
                await provider.fetchEquipmentHistory(widget.equipmentId);
                await riskProvider.fetchEquipmentRisk(widget.equipmentId);
                await maintenanceProvider.fetchRecommendations(
                  statusFilter: 'onerildi',
                );
                if (equipment.equipmentType == EquipmentType.sayac) {
                  await anomalyProvider.fetchEquipmentAnomaly(
                    widget.equipmentId,
                  );
                  await anomalyProvider.fetchEquipmentConsumption(
                    widget.equipmentId,
                  );
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  Row(
                    children: [
                      Icon(
                        equipment.equipmentType.icon,
                        size: 28,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          equipment.equipmentType.label,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      _EquipmentStatusBadge(status: equipment.status),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Icon(
                        Icons.qr_code_2_outlined,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        equipment.qrCode,
                        style: AppTextStyles.dataMono(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  _SectionCard(
                    title: 'Ekipman Bilgileri',
                    icon: Icons.info_outline,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _InfoRow(
                          icon: Icons.location_on_outlined,
                          label: 'Konum',
                          value: equipment.locationName,
                        ),
                        _InfoRow(
                          icon: Icons.event_outlined,
                          label: 'Kurulum Tarihi',
                          value: equipment.installDate != null
                              ? '${_formatDate(equipment.installDate!)} (${_installedAgoLabel(equipment.installDate!)})'
                              : 'Bilinmiyor',
                        ),
                        _InfoRow(
                          icon: Icons.build_outlined,
                          label: 'Son Bakım',
                          value: equipment.lastMaintenanceDate != null
                              ? '${_formatDate(equipment.lastMaintenanceDate!)} (${formatRelativeTime(equipment.lastMaintenanceDate!)})'
                              : 'Hiç bakım kaydı yok',
                        ),
                        _InfoRow(
                          icon: Icons.factory_outlined,
                          label: 'Üretici',
                          value: equipment.manufacturer.isNotEmpty
                              ? equipment.manufacturer
                              : 'Bilinmiyor',
                        ),
                        _InfoRow(
                          icon: Icons.settings_outlined,
                          label: 'Kapasite',
                          value: equipment.capacityInfo?.isNotEmpty == true
                              ? equipment.capacityInfo!
                              : '—',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  _SectionCard(
                    title: 'Risk Analizi',
                    icon: Icons.insights_outlined,
                    child: _RiskAnalysisSection(
                      equipmentId: widget.equipmentId,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // Kestirimci Bakım Planlama (Modül 12) — bu ekipman için
                  // bekleyen ('onerildi') bir öneri varsa bağlam içi gösterilir;
                  // kullanıcı merkezi Bakım Planlama listesine gitmeden,
                  // doğrudan burada "Önleyici İş Emri Oluştur" aksiyonunu
                  // alabilir. Öneri yoksa hiçbir şey render edilmez (bkz.
                  // _MaintenanceRecommendationSection).
                  _MaintenanceRecommendationSection(
                    equipmentId: widget.equipmentId,
                  ),

                  // Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11) — yalnızca
                  // sayaç tipi ekipmanlar için anlamlıdır (bkz. routes/anomaly.js
                  // equipment_type kontrolü). Farklı bir ikon (büyüteç) kullanılır
                  // ki Risk Analizi kartıyla (Icons.insights_outlined) karışmasın.
                  if (equipment.equipmentType == EquipmentType.sayac) ...[
                    _SectionCard(
                      title: 'Tüketim Analizi',
                      icon: Icons.search,
                      child: _ConsumptionAnalysisSection(
                        equipmentId: widget.equipmentId,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  _SectionCard(
                    title: 'Geçmiş Arıza Kayıtları',
                    icon: Icons.history,
                    child: _HistorySection(equipmentId: widget.equipmentId),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
  }
}

class _EquipmentStatusBadge extends StatelessWidget {
  final EquipmentStatus status;
  const _EquipmentStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = equipmentStatusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: accessibleOnColor(color),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm + 4),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: scheme.onSurface)),
          ),
        ],
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  final int equipmentId;
  const _HistorySection({required this.equipmentId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EquipmentProvider>();
    final scheme = Theme.of(context).colorScheme;

    if (provider.isHistoryLoading &&
        provider.history.isEmpty &&
        provider.historyErrorMessage == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (provider.historyErrorMessage != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            provider.historyErrorMessage!,
            style: TextStyle(color: scheme.error),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Tekrar Dene',
            variant: AppButtonVariant.secondary,
            onPressed: () => provider.fetchEquipmentHistory(equipmentId),
          ),
        ],
      );
    }

    if (provider.history.isEmpty) {
      return Text(
        'Bu ekipmanın kayıtlı arıza geçmişi bulunmuyor.',
        style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < provider.history.length; i++) ...[
          if (i > 0) const Divider(height: 20),
          _HistoryRow(entry: provider.history[i], equipmentId: equipmentId),
        ],
      ],
    );
  }
}

/// Arıza Risk Tahmini (Modül 9) — büyük skor + kısa, sabit bir açıklama
/// metniyle modelin şeffaf olduğunu gösterir.
///
/// DÜRÜSTLÜK NOTU: Bu skoru üreten model, ArasSaha'nın henüz gerçek bir
/// arıza geçmişi biriktirmemiş olması nedeniyle SENTETİK (kural tabanlı
/// üretilmiş) bir veri setiyle eğitildi (bkz. arassaha-ml/README.md).
class _RiskAnalysisSection extends StatelessWidget {
  final int equipmentId;
  const _RiskAnalysisSection({required this.equipmentId});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RiskProvider>();
    final risk = provider.riskFor(equipmentId);
    final isLoading = provider.isRiskLoading(equipmentId);
    final scheme = Theme.of(context).colorScheme;

    if (isLoading && risk == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (risk == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            provider.riskErrorMessage ?? 'Risk skoru henüz hesaplanmadı.',
            style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Risk Skorunu Hesapla',
            icon: Icons.refresh,
            variant: AppButtonVariant.secondary,
            onPressed: () => provider.fetchEquipmentRisk(equipmentId),
          ),
        ],
      );
    }

    final color = riskLevelColor(context, risk.riskLevel);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(
            '${risk.riskScore}',
            style: TextStyle(
              color: accessibleOnColor(color),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                risk.riskLevel.label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Bu ekipmanın yaşı, son bakım tarihi ve geçmiş arıza sayısına göre hesaplanmıştır.',
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Kestirimci Bakım Planlama (Modül 12) — bu ekipman için bekleyen bir öneri
/// varsa AYNI [MaintenanceRecommendationCard] bileşenini (Bakım Planlama
/// listesiyle paylaşılan) gösterir; yoksa hiçbir şey render etmez (SizedBox.shrink) —
/// spec gereği bu kart yalnızca KOŞULLU görünür, boş bir "öneri yok" durumu
/// göstermez (o zaten merkezi listede ele alınıyor).
class _MaintenanceRecommendationSection extends StatelessWidget {
  final int equipmentId;
  const _MaintenanceRecommendationSection({required this.equipmentId});

  @override
  Widget build(BuildContext context) {
    final recommendation = context
        .watch<MaintenanceProvider>()
        .recommendationForEquipment(equipmentId);
    if (recommendation == null) return const SizedBox.shrink();

    return Column(
      children: [
        MaintenanceRecommendationCard(recommendation: recommendation),
        const SizedBox(height: AppSpacing.md),
      ],
    );
  }
}

/// Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11) — anomali skoru + kural
/// tabanlı gerekçe + son 12 aylık tüketim grafiği (fl_chart). Yalnızca
/// equipment.equipmentType == sayac olduğunda oluşturulur (bkz. build); bu
/// yüzden fetch'i initState'te KOŞULSUZ tetiklemek güvenlidir.
///
/// DÜRÜSTLÜK NOTU: Bu skoru üreten IsolationForest modeli, ArasSaha'nın
/// henüz gerçek bir AMI/akıllı sayaç okuma sistemi olmaması nedeniyle
/// SENTETİK bir tüketim geçmişiyle eğitildi (bkz. arassaha-ml/README.md).
class _ConsumptionAnalysisSection extends StatefulWidget {
  final int equipmentId;
  const _ConsumptionAnalysisSection({required this.equipmentId});

  @override
  State<_ConsumptionAnalysisSection> createState() =>
      _ConsumptionAnalysisSectionState();
}

class _ConsumptionAnalysisSectionState
    extends State<_ConsumptionAnalysisSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AnomalyProvider>();
      provider.fetchEquipmentAnomaly(widget.equipmentId);
      provider.fetchEquipmentConsumption(widget.equipmentId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnomalyProvider>();
    final anomaly = provider.anomalyFor(widget.equipmentId);
    final isAnomalyLoading = provider.isAnomalyLoading(widget.equipmentId);
    final consumption = provider.consumptionFor(widget.equipmentId);
    final isConsumptionLoading = provider.isConsumptionLoading(
      widget.equipmentId,
    );
    final scheme = Theme.of(context).colorScheme;

    if (isAnomalyLoading && anomaly == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (anomaly == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            provider.anomalyErrorMessage ??
                'Tüketim analizi henüz hesaplanmadı.',
            style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Tüketim Analizini Hesapla',
            icon: Icons.refresh,
            variant: AppButtonVariant.secondary,
            onPressed: () => provider.fetchEquipmentAnomaly(widget.equipmentId),
          ),
        ],
      );
    }

    final color = anomaly.isSuspicious
        ? AppColors.danger(context)
        : AppColors.success(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Text(
                '${anomaly.anomalyScore}',
                style: TextStyle(
                  color: accessibleOnColor(color),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    anomaly.isSuspicious ? 'Şüpheli Tüketim' : 'Normal Tüketim',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    anomaly.detectedReason ??
                        'Tüketim örüntüsü, model tarafından normal aralıkta değerlendirildi.',
                    style: AppTextStyles.caption(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (isConsumptionLoading && consumption == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (consumption != null && consumption.isNotEmpty)
          _ConsumptionChart(entries: consumption, lineColor: color)
        else if (provider.consumptionErrorMessage != null)
          Text(
            provider.consumptionErrorMessage!,
            style: TextStyle(color: scheme.error),
          ),
      ],
    );
  }
}

/// Son 12 aylık tüketimi gösteren basit bir çizgi grafik — düşüşü/
/// düzensizliği görsel olarak da kanıtlar (bkz. PROMPT Modül 11 7b).
class _ConsumptionChart extends StatelessWidget {
  final List<MeterConsumptionEntry> entries;
  final Color lineColor;
  const _ConsumptionChart({required this.entries, required this.lineColor});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxY = entries
        .map((e) => e.consumptionKwh)
        .fold<double>(0, (max, v) => v > max ? v : max);

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY <= 0 ? 10 : maxY * 1.2,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 3,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= entries.length)
                    return const SizedBox.shrink();
                  final parts = entries[index].yearMonth.split('-');
                  final label = parts.length == 2
                      ? '${parts[1]}/${parts[0].substring(2)}'
                      : entries[index].yearMonth;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (int i = 0; i < entries.length; i++)
                  FlSpot(i.toDouble(), entries[i].consumptionKwh),
              ],
              isCurved: true,
              color: lineColor,
              barWidth: 3,
              dotData: const FlDotData(show: true),
              belowBarData: BarAreaData(
                show: true,
                color: lineColor.withValues(alpha: 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Modül 1'deki iş emri kartının küçültülmüş versiyonu: başlık, statü, tarih.
/// Tıklanınca Modül 1'in (İş Emirleri) tam detay ekranına gider — modüller
/// arası gerçek bağlantı.
class _HistoryRow extends StatelessWidget {
  final EquipmentHistoryEntry entry;
  final int equipmentId;
  const _HistoryRow({required this.entry, required this.equipmentId});

  /// İş emri detayında durum 'çözüldü'ye getirilirse backend bağlı
  /// ekipmanın last_maintenance_date'ini otomatik günceller (bkz.
  /// routes/workOrders.js PATCH /:id/status). Bu ekrana geri dönüldüğünde
  /// (push'un Future'ı tamamlandığında) ekipman bilgisi ve geçmiş listesi
  /// YENİDEN çekilmezse kullanıcı hâlâ ESKİ "Son Bakım" tarihini görür —
  /// bu yüzden dönüşte açıkça yeniden fetch edilir.
  Future<void> _openDetail(BuildContext context) async {
    final equipmentProvider = context.read<EquipmentProvider>();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WorkOrderDetailScreen(workOrderId: entry.id),
      ),
    );
    await equipmentProvider.fetchEquipmentDetail(equipmentId);
    await equipmentProvider.fetchEquipmentHistory(equipmentId);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.chip),
      onTap: () => _openDetail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      StatusBadge(status: entry.status),
                      const SizedBox(width: 8),
                      Text(
                        formatRelativeTime(entry.createdAt),
                        style: AppTextStyles.caption(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
