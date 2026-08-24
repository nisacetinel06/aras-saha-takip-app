import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'app_button.dart';

/// Tek bir aktif filtreyi temsil eder — [EmptyState] bunu yalnızca bir chip
/// olarak GÖSTERİR, filtre mantığını bilmez; her ekran kendi filtre
/// state'inden (statü/öncelik/il/arama gibi) bu listeyi üretir ve chip'in
/// ✕'üne basılınca SADECE o filtreyi kaldıran callback'i [onRemove]'a verir.
class ActiveFilterChip {
  final String label;
  final VoidCallback onRemove;

  const ActiveFilterChip({required this.label, required this.onRemove});
}

/// Uygulama genelindeki "filtrelenmiş liste boş durumu" ekranları için TEK,
/// paylaşılan bileşen (bkz. İş Emirleri/Ekipman/Bakım Önerileri/Stok
/// listeleri). Önceden her ekran kendi "Bu filtreye uyan X yok." metnini
/// tekrar tekrar yazıyordu ve hiçbiri aktif filtreleri özetlemiyordu —
/// kullanıcı hangi filtrelerin açık olduğunu hatırlayıp teker teker
/// kapatmak zorunda kalıyordu (bkz. MODUL_ONERILERI.md "Filtrelenmiş Liste
/// Boş Durumu İyileştirmesi").
///
/// İki farklı boş durum senaryosunu ayırt eder:
///   1. [activeFilters] doluysa: kullanıcı bir/daha fazla filtre uygulamış
///      ve sonuç boş — filtreler chip olarak listelenir (her biri tek
///      başına kaldırılabilir) + altında tam genişlikte "Tüm Filtreleri
///      Temizle" butonu.
///   2. [activeFilters] boş/null ise: liste zaten (filtresiz) boş — chip
///      gösterilmez, yalnızca [subtitle] açıklaması ve varsa genel bir
///      [onPrimaryAction] gösterilir (örn. "İlk İş Emrini Oluştur").
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final List<ActiveFilterChip>? activeFilters;
  final VoidCallback? onClearFilters;
  final VoidCallback? onPrimaryAction;
  final String? primaryActionLabel;

  /// [onPrimaryAction] butonunun varyantı. Varsayılan `primary` — "İlk
  /// kaydı oluştur" gibi asıl CTA'lar için doğru. Bir "Tekrar Dene" aksiyonu
  /// geçiriliyorsa `AppButtonVariant.secondary` verilmeli (bkz.
  /// CONTRIBUTING.md "Hata ve Boş Durum Standartları" — uygulama genelinde
  /// TÜM "Tekrar Dene" butonları aynı stilde olmalı).
  final AppButtonVariant primaryActionVariant;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.activeFilters,
    this.onClearFilters,
    this.onPrimaryAction,
    this.primaryActionLabel,
    this.primaryActionVariant = AppButtonVariant.primary,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasActiveFilters =
        activeFilters != null && activeFilters!.isNotEmpty;

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: AppColors.textSecondary(context)),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium(color: scheme.onSurface)
                .copyWith(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs + 2),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium(
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
          if (hasActiveFilters) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final filter in activeFilters!) _RemovableChip(filter: filter),
              ],
            ),
            if (onClearFilters != null) ...[
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  label: 'Tüm Filtreleri Temizle',
                  icon: Icons.filter_alt_off_outlined,
                  variant: AppButtonVariant.secondary,
                  onPressed: onClearFilters,
                ),
              ),
            ],
          ] else if (onPrimaryAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                label: primaryActionLabel ?? 'Aksiyon',
                variant: primaryActionVariant,
                onPressed: onPrimaryAction,
              ),
            ),
          ],
        ],
      ),
    );

    // LayoutBuilder + SingleChildScrollView + ConstrainedBox(minHeight): bu
    // ekranların çoğu bir RefreshIndicator içinde yaşıyor — liste boşken bile
    // aşağı çekip yenileyebilmek için içerik SCROLL EDİLEBİLİR kalmalı, aynı
    // zamanda kısa içerik dikeyde ortalanmalı (mevcut ekranlardaki AYNI desen).
    // Bu, YALNIZCA sınırlı (bounded) bir yükseklik verildiğinde güvenlidir —
    // EmptyState zaten sınırsız yükseklikli bir Column içine (örn. Ana
    // Sayfa'daki gömülü "Tamamlanan İş Emirlerim" önizleme bölümü gibi
    // kendisi zaten kaydırılabilir bir üst widget'ın içine) yerleştirildiğinde
    // `constraints.maxHeight` sonsuz olur — bu durumda `ConstrainedBox`'a
    // sonsuz `minHeight` vermek layout hatasına yol açar, bu yüzden o
    // durumda içerik SADECE ortalanır, ayrıca bir scroll view'a SARILMAZ (üst
    // widget zaten kaydırılabilir).
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!constraints.hasBoundedHeight) {
          return Center(child: content);
        }
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: content),
          ),
        );
      },
    );
  }
}

class _RemovableChip extends StatelessWidget {
  final ActiveFilterChip filter;
  const _RemovableChip({required this.filter});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(filter.label),
      labelStyle: AppTextStyles.caption(color: scheme.onSurfaceVariant),
      backgroundColor: scheme.surfaceContainerLowest,
      side: BorderSide(color: scheme.outlineVariant),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      deleteIcon: Icon(Icons.close, size: 16, color: scheme.onSurfaceVariant),
      onDeleted: filter.onRemove,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
