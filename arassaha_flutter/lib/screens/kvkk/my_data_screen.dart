import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/kvkk_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';
import 'aydinlatma_metni_screen.dart';
import 'deletion_request_screen.dart';

/// "Kişisel Verilerim ve Gizlilik" (KVKK Uyum Modülü) — Profil ekranından
/// (Modül 8) erişilir. Kullanıcının kendi verisinin SAYISAL özetini ve
/// aydınlatma metnine erişimi gösterir; asıl silme/anonimleştirme talebi
/// ayrı bir ekrandan (DeletionRequestScreen) başlatılır.
class MyDataScreen extends StatefulWidget {
  const MyDataScreen({super.key});

  @override
  State<MyDataScreen> createState() => _MyDataScreenState();
}

class _MyDataScreenState extends State<MyDataScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('MyDataScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KvkkProvider>().fetchMyDataSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KvkkProvider>();
    final scheme = Theme.of(context).colorScheme;
    final summary = provider.dataSummary;

    return Scaffold(
      appBar: const AppTopBar(title: 'Kişisel Verilerim ve Gizlilik'),
      body: Builder(
        builder: (context) {
          if (provider.isLoadingSummary && summary == null) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.summaryErrorMessage != null && summary == null) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Verileriniz yüklenemedi',
              subtitle: provider.summaryErrorMessage!,
              onPrimaryAction: () =>
                  context.read<KvkkProvider>().fetchMyDataSummary(),
              primaryActionLabel: 'Tekrar Dene',
              primaryActionVariant: AppButtonVariant.secondary,
            );
          }

          if (summary == null) return const SizedBox.shrink();

          return RefreshIndicator(
            onRefresh: () => context.read<KvkkProvider>().fetchMyDataSummary(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: 'Aydınlatma Metnini Oku',
                    icon: Icons.description_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AydinlatmaMetniScreen(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Sistemde Hakkımda Bulunan Veriler',
                  style: AppTextStyles.headingMedium(color: scheme.onSurface),
                ),
                const SizedBox(height: AppSpacing.sm + 4),
                _SummaryCard(
                  icon: Icons.badge_outlined,
                  label: 'Profil Bilgisi',
                  value:
                      '${summary.profileName} · Sicil No: ${summary.profileSicilNo}',
                ),
                const SizedBox(height: AppSpacing.sm),
                _SummaryCard(
                  icon: Icons.shield_outlined,
                  label: 'İSG Bildirimi',
                  value: '${summary.submittedIsgReportsCount} bildirim',
                ),
                const SizedBox(height: AppSpacing.sm),
                _SummaryCard(
                  icon: Icons.assignment_outlined,
                  label: 'İş Emri Kaydı',
                  value: '${summary.assignedWorkOrdersCount} iş emri',
                ),
                const SizedBox(height: AppSpacing.sm),
                _SummaryCard(
                  icon: Icons.photo_library_outlined,
                  label: 'Fotoğraf',
                  value: '${summary.uploadedPhotosCount} fotoğraf',
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    label: 'Veri Silme Talebi Oluştur',
                    icon: Icons.delete_outline,
                    variant: AppButtonVariant.destructive,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DeletionRequestScreen(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      child: Row(
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.bodyMedium(color: scheme.onSurface),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
