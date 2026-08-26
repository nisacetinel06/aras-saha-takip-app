import 'package:flutter/material.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';

/// Ana Sayfa Turu VE bağlamsal ilk-karşılaşma ipuçları (risk rozeti, QR
/// tarama bilgi banner'ı QR tarafında ayrı bir yerel bileşen kullanır, ama
/// risk rozeti AYNI coach-mark mekanizmasını paylaşır) için TEK ortak
/// görünüm — showcaseview paketinin varsayılan (beyaz zemin/siyah metin)
/// tooltip'i yerine, uygulamanın kendi renk/tipografi sistemini (AppColors,
/// AppTextStyles) kullanır ki tur, geri kalan arayüzden görsel olarak
/// kopmasın (bkz. PROMPT madde 9 — Tasarım Sistemine Uyum).
///
/// Zemin rengi olarak BİLİNÇLİ olarak `AppColors.primary` (marka mavisi)
/// seçildi — nötr beyaz/gri bir tooltip, altındaki gerçek arayüzle karışıp
/// "bu bir coach-mark mı yoksa gerçek bir kart mı" belirsizliği yaratırdı;
/// dolu marka rengi bunu tek bakışta "geçici, öğretici bir katman" olarak
/// ayırt ettirir — [_QuickActionCard]'ın "bir şey BAŞLATIR" için dolu mavi
/// kullanma mantığıyla aynı görsel dil.
class CoachMarkStyle {
  CoachMarkStyle._();

  static Color background(BuildContext context) => AppColors.primary(context);

  /// bkz. accessibleOnColor (app_colors.dart) — dolu marka rengi zemininde
  /// WCAG kontrastını GARANTİ eder, sabit `Colors.white` varsaymaz.
  static Color foreground(BuildContext context) =>
      accessibleOnColor(background(context));

  static TextStyle title(BuildContext context) => AppTextStyles.headingMedium(
    color: foreground(context),
  ).copyWith(fontSize: 16);

  static TextStyle description(BuildContext context) =>
      AppTextStyles.bodyMedium(color: foreground(context));

  static BorderRadius get borderRadius => BorderRadius.circular(AppRadius.card);

  static const actionConfig = TooltipActionConfig(
    position: TooltipActionPosition.inside,
    alignment: MainAxisAlignment.spaceBetween,
    gapBetweenContentAndAction: AppSpacing.sm + 4,
    actionGap: AppSpacing.sm,
  );

  static TooltipActionButton _action(
    BuildContext context, {
    required TooltipDefaultActionType type,
    required String name,
    bool filled = false,
  }) {
    final fg = foreground(context);
    return TooltipActionButton(
      type: type,
      name: name,
      backgroundColor: filled ? fg : Colors.transparent,
      textStyle: TextStyle(
        color: filled ? background(context) : fg,
        fontWeight: filled ? FontWeight.w700 : FontWeight.w600,
      ),
    );
  }

  /// Ana Sayfa Turu'nun 1-4. adımlarında (son adım hariç) ortak Skip/Next/
  /// Previous aksiyonları. "Geç" HER ZAMAN görünür — turu zorla
  /// tamamlatmama ilkesi (bkz. PROMPT madde 5 ve mobile-design skill'inin
  /// "Provide Skip and Back buttons, never force a linear unskippable tour"
  /// kuralı). "Geri" yalnızca ilk adımda (henüz gidilecek önceki adım
  /// yokken) listeden ÇIKARILIR — [TooltipActionButton.hideActionWidgetForShowcase]
  /// KULLANILMAZ, çünkü bu filtre YALNIZCA [ShowcaseView.globalTooltipActions]
  /// için çalışır (bkz. showcaseview showcase_controller.dart
  /// `_getTooltipActions`); burada olduğu gibi her [Showcase]'e YEREL
  /// `tooltipActions` verildiğinde bu filtre tamamen atlanır ve TÜM
  /// butonlar (gizlenmesi istenenler dahil) görünür kalırdı. Son adımda
  /// "İleri" yerine [homeTourFinalStepActions]'daki "Tamam" kullanılır.
  static List<TooltipActionButton> homeTourActions(
    BuildContext context, {
    required bool isFirstStep,
  }) {
    return [
      if (!isFirstStep)
        _action(context, type: TooltipDefaultActionType.previous, name: 'Geri'),
      _action(context, type: TooltipDefaultActionType.skip, name: 'Geç'),
      _action(
        context,
        type: TooltipDefaultActionType.next,
        name: 'İleri',
        filled: true,
      ),
    ];
  }

  /// Son adımda kullanılır. showcaseview'da bir [Showcase]'e YEREL
  /// `tooltipActions` verilirse GLOBAL listenin TAMAMININ yerini alır
  /// (`hideActionWidgetForShowcase` filtresi burada uygulanmaz) — bu yüzden
  /// "Geri" ve "Geç" burada AYNEN tekrarlanır, yalnızca "İleri" yerine turu
  /// bitiren "Tamam" eklenir.
  static List<TooltipActionButton> homeTourFinalStepActions(
    BuildContext context,
  ) {
    return [
      _action(context, type: TooltipDefaultActionType.previous, name: 'Geri'),
      _action(context, type: TooltipDefaultActionType.skip, name: 'Geç'),
      _action(
        context,
        type: TooltipDefaultActionType.next,
        name: 'Tamam',
        filled: true,
      ),
    ];
  }

  /// Bağlamsal ilk-karşılaşma ipuçları (risk rozeti vb.) için: bunlar bir
  /// SIRA değil, TEK bir bilgilendirme adımı — Skip/Next/Previous YOK,
  /// yalnızca tek bir kapatma aksiyonu.
  static List<TooltipActionButton> singleHintAction(BuildContext context) {
    return [
      _action(
        context,
        type: TooltipDefaultActionType.skip,
        name: 'Anladım',
        filled: true,
      ),
    ];
  }
}
