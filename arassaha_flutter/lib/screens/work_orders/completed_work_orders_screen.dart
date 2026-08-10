import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/completed_work_orders_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/sort_direction_control.dart';
import '../../widgets/work_order_card.dart';
import '../work_order_detail_screen.dart';

/// "Tamamlanan İş Emirlerim" (Ana Sayfa, teknisyen) bölümünün "Tümünü Gör"
/// hedefi — [CompletedWorkOrdersProvider] ile AYNI, tek global örneği
/// paylaşır (bkz. main.dart), bu yüzden Ana Sayfa'da zaten yüklenmiş ilk
/// sayfayı SIFIRDAN yeniden çekmez; yalnızca kaydırma sonuna gelindiğinde
/// [CompletedWorkOrdersProvider.loadMore] ile listeyi büyütür.
class CompletedWorkOrdersScreen extends StatefulWidget {
  const CompletedWorkOrdersScreen({super.key});

  @override
  State<CompletedWorkOrdersScreen> createState() =>
      _CompletedWorkOrdersScreenState();
}

class _CompletedWorkOrdersScreenState
    extends State<CompletedWorkOrdersScreen> {
  late final TextEditingController _searchController;
  final _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('CompletedWorkOrdersScreen');
    _searchController = TextEditingController(
      text: context.read<CompletedWorkOrdersProvider>().searchQuery,
    );
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Sona 200px kalınca bir sonraki sayfa istenir — kullanıcı kaydırmayı
    // TAM sona vardırmadan önce yeni kayıtlar hazır olsun diye.
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<CompletedWorkOrdersProvider>().loadMore();
    }
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

    return Scaffold(
      appBar: const AppTopBar(title: 'Tamamlanan İş Emirlerim'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Ara (başlık, iş emri no, ekipman)…',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  provider.isLoading
                      ? ' '
                      : '${provider.items.length} kayıt',
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                ),
                SortDirectionControl(
                  descending: provider.sortDescending,
                  onChanged: provider.setSortDescending,
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(context, provider)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, CompletedWorkOrdersProvider provider) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.errorMessage != null) {
      return _ErrorState(
        message: provider.errorMessage!,
        onRetry: provider.loadInitial,
      );
    }

    if (provider.items.isEmpty) {
      return _EmptyState(isSearching: provider.searchQuery.trim().isNotEmpty);
    }

    return RefreshIndicator(
      onRefresh: provider.loadInitial,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
        itemCount: provider.items.length + 1,
        itemBuilder: (context, index) {
          if (index == provider.items.length) {
            return _ListFooter(provider: provider);
          }
          final workOrder = provider.items[index];
          return WorkOrderCard(
            workOrder: workOrder,
            showCompletedDate: true,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WorkOrderDetailScreen(workOrderId: workOrder.id),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Listenin altındaki durum satırı: sayfalanıyor (spinner), hata (tekrar
/// dene) ya da her ikisi de değilse (tüm kayıtlar zaten yüklendi) boş.
class _ListFooter extends StatelessWidget {
  final CompletedWorkOrdersProvider provider;
  const _ListFooter({required this.provider});

  @override
  Widget build(BuildContext context) {
    if (provider.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (provider.loadMoreErrorMessage != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Column(
          children: [
            Text(
              provider.loadMoreErrorMessage!,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            AppButton(
              label: 'Tekrar Dene',
              variant: AppButtonVariant.text,
              onPressed: provider.loadMore,
            ),
          ],
        ),
      );
    }

    return const SizedBox(height: AppSpacing.md);
  }
}

class _EmptyState extends StatelessWidget {
  final bool isSearching;
  const _EmptyState({required this.isSearching});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.task_alt_outlined,
                    size: 56,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    isSearching
                        ? 'Aramanızla eşleşen tamamlanmış iş emri bulunamadı.'
                        : 'Henüz tamamlanmış bir iş emriniz yok.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 56,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            AppButton(label: 'Tekrar Dene', onPressed: onRetry),
          ],
        ),
      ),
    );
  }
}
