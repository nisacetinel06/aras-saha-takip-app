import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/equipment_risk.dart' show RiskLevel;
import '../../models/maintenance_recommendation.dart';
import '../../providers/auth_provider.dart';
import '../../providers/maintenance_provider.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/maintenance_recommendation_card.dart';

enum _RecommendationFilter { tumu, yuksek, orta, bekleyen, planlanan }

/// [_RecommendationFilter]'ın Filtrelenmiş Liste Boş Durumu (bkz.
/// widgets/empty_state.dart) chip'inde gösterilecek etiketi — bu ekranda
/// filtreler (İş Emirleri/Ekipman ekranlarının aksine) BİRLEŞTİRİLEMEZ, tek
/// seferde en fazla biri aktif olabilir (radio davranışı, bkz. _FilterBar).
extension on _RecommendationFilter {
  String? get activeFilterLabel {
    switch (this) {
      case _RecommendationFilter.tumu:
        return null;
      case _RecommendationFilter.yuksek:
        return 'Aciliyet: Yüksek';
      case _RecommendationFilter.orta:
        return 'Aciliyet: Orta';
      case _RecommendationFilter.bekleyen:
        return 'Durum: Bekleyen';
      case _RecommendationFilter.planlanan:
        return 'Durum: Planlanan';
    }
  }
}

/// Kestirimci Bakım Planlama (Modül 12) — merkezi öneri listesi ekranı.
///
/// AYRIM: Bu ekranda görüntülenen öneriler bir ML modelinin çıktısı DEĞİLDİR;
/// Modül 9'un ürettiği risk skorunun backend'de (routes/maintenance.js) SABİT
/// eşiklerle bir bakım önerisine çevrildiği bir iş kuralı/otomasyon
/// katmanıdır. Yalnızca yönetici/dispeçer rolünde Ana Sayfa modül
/// ızgarasından erişilir (bkz. home_screen.dart).
class MaintenanceRecommendationsScreen extends StatefulWidget {
  const MaintenanceRecommendationsScreen({super.key});

  @override
  State<MaintenanceRecommendationsScreen> createState() =>
      _MaintenanceRecommendationsScreenState();
}

class _MaintenanceRecommendationsScreenState
    extends State<MaintenanceRecommendationsScreen> {
  _RecommendationFilter _filter = _RecommendationFilter.tumu;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _applyFilter(_RecommendationFilter.tumu),
    );
  }

  Future<void> _applyFilter(_RecommendationFilter filter) async {
    setState(() => _filter = filter);
    final provider = context.read<MaintenanceProvider>();
    switch (filter) {
      case _RecommendationFilter.tumu:
        await provider.fetchRecommendations();
        break;
      case _RecommendationFilter.yuksek:
        await provider.fetchRecommendations(urgencyFilter: 'yuksek');
        break;
      case _RecommendationFilter.orta:
        await provider.fetchRecommendations(urgencyFilter: 'orta');
        break;
      case _RecommendationFilter.bekleyen:
        await provider.fetchRecommendations(statusFilter: 'onerildi');
        break;
      case _RecommendationFilter.planlanan:
        await provider.fetchRecommendations(statusFilter: 'planlandi');
        break;
    }
  }

  Future<void> _refreshRules() async {
    final provider = context.read<MaintenanceProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final result = await provider.refreshRecommendationRules();

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result != null
              ? 'Öneriler güncellendi: ${result.created} yeni, ${result.updated} güncellendi, ${result.skipped} atlandı.'
              : (provider.refreshRulesError ?? 'Öneriler güncellenemedi.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final provider = context.watch<MaintenanceProvider>();

    return Scaffold(
      // A2: "Yeniden Hesapla" veri değiştiren gerçek bir aksiyondur — yalnızca
      // simge + tooltip olarak app bar'a gömülüyse fark edilme riski yüksek
      // (skill'in "önemli aksiyonlar yalnızca app bar'da yaşamamalı" kuralı).
      // Etiketli, gövdede görünür bir buton olarak taşındı (bkz. _SummaryStrip).
      appBar: const AppTopBar(title: 'Bakım Planlama'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _SummaryStrip(
              recommendations: provider.recommendations,
              showRefreshButton: auth.isYonetici,
              isRefreshing: provider.isRefreshingRules,
              onRefresh: _refreshRules,
            ),
            _FilterBar(selected: _filter, onSelected: _applyFilter),
            Expanded(
              child: _Body(
                provider: provider,
                onRetry: () => _applyFilter(_filter),
                activeFilter: _filter,
                onClearFilter: () => _applyFilter(_RecommendationFilter.tumu),
                showRefreshAction: auth.isYonetici,
                isRefreshing: provider.isRefreshingRules,
                onRefresh: _refreshRules,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final List<MaintenanceRecommendation> recommendations;
  final bool showRefreshButton;
  final bool isRefreshing;
  final VoidCallback onRefresh;
  const _SummaryStrip({
    required this.recommendations,
    required this.showRefreshButton,
    required this.isRefreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = recommendations.length;
    final highCount = recommendations
        .where((r) => r.urgencyLevel == RiskLevel.yuksek)
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 4,
        ),
        child: Row(
          children: [
            Icon(Icons.build_circle_outlined, size: 20, color: scheme.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                highCount > 0
                    ? '$total öneri, $highCount yüksek öncelikli'
                    : '$total öneri',
                style: AppTextStyles.bodyMedium(
                  color: scheme.onSurface,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            // A2: yönetici için "Modül 9 risk skorlarına göre yeniden hesapla"
            // aksiyonu — artık etiketli, gövdede görünür bir buton (öncesinde
            // yalnızca app bar'da bir simgeydi, bkz. dosya üstündeki not).
            if (showRefreshButton) ...[
              const SizedBox(width: AppSpacing.sm),
              AppButton(
                label: 'Yenile',
                icon: Icons.refresh,
                variant: AppButtonVariant.text,
                isLoading: isRefreshing,
                onPressed: isRefreshing ? null : onRefresh,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final _RecommendationFilter selected;
  final void Function(_RecommendationFilter) onSelected;
  const _FilterBar({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = {
      _RecommendationFilter.tumu: 'Tümü',
      _RecommendationFilter.yuksek: 'Yüksek',
      _RecommendationFilter.orta: 'Orta',
      _RecommendationFilter.bekleyen: 'Bekleyen',
      _RecommendationFilter.planlanan: 'Planlanan',
    };

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: labels.entries.map((entry) {
          final isSelected = selected == entry.key;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: ChoiceChip(
              label: Text(entry.value),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              onSelected: (_) => onSelected(entry.key),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final MaintenanceProvider provider;
  final Future<void> Function() onRetry;
  final _RecommendationFilter activeFilter;
  final VoidCallback onClearFilter;
  final bool showRefreshAction;
  final bool isRefreshing;
  final Future<void> Function() onRefresh;

  const _Body({
    required this.provider,
    required this.onRetry,
    required this.activeFilter,
    required this.onClearFilter,
    required this.showRefreshAction,
    required this.isRefreshing,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading && provider.recommendations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Bakım önerileri yüklenemedi',
        subtitle: provider.errorMessage!,
        onPrimaryAction: onRetry,
        primaryActionLabel: 'Tekrar Dene',
        primaryActionVariant: AppButtonVariant.secondary,
      );
    }

    if (provider.recommendations.isEmpty) {
      // Bu ekranda filtreler BİRLEŞTİRİLEMEZ (bkz. _RecommendationFilter
      // activeFilterLabel dokümantasyonu) — en fazla TEK bir chip olur.
      final label = activeFilter.activeFilterLabel;
      final activeFilters = label != null
          ? [ActiveFilterChip(label: label, onRemove: onClearFilter)]
          : const <ActiveFilterChip>[];

      return EmptyState(
        icon: Icons.task_alt,
        title: activeFilters.isEmpty
            ? 'Bakım önerisi bulunmuyor'
            : 'Bu filtrede bakım önerisi bulunmuyor',
        subtitle: activeFilters.isEmpty
            ? 'Şu anda hiçbir bakım önerisi yok. Öneriler, ekipman risk '
                  'skorları güncellendiğinde otomatik oluşturulur.'
            : null,
        activeFilters: activeFilters,
        onClearFilters: activeFilters.isEmpty ? null : onClearFilter,
        onPrimaryAction: activeFilters.isEmpty && showRefreshAction
            ? (isRefreshing ? null : onRefresh)
            : null,
        primaryActionLabel: 'Önerileri Yeniden Hesapla',
      );
    }

    return RefreshIndicator(
      onRefresh: onRetry,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        itemCount: provider.recommendations.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: MaintenanceRecommendationCard(
              recommendation: provider.recommendations[index],
            ),
          );
        },
      ),
    );
  }
}
