import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/meter_anomaly.dart';
import '../../providers/anomaly_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import 'equipment_detail_screen.dart';

/// Kayıp-Kaçak / Anormal Tüketim Tespiti (Modül 11) — Şüpheli Sayaçlar
/// listesi. GET /api/meters/suspicious'tan gelen tüm kayıtları, anomaly_score'a
/// göre azalan sırada gösterir.
///
/// Modül 9'daki "Riskli Ekipmanlar" ile AYNI görsel dilden (AppCard, sol
/// kenarda durum şeridi) gelir ama BİLİNÇLİ olarak farklı bir rozet ikonu
/// kullanır (büyüteç yerine uyarı üçgeni) — kullanıcı iki farklı analiz
/// türünü (genel risk skoru / somut tüketim anomalisi) karıştırmasın diye.
/// Her kartta `detectedReason` metni ÖNE ÇIKARILIR — bu modülün Modül 9'un
/// genel risk skorundan farkı, somut bir gerekçe sunabilmesidir.
///
/// DÜRÜSTLÜK NOTU: Skorları üreten IsolationForest modeli, ArasSaha'nın
/// henüz gerçek bir AMI/akıllı sayaç okuma sistemi olmaması nedeniyle
/// SENTETİK bir tüketim geçmişiyle eğitildi (bkz. arassaha-ml/README.md).
class SuspiciousMetersScreen extends StatefulWidget {
  const SuspiciousMetersScreen({super.key});

  @override
  State<SuspiciousMetersScreen> createState() => _SuspiciousMetersScreenState();
}

class _SuspiciousMetersScreenState extends State<SuspiciousMetersScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('SuspiciousMetersScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnomalyProvider>().fetchSuspiciousMeters();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AnomalyProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'Şüpheli Sayaçlar'),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (provider.isSuspiciousListLoading &&
                provider.suspiciousMeters.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.suspiciousListErrorMessage != null &&
                provider.suspiciousMeters.isEmpty) {
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
                        provider.suspiciousListErrorMessage!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: 'Tekrar Dene',
                        onPressed: provider.fetchSuspiciousMeters,
                      ),
                    ],
                  ),
                ),
              );
            }

            if (provider.suspiciousMeters.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search_off,
                        size: 56,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppSpacing.sm + 4),
                      Text(
                        'Şu anda şüpheli işaretlenmiş bir sayaç yok.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: provider.fetchSuspiciousMeters,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                itemCount: provider.suspiciousMeters.length,
                itemBuilder: (context, index) {
                  final item = provider.suspiciousMeters[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: _SuspiciousMeterCard(
                      item: item,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              EquipmentDetailScreen(equipmentId: item.id),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Anomali şiddetine göre renk: 75+ yüksek şüphe (kırmızı/danger),
/// altındaki tüm şüpheli kayıtlar düşük şüphe (sarı/warning). Bu eşik,
/// yalnızca görsel önceliklendirme içindir — is_suspicious kararının
/// kendisi zaten backend'deki modelin kendi karar sınırından gelir.
Color _severityColor(BuildContext context, int score) {
  return score >= 75 ? AppColors.danger(context) : AppColors.warning(context);
}

class _SuspiciousMeterCard extends StatelessWidget {
  final SuspiciousMeterSummary item;
  final VoidCallback onTap;
  const _SuspiciousMeterCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _severityColor(context, item.anomalyScore);

    return AppCard(
      onTap: onTap,
      statusStripeColor: color,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Modül 9'daki risk rozetinden (skor sayısı) BİLİNÇLİ olarak farklı:
          // burada bir uyarı üçgeni ikonu kullanılır — kullanıcı iki analiz
          // türünü karıştırmasın diye.
          CircleAvatar(
            radius: 22,
            backgroundColor: color,
            child: Icon(
              Icons.warning_amber_rounded,
              color: accessibleOnColor(color),
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.speed, size: 16, color: scheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        item.qrCode,
                        style: AppTextStyles.dataMono(color: scheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '${item.anomalyScore}',
                      style: TextStyle(
                        color: color,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  item.locationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
                if (item.detectedReason != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  // Bu modülün en değerli kısmı: somut, insan tarafından
                  // okunabilir bir gerekçe — Modül 9'un genel risk skorunun
                  // aksine "neden" sorusuna doğrudan yanıt verir.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.18
                            : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      item.detectedReason!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
