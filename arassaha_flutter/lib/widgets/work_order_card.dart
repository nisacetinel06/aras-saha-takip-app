import 'package:flutter/material.dart';
import '../models/work_order.dart';
import '../theme/app_colors.dart';
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
  // "Tamamlanan İş Emirlerim" bölümü (Ana Sayfa, teknisyen) için: alttaki
  // tarih, oluşturulma değil TAMAMLANMA anını göstersin diye — bir iş emri
  // haftalar önce açılıp bugün çözülmüş olabilir, bu durumda "oluşturuldu: 3
  // hafta önce" göstermek yanıltıcı olurdu. `updatedAt`, bir iş emri
  // 'cozuldu' durumuna geçtiğinde GERÇEK tamamlanma anını taşır (bkz.
  // routes/workOrders.js PATCH /:id/status). Varsayılan false: diğer TÜM
  // çağıranlar (İş Emirleri listesi, Ana Sayfa özet kartları, Harita)
  // davranışı değişmeden createdAt göstermeye devam eder.
  final bool showCompletedDate;

  // Kartın kendi yatay dış boşluğu — varsayılan (12) tüm mevcut kullanım
  // yerleriyle (İş Emirleri listesi, Harita, vb. — hepsi PADDİNG'SİZ bir
  // ListView içine yerleştirir) birebir aynıdır. "Tamamlanan İş Emirlerim"
  // bölümü (Ana Sayfa) bu kartı ZATEN AppSpacing.md (16px) yatay boşluk
  // uygulayan bir ListView'ın İÇİNE yerleştirdiği için orada 0 verilir —
  // aksi halde 12+16=28px, sayfadaki diğer her şeyin 16px'inden farklı
  // görünürdü (bkz. completed_work_orders_section.dart).
  final double horizontalMargin;

  const WorkOrderCard({
    super.key,
    required this.workOrder,
    required this.onTap,
    this.showCompletedDate = false,
    this.horizontalMargin = 12,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPreventiveMaintenance =
        workOrder.sourceType == WorkOrderSourceType.onleyiciBakim;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: 6),
      child: Stack(
        children: [
          AppCard(
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
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        workOrder.locationName,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
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
                      showCompletedDate
                          ? 'Tamamlandı: ${formatRelativeTime(workOrder.updatedAt)}'
                          : formatRelativeTime(workOrder.createdAt),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                Divider(
                  height: 24,
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        workOrder.assignedUser?.name ?? 'Atanmamış',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Text(
                      'Detaylar',
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(Icons.arrow_forward, size: 16, color: scheme.primary),
                  ],
                ),
              ],
            ),
          ),
          // Kestirimci Bakım Planlama (Modül 12) — bir bakım önerisinden
          // dönüştürülen iş emirlerini arıza iş emirlerinden bir bakışta
          // ayırt etmek için kartın köşesinde küçük bir rozet (bkz.
          // ARCHITECTURE.md Modül 12: "kaynak ayrımı").
          if (isPreventiveMaintenance)
            Positioned(
              top: 6,
              right: 6,
              child: Tooltip(
                message: 'Önleyici Bakım',
                child: CircleAvatar(
                  radius: 12,
                  backgroundColor: AppColors.success(context),
                  child: Icon(
                    Icons.build,
                    size: 14,
                    color: accessibleOnColor(AppColors.success(context)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
