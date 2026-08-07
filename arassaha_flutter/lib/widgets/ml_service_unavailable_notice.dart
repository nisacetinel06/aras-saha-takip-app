import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text_styles.dart';
import 'app_button.dart';

/// arassaha-ml (Python/FastAPI) servisine ulaşılamadığında (kapalı/ağ hatası)
/// Modül 9 (Risk), Modül 10 (NLP sınıflandırma) ve Modül 11 (Anomali) TARAFINDAN
/// ORTAK kullanılan tek bir uyarı bileşeni. Öncesinde her modül kendi başına
/// (bazen sessizce, bazen belirsiz bir metinle) bu durumu ele alıyordu — artık
/// hepsi AYNI, açıklayıcı mesajı gösteriyor: kullanıcı "sonuç neden boş"
/// sorusuna kendi başına cevap arayacağına, servisin GEÇİCİ olarak
/// (bilgisayar kapalı/ağ sorunu) ulaşılamaz olduğunu net şekilde görür.
///
/// Renk kuralı: bu bir "uyarı" (warning/amber) durumudur, "hata" (danger)
/// DEĞİL — veri kaybı/bozulma yok, servis geçici olarak erişilemez; durum
/// renkleri kuralına (bkz. app_colors.dart) uygun tek genel-amaçlı kullanım.
class MlServiceUnavailableNotice extends StatelessWidget {
  /// Backend'den gelen ham hata mesajı (varsa) — genellikle zaten Türkçe ve
  /// açıklayıcıdır (bkz. arassaha-backend routes/risk.js "ML servisine
  /// ulaşılamıyor olabilir" gibi 503 mesajları). null ise sabit bir varsayılan
  /// açıklama gösterilir.
  final String? detail;

  /// Verilirse altta bir "Tekrar Dene" butonu gösterilir.
  final VoidCallback? onRetry;

  const MlServiceUnavailableNotice({super.key, this.detail, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warning = AppColors.warning(context);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: warning.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_outlined, color: warning, size: 22),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Servis şu anda kullanılamıyor',
                  style: AppTextStyles.bodyMedium(
                    color: scheme.onSurface,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  detail ??
                      'Tahmin/analiz servisine (arassaha-ml) şu anda ulaşılamıyor. '
                          'Servisin çalıştığı bilgisayarın açık ve ağa bağlı olduğundan emin olup tekrar deneyin.',
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Tekrar Dene',
                    icon: Icons.refresh,
                    variant: AppButtonVariant.secondary,
                    onPressed: onRetry,
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
