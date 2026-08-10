import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/completed_work_orders_provider.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/sort_direction_control.dart';
import '../../widgets/work_order_card.dart';
import '../work_order_detail_screen.dart';
import '../work_orders/completed_work_orders_screen.dart';

/// "Tamamlanan İş Emirlerim" bölümü — Ana Sayfa'da yalnızca teknisyen
/// rolündeyken gösterilir (bkz. home_screen.dart, HomeScreen zaten
/// initState'inde [CompletedWorkOrdersProvider.loadInitial]'ı tetikler,
/// bu widget yalnızca SUNUM ve arama/sıralama ETKİLEŞİMİNDEN sorumludur).
///
/// Arama debounce'lu (400ms) tutulur: her tuş vuruşunda backend'e istek
/// atmak (WorkOrderListProvider'ın istemci-taraflı aramasının aksine, burası
/// arama/sıralamayı SUNUCUYA gönderir — bkz. CompletedWorkOrdersProvider
/// dokümantasyonu) gereksiz ağ trafiği yaratırdı.
class CompletedWorkOrdersSection extends StatefulWidget {
  const CompletedWorkOrdersSection({super.key});

  @override
  State<CompletedWorkOrdersSection> createState() =>
      _CompletedWorkOrdersSectionState();
}

class _CompletedWorkOrdersSectionState
    extends State<CompletedWorkOrdersSection> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      context.read<CompletedWorkOrdersProvider>().setSearchQuery(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final provider = context.watch<CompletedWorkOrdersProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Tamamlanan İş Emirlerim',
                style: AppTextStyles.headingMedium(color: scheme.onSurface),
              ),
            ),
            SortDirectionControl(
              descending: provider.sortDescending,
              onChanged: provider.setSortDescending,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          controller: _searchController,
          onChanged: _onSearchChanged,
          decoration: const InputDecoration(
            hintText: 'Ara (başlık, iş emri no, ekipman)…',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SectionBody(provider: provider),
      ],
    );
  }
}

class _SectionBody extends StatelessWidget {
  final CompletedWorkOrdersProvider provider;
  const _SectionBody({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (provider.errorMessage != null) {
      return _InlineError(
        message: provider.errorMessage!,
        onRetry: provider.loadInitial,
      );
    }

    if (provider.items.isEmpty) {
      return _InlineEmptyState(
        isSearching: provider.searchQuery.trim().isNotEmpty,
      );
    }

    final preview = provider.items
        .take(CompletedWorkOrdersProvider.previewLimit)
        .toList();

    return Column(
      children: [
        // horizontalMargin: 0 — Ana Sayfa'nın ListView'ı zaten AppSpacing.md
        // (16px) yatay boşluk uyguluyor; kartın kendi varsayılan 12px'i
        // (bkz. work_order_card.dart) ÜSTÜNE binerse kartlar sayfadaki diğer
        // her şeyden (Özet şeridi, Çabuk Erişim) daha içeri kaymış görünürdü.
        for (final workOrder in preview)
          WorkOrderCard(
            workOrder: workOrder,
            showCompletedDate: true,
            horizontalMargin: 0,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    WorkOrderDetailScreen(workOrderId: workOrder.id),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Tümünü Gör',
              icon: Icons.history,
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const CompletedWorkOrdersScreen(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  final bool isSearching;
  const _InlineEmptyState({required this.isSearching});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        children: [
          Icon(
            Icons.task_alt_outlined,
            size: 40,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            isSearching
                ? 'Aramanızla eşleşen tamamlanmış iş emri bulunamadı.'
                : 'Henüz tamamlanmış bir iş emriniz yok — bir iş emrini "Çözüldü" durumuna getirdiğinizde burada görünecek.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _InlineError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          Icon(
            Icons.error_outline,
            size: 32,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          AppButton(label: 'Tekrar Dene', onPressed: onRetry),
        ],
      ),
    );
  }
}
