import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/kvkk_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';

/// KVKK Aydınlatma Metni — tam metni gösterir. Metin backend'den (bkz.
/// routes/kvkk.js GET /aydinlatma-metni) okunur; ileride hukuk/KVKK uyum
/// birimi metni güncellediğinde uygulama sürümünü yükseltmeye gerek kalmaz.
///
/// ÖNEMLİ: Bu metin TASLAKTIR. `draftWarning` uyarısı, hukuk birimi onayı
/// gelene kadar HER ZAMAN belirgin şekilde gösterilmeli — kaldırılmamalıdır
/// (bkz. görev talimatı, routes/kvkk.js AYDINLATMA_METNI notu).
class AydinlatmaMetniScreen extends StatefulWidget {
  const AydinlatmaMetniScreen({super.key});

  @override
  State<AydinlatmaMetniScreen> createState() => _AydinlatmaMetniScreenState();
}

class _AydinlatmaMetniScreenState extends State<AydinlatmaMetniScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('AydinlatmaMetniScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KvkkProvider>().fetchAydinlatmaMetni();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KvkkProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: const AppTopBar(title: 'Aydınlatma Metni'),
      body: Builder(
        builder: (context) {
          if (provider.isLoadingAydinlatmaMetni &&
              provider.aydinlatmaMetni == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.aydinlatmaMetniErrorMessage != null &&
              provider.aydinlatmaMetni == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 56, color: scheme.error),
                    const SizedBox(height: AppSpacing.sm + 4),
                    Text(
                      provider.aydinlatmaMetniErrorMessage!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppButton(
                      label: 'Tekrar Dene',
                      onPressed: () =>
                          context.read<KvkkProvider>().fetchAydinlatmaMetni(),
                    ),
                  ],
                ),
              ),
            );
          }

          final content = provider.aydinlatmaMetni;
          if (content == null) return const SizedBox.shrink();

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (provider.draftWarning != null &&
                  provider.draftWarning!.isNotEmpty)
                _DraftWarningBanner(text: provider.draftWarning!),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: SelectableText(
                  content,
                  style: AppTextStyles.bodyMedium(
                    color: scheme.onSurface,
                  ).copyWith(height: 1.6),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DraftWarningBanner extends StatelessWidget {
  final String text;
  const _DraftWarningBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    final warningColor = AppColors.warning(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: warningColor.withValues(alpha: isDark ? 0.22 : 0.14),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: warningColor.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: warningColor, size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: warningColor,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
