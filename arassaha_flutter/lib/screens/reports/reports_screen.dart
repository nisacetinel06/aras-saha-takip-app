import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../models/equipment.dart';
import '../../models/equipment_risk.dart';
import '../../models/material.dart' show formatMaterialQuantity;
import '../../models/report.dart';
import '../../providers/equipment_provider.dart';
import '../../providers/reports_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../equipment/equipment_list_screen.dart';

/// Raporlar / Analitik Sayfası (Modül 14) — Dashboard'un (Modül 2) "büyütülmüş"
/// hali: risk yoğunluk haritası, bölgesel/zamansal arıza kırılımları, anomali
/// dağılımı ve malzeme kullanım özeti. Yalnızca yönetici erişebilir (backend
/// routes/reports.js her endpoint'te requireRole('yonetici') uygular; Ana
/// Sayfa modül kartı da AYNI kısıtlamayla yalnızca yöneticiye gösterilir).
///
/// 3 sekme (Bölgesel Görünüm / Eğilimler / Malzeme Kullanımı) LAZY LOADING
/// ile çalışır: her sekmeye YALNIZCA ilk kez gidildiğinde ilgili veri çekilir
/// (bkz. ReportsProvider) — ekran açılır açılmaz 6 endpoint'e birden istek
/// atmak performansı gereksiz düşürürdü.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _lastFetchedTabIndex = -1;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('ReportsScreen');
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => _fetchForTab(_tabController.index));
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetchForTab(0));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Bir sekme İLK KEZ görünür olduğunda ilgili verisini çeker.
  /// `_lastFetchedTabIndex`, TabController'ın animasyon sırasında listener'ı
  /// birden fazla kez tetiklemesi yüzünden aynı sekme için gereksiz tekrar
  /// çağrı yapılmasını önler; asıl "yalnızca bir kez çek" garantisi zaten
  /// ReportsProvider'daki `_xLoaded` bayraklarındadır (bkz. reports_provider.dart) —
  /// bu yalnızca gereksiz provider çağrısını azaltan bir optimizasyon.
  void _fetchForTab(int index) {
    if (_lastFetchedTabIndex == index) return;
    _lastFetchedTabIndex = index;
    final provider = context.read<ReportsProvider>();
    switch (index) {
      case 0:
        provider.fetchRegionalTabData();
        break;
      case 1:
        provider.fetchTrendsTabData();
        break;
      case 2:
        provider.fetchTopMaterialUsage();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Raporlar'),
        actions: const [
          NotificationBellButton(),
          ThemeToggleButton(),
          SizedBox(width: AppSpacing.xs),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Bölgesel Görünüm'),
            Tab(text: 'Eğilimler'),
            Tab(text: 'Malzeme Kullanımı'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabController,
          children: const [_RegionalTab(), _TrendsTab(), _MaterialsTab()],
        ),
      ),
    );
  }
}

/// Ortak bölüm çerçevesi: başlık + yükleniyor/hata/boş/veri durumlarını TEK
/// yerden yönetir — Dashboard'daki (_RiskyEquipmentSection, _LowStockMaterialsSection)
/// loading/error/empty/list deseniyle AYNI, 6 farklı bölüm için tekrar yazılmasın diye buraya taşındı.
class _ReportSection extends StatelessWidget {
  final String title;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;
  final bool isEmpty;
  final String emptyMessage;
  final Widget child;

  const _ReportSection({
    required this.title,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
    required this.isEmpty,
    required this.emptyMessage,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (isLoading && isEmpty) {
      content = const AppCard(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (errorMessage != null && isEmpty) {
      content = AppCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            AppButton(label: 'Tekrar Dene', onPressed: onRetry),
          ],
        ),
      );
    } else if (isEmpty) {
      content = AppCard(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            emptyMessage,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    } else {
      content = child;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          content,
        ],
      ),
    );
  }
}

/// Bir ilin risk verisi henüz yoksa da (equipment_count=0 ya da avg_risk_score
/// null) aynı satır biçimini paylaşan basit bir yatay oran çubuğu — fault-by-region
/// ve material-usage-top BİLİNÇLİ olarak fl_chart'ın (vertical-only) BarChart'ı
/// yerine bununla çizildi: fl_chart'ta yatay çubuk yalnızca tüm widget'ı 90°
/// döndürüp etiketleri geri döndürme gibi karmaşık bir workaround'la mümkün;
/// burada ≤10 satırlık sıralı bir liste için bu basit oran çubuğu hem daha
/// az kod hem de Dashboard'daki (RiskyEquipmentSection/LowStockMaterialsSection)
/// satır tabanlı görsel diliyle zaten tutarlı.
class _HorizontalBarRow extends StatelessWidget {
  final String label;
  final double value;
  final double maxValue;
  final Color color;
  final String valueLabel;

  const _HorizontalBarRow({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.color,
    required this.valueLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = maxValue <= 0 ? 0.0 : (value / maxValue).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    children: [
                      Container(
                        height: 16,
                        color: scheme.surfaceContainerHighest,
                      ),
                      Container(
                        height: 16,
                        width: constraints.maxWidth * fraction,
                        color: color,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 48,
            child: Text(
              valueLabel,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Sekme 1 — Bölgesel Görünüm
// ============================================================================

class _RegionalTab extends StatelessWidget {
  const _RegionalTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportsProvider>();

    return RefreshIndicator(
      onRefresh: () => provider.fetchRegionalTabData(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text(
            'Risk Yoğunluk Haritası',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          _RiskBubbleMap(
            regions: provider.regionalRiskSummary,
            isLoading: provider.isLoadingRegionalRisk,
            errorMessage: provider.regionalRiskErrorMessage,
            onRetry: () => provider.fetchRegionalRiskSummary(force: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          const _RiskLegend(),
          const SizedBox(height: AppSpacing.lg),
          _ReportSection(
            title: 'Arıza Dağılımı (Bölgeye Göre)',
            isLoading: provider.isLoadingFaultByRegion,
            errorMessage: provider.faultByRegionErrorMessage,
            onRetry: () => provider.fetchFaultByRegion(force: true),
            isEmpty: provider.faultByRegion.isEmpty,
            emptyMessage: 'Gösterilecek arıza kaydı yok.',
            child: _FaultByRegionChart(data: provider.faultByRegion),
          ),
        ],
      ),
    );
  }
}

/// Haritanın kendisi ayrı bir alt widget'a çıkarıldı — yükleniyor/hata
/// durumlarını harita ALANININ İÇİNDE (MapScreen'deki _LoadingChip/_ErrorBanner
/// deseniyle AYNI şekilde bindirilmiş olarak) göstermek için.
class _RiskBubbleMap extends StatelessWidget {
  final List<RegionalRiskSummary> regions;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;

  const _RiskBubbleMap({
    required this.regions,
    required this.isLoading,
    required this.errorMessage,
    required this.onRetry,
  });

  // MapScreen'deki (Modül 3) hizmet bölgesi merkeziyle BİREBİR AYNI —
  // haritanın ilk açılışta aynı bölgeyi göstermesi için (bkz. map_screen.dart).
  static const LatLng _regionCenter = LatLng(39.90, 41.27);
  static const double _regionZoom = 6.6;

  void _showRegionSheet(BuildContext context, RegionalRiskSummary region) {
    final hasEquipment = region.equipmentCount > 0;
    final level = region.riskLevel;
    final color = level != null
        ? riskLevelColor(context, level)
        : Theme.of(context).colorScheme.outline;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm + 4,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                AppCard(
                  statusStripeColor: color,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        region.il,
                        style: Theme.of(sheetContext).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm + 2),
                      Text(
                        'Ekipman sayısı: ${region.equipmentCount}',
                        style: AppTextStyles.bodyMedium(
                          color: Theme.of(sheetContext).colorScheme.onSurface,
                        ),
                      ),
                      if (region.avgRiskScore != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Ortalama risk skoru: ${region.avgRiskScore!.toStringAsFixed(0)} (${level!.label})',
                          style: AppTextStyles.bodyMedium(
                            color: Theme.of(sheetContext).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Yüksek riskli ekipman: ${region.highRiskCount}',
                          style: AppTextStyles.bodyMedium(
                            color: Theme.of(sheetContext).colorScheme.onSurface,
                          ),
                        ),
                      ] else if (hasEquipment) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Bu ildeki ekipmanlar için risk skoru henüz hesaplanmamış.',
                          style: AppTextStyles.caption(
                            color: Theme.of(
                              sheetContext,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 4),
                        Text(
                          'Bu ilde henüz ekipman kaydı yok.',
                          style: AppTextStyles.caption(
                            color: Theme.of(
                              sheetContext,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (hasEquipment) ...[
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: AppButton(
                            label: 'Detaya Git',
                            icon: Icons.arrow_forward,
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              // Modül 4 (Ekipman) ile bağlantı: MapScreen'in
                              // "Ekipman Detayını Gör" bağlantısıyla AYNI
                              // desen — EquipmentProvider zaten uygulama
                              // kökünde tek bir örnek olarak yaşadığı için,
                              // filtreyi push'tan ÖNCE ayarlamak yeterli;
                              // EquipmentListScreen kendi initState'inde bu
                              // filtreyle listeyi çeker.
                              context.read<EquipmentProvider>().setIlFilter(
                                region.il,
                              );
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const EquipmentListScreen(),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Marker _buildRegionMarker(
    BuildContext context,
    RegionalRiskSummary region,
    int maxEquipmentCount,
  ) {
    final hasEquipment = region.equipmentCount > 0;
    final level = region.riskLevel;
    // Büyüklük ekipman sayısıyla orantılı ("nerede daha fazla altyapı var"
    // bilgisini de taşısın diye) — B2 (dokunma alanı) gereği en küçük
    // bubble bile MapScreen'in normal pin boyutuyla (44dp) aynı dokunma
    // alanına sahip; büyüklük farkı yalnızca GÖRSELDİR (36-68dp aralığı),
    // GestureDetector her zaman tüm daireyi kaplar.
    final size = hasEquipment
        ? (36 + (region.equipmentCount / maxEquipmentCount) * 32).clamp(
            36.0,
            68.0,
          )
        : 32.0;
    final color = level != null
        ? riskLevelColor(context, level)
        : Theme.of(context).colorScheme.outline;

    return Marker(
      point: LatLng(region.centerLat, region.centerLng),
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _showRegionSheet(context, region),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: level != null ? 0.55 : 0.18),
            border: Border.all(color: color, width: level != null ? 2.5 : 1.5),
          ),
          alignment: Alignment.center,
          child: hasEquipment
              ? Text(
                  '${region.equipmentCount}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.3,
                    color: level != null
                        ? accessibleOnColor(color)
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                )
              : Icon(
                  Icons.remove,
                  size: size * 0.4,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxEquipmentCount = regions.isEmpty
        ? 1
        : regions
              .map((r) => r.equipmentCount)
              .fold<int>(1, (max, c) => c > max ? c : max);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: SizedBox(
        height: 320,
        child: Stack(
          children: [
            FlutterMap(
              options: const MapOptions(
                initialCenter: _regionCenter,
                initialZoom: _regionZoom,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.arasedas.arassaha_flutter',
                ),
                MarkerLayer(
                  markers: regions
                      .map(
                        (r) =>
                            _buildRegionMarker(context, r, maxEquipmentCount),
                      )
                      .toList(),
                ),
              ],
            ),
            if (isLoading && regions.isEmpty)
              const Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: _MapStatusChip(message: 'Risk verileri yükleniyor...'),
              ),
            if (errorMessage != null && regions.isEmpty)
              Positioned(
                top: 10,
                left: 12,
                right: 12,
                child: _MapErrorBanner(
                  message: errorMessage!,
                  onRetry: onRetry,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// MapScreen'deki (_LoadingChip) ile AYNI görsel dil — modüller arası tutarlılık.
class _MapStatusChip extends StatelessWidget {
  final String message;
  const _MapStatusChip({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.primary,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              message,
              style: TextStyle(fontSize: 12, color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

/// MapScreen'deki (_ErrorBanner) ile AYNI görsel dil.
class _MapErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _MapErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: scheme.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              foregroundColor: scheme.onErrorContainer,
            ),
            child: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }
}

class _RiskLegend extends StatelessWidget {
  const _RiskLegend();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (label: 'Düşük Risk', color: riskLevelColor(context, RiskLevel.dusuk)),
      (label: 'Orta Risk', color: riskLevelColor(context, RiskLevel.orta)),
      (label: 'Yüksek Risk', color: riskLevelColor(context, RiskLevel.yuksek)),
      (label: 'Veri Yok', color: scheme.outline),
    ];

    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: 6,
      children: items.map((item) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: item.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              item.label,
              style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _FaultByRegionChart extends StatelessWidget {
  final List<RegionFaultCount> data;
  const _FaultByRegionChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxValue = data
        .map((d) => d.faultCount)
        .fold<int>(0, (max, c) => c > max ? c : max)
        .toDouble();

    return AppCard(
      child: Column(
        children: data
            .map(
              (d) => _HorizontalBarRow(
                label: d.il,
                value: d.faultCount.toDouble(),
                maxValue: maxValue,
                color: AppColors.primary(context),
                valueLabel: '${d.faultCount}',
              ),
            )
            .toList(),
      ),
    );
  }
}

// ============================================================================
// Sekme 2 — Eğilimler
// ============================================================================

class _TrendsTab extends StatelessWidget {
  const _TrendsTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportsProvider>();

    return RefreshIndicator(
      onRefresh: () => provider.fetchTrendsTabData(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _ReportSection(
            title: 'Aylık Arıza Trendi',
            isLoading: provider.isLoadingFaultTrend,
            errorMessage: provider.faultTrendErrorMessage,
            onRetry: () => provider.fetchFaultTrend(force: true),
            isEmpty: provider.faultTrend.isEmpty,
            emptyMessage: 'Gösterilecek arıza kaydı yok.',
            child: _FaultTrendChart(data: provider.faultTrend),
          ),
          _ReportSection(
            title: 'Ekipman Tipine Göre Arıza Sıklığı',
            isLoading: provider.isLoadingFaultByEquipmentType,
            errorMessage: provider.faultByEquipmentTypeErrorMessage,
            onRetry: () => provider.fetchFaultByEquipmentType(force: true),
            isEmpty: provider.faultByEquipmentType.isEmpty,
            emptyMessage: 'Gösterilecek arıza kaydı yok.',
            child: _FaultByEquipmentTypePieChart(
              data: provider.faultByEquipmentType,
            ),
          ),
          _ReportSection(
            title: 'Anomali / Şüpheli Sayaç Dağılımı',
            isLoading: provider.isLoadingAnomalyByRegion,
            errorMessage: provider.anomalyByRegionErrorMessage,
            onRetry: () => provider.fetchAnomalyByRegion(force: true),
            isEmpty: provider.anomalyByRegion.isEmpty,
            emptyMessage: 'Gösterilecek sayaç verisi yok.',
            child: _AnomalyByRegionTable(data: provider.anomalyByRegion),
          ),
        ],
      ),
    );
  }
}

class _FaultTrendChart extends StatelessWidget {
  final List<MonthlyFaultCount> data;
  const _FaultTrendChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final maxY = data
        .map((d) => d.faultCount)
        .fold<int>(0, (max, c) => c > max ? c : max);

    return AppCard(
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 8),
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: (maxY + 1).toDouble(),
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
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= data.length)
                      return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        data[index].shortLabel,
                        style: TextStyle(fontSize: 11, color: onSurface),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) =>
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (int i = 0; i < data.length; i++)
                    FlSpot(i.toDouble(), data[i].faultCount.toDouble()),
                ],
                isCurved: true,
                color: AppColors.primary(context),
                barWidth: 3,
                dotData: const FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: AppColors.primary(context).withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ekipman tipi renkleri yalnızca bu pasta grafiğe özeldir (gerçek bir statü/
/// risk göstergesi değil, salt kategorik ayrım) — bu yüzden AppColors'a değil,
/// buraya yerel bırakıldı; statusColor/riskLevelColor gibi uygulama genelinde
/// tekrar kullanılan "gerçek durum" renkleriyle KARIŞTIRILMASIN diye.
Color _equipmentTypeColor(BuildContext context, EquipmentType type) {
  switch (type) {
    case EquipmentType.trafo:
      return AppColors.primary(context);
    case EquipmentType.direk:
      // Marka revizyonu: eski "accent" (turuncu) kaldırıldığı için, statü
      // yeşilinden (success) görsel olarak ayrışan positive tonu kullanılır —
      // dördüncü kategori için yeni bir hue eklemek yerine mevcut onaylı
      // paletten (mavi/yeşil/kırmızı/amber) kalıyoruz.
      return AppColors.positive(context);
    case EquipmentType.kesici:
      return AppColors.danger(context);
    case EquipmentType.sayac:
      return AppColors.success(context);
  }
}

class _FaultByEquipmentTypePieChart extends StatelessWidget {
  final List<EquipmentTypeFaultCount> data;
  const _FaultByEquipmentTypePieChart({required this.data});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 130,
            height: 130,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 28,
                sections: data.map((d) {
                  final color = _equipmentTypeColor(context, d.equipmentType);
                  return PieChartSectionData(
                    value: d.faultCount.toDouble(),
                    color: color,
                    title: '${d.faultCount}',
                    radius: 40,
                    titleStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: accessibleOnColor(color),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: data.map((d) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _equipmentTypeColor(context, d.equipmentType),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${d.equipmentType.label}: ${d.faultCount}',
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnomalyByRegionTable extends StatelessWidget {
  final List<RegionAnomalySummary> data;
  const _AnomalyByRegionTable({required this.data});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < data.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _AnomalyRegionRow(item: data[i]),
          ],
        ],
      ),
    );
  }
}

class _AnomalyRegionRow extends StatelessWidget {
  final RegionAnomalySummary item;
  const _AnomalyRegionRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Oran eşikleri: Modül 11'in kendi eşiği yok (is_suspicious ikili bir
    // bayrak) — bu yalnızca RAPOR sayfasına özel bir görsel vurgu, %50 üstü
    // "dikkat çekici" kabul edildi (bkz. danger rengi).
    final color = item.suspiciousRatio >= 0.5
        ? AppColors.danger(context)
        : item.suspiciousCount > 0
        ? AppColors.warning(context)
        : AppColors.success(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color,
        radius: 18,
        child: Text(
          '${item.suspiciousCount}',
          style: TextStyle(
            color: accessibleOnColor(color),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      title: Text(item.il),
      subtitle: Text(
        '${item.suspiciousCount}/${item.totalMeters} şüpheli sayaç',
        style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
      ),
      trailing: Text(
        '%${(item.suspiciousRatio * 100).toStringAsFixed(0)}',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ============================================================================
// Sekme 3 — Malzeme Kullanımı
// ============================================================================

class _MaterialsTab extends StatelessWidget {
  const _MaterialsTab();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ReportsProvider>();

    return RefreshIndicator(
      onRefresh: () => provider.fetchTopMaterialUsage(force: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          _ReportSection(
            title: 'En Çok Kullanılan Malzemeler',
            isLoading: provider.isLoadingTopMaterialUsage,
            errorMessage: provider.topMaterialUsageErrorMessage,
            onRetry: () => provider.fetchTopMaterialUsage(force: true),
            isEmpty: provider.topMaterialUsage.isEmpty,
            emptyMessage:
                'Henüz bir iş emrinde malzeme kullanımı kaydedilmedi.',
            child: _TopMaterialUsageChart(data: provider.topMaterialUsage),
          ),
        ],
      ),
    );
  }
}

class _TopMaterialUsageChart extends StatelessWidget {
  final List<TopMaterialUsage> data;
  const _TopMaterialUsageChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final maxValue = data
        .map((d) => d.totalUsed)
        .fold<double>(0, (max, v) => v > max ? v : max);

    return AppCard(
      child: Column(
        children: data.map((d) {
          return _HorizontalBarRow(
            label: d.name,
            value: d.totalUsed,
            maxValue: maxValue,
            color: AppColors.warning(context),
            valueLabel: formatMaterialQuantity(d.totalUsed),
          );
        }).toList(),
      ),
    );
  }
}
