import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/work_order.dart';
import '../providers/auth_provider.dart';
import '../providers/work_order_list_provider.dart';
import '../services/analytics_service.dart';
import '../widgets/app_button.dart';
import '../widgets/cache_age_note.dart';
import '../widgets/empty_state.dart';
import '../widgets/work_order_card.dart';
import 'work_order_detail_screen.dart';
import 'work_orders/create_work_order_screen.dart';

/// Görevler sekmesinin içeriği. MainShell'in ortak app bar'ı/alt navigasyonu
/// altında gösterilir; kendi Scaffold/AppBar'ı yoktur. Ana Sayfa'daki modül
/// kartlarından ya da Dashboard'daki özet kartlardan belirli bir statü
/// filtresiyle açılmak istendiğinde, MainShell bu ekran mount olmadan önce
/// `WorkOrderListProvider.setFilter(...)` çağırır (bkz. main_shell.dart).
class WorkOrderListScreen extends StatefulWidget {
  const WorkOrderListScreen({super.key});

  @override
  State<WorkOrderListScreen> createState() => _WorkOrderListScreenState();
}

class _WorkOrderListScreenState extends State<WorkOrderListScreen> {
  // Filtrelenmiş Liste Boş Durumu (bkz. widgets/empty_state.dart): arama
  // kutusunun kendi TextEditingController'ı burada, ekran seviyesinde
  // tutulur — "Tüm Filtreleri Temizle" ya da tek bir "Arama" chip'i
  // kaldırıldığında, provider'daki searchQuery'yi SIFIRLAMAK yetmez, kutunun
  // GÖRÜNEN metnini de temizlemek gerekir (aksi halde kullanıcı filtreyi
  // temizlese bile arama kutusunda eski metin görünmeye devam ederdi).
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('WorkOrderListScreen');
    // Ekran ilk açıldığında listeyi backend'den çek.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WorkOrderListProvider>().loadWorkOrders();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _clearAllFilters(WorkOrderListProvider provider) async {
    _searchController.clear();
    await provider.clearAllFilters();
  }

  /// Filtre yokken liste zaten boşsa (örn. teknisyenin hiç görevi yoksa)
  /// gösterilecek role-duyarlı açıklama — üç rolün de "boş liste" anlamı
  /// farklı olduğu için (teknisyen: kendisine atanan iş yok; dispeçer:
  /// ekibine atanan iş yok; yönetici: sistemde hiç kayıt yok).
  String _noDataSubtitle(AuthProvider auth) {
    if (auth.isTeknisyen) return 'Şu anda size atanmış bir görev bulunmuyor.';
    if (auth.isDispecer) {
      return 'Şu anda ekibinize atanmış bir iş emri bulunmuyor.';
    }
    return 'Sistemde henüz kayıtlı bir iş emri yok.';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Column(
      children: [
        _SearchBar(controller: _searchController),
        const _FilterBar(),
        Expanded(
          child: Consumer<WorkOrderListProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (provider.errorMessage != null) {
                return _ErrorState(
                  message: provider.errorMessage!,
                  onRetry: provider.loadWorkOrders,
                );
              }

              // Okuma Önbelleği (Modül 17): önbellekten dönüldüğünde
              // ("Kayıt bulunamadı" YA DA gerçek liste) her iki durumda da
              // önce bu not gösterilir — kullanıcı gördüğü verinin NE KADAR
              // eski olduğunu bilsin.
              final cacheNote = provider.isFromCache
                  ? CacheAgeNote(cachedAt: provider.cachedAt!)
                  : null;

              if (provider.workOrders.isEmpty) {
                // Aktif filtreleri (statü/önleyici bakım/arama — hangileri
                // doluysa) kaldırılabilir chip'lere çevirir; hiçbiri aktif
                // değilse (liste zaten filtresiz boşsa) boş kalır ve
                // EmptyState otomatik olarak "genel boş durum" görünümüne
                // (chipsiz, role-duyarlı subtitle + varsa birincil aksiyon)
                // geçer.
                final activeFilters = <ActiveFilterChip>[
                  if (provider.filterStatus != null)
                    ActiveFilterChip(
                      label: 'Durum: ${provider.filterStatus!.label}',
                      onRemove: () => provider.setFilter(null),
                    ),
                  if (provider.onlyPreventiveMaintenance)
                    ActiveFilterChip(
                      label: 'Sadece Önleyici Bakım',
                      onRemove: () =>
                          provider.setOnlyPreventiveMaintenance(false),
                    ),
                  if (provider.searchQuery.trim().isNotEmpty)
                    ActiveFilterChip(
                      label: 'Arama: "${provider.searchQuery.trim()}"',
                      onRemove: () {
                        _searchController.clear();
                        provider.setSearchQuery('');
                      },
                    ),
                ];

                return Column(
                  children: [
                    if (cacheNote != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: cacheNote,
                      ),
                    Expanded(
                      child: EmptyState(
                        icon: Icons.inbox_outlined,
                        title: activeFilters.isEmpty
                            ? 'Görev bulunmuyor'
                            : 'Bu filtreye uyan görev yok',
                        subtitle: activeFilters.isEmpty
                            ? _noDataSubtitle(auth)
                            : null,
                        activeFilters: activeFilters,
                        onClearFilters: activeFilters.isEmpty
                            ? null
                            : () => _clearAllFilters(provider),
                        onPrimaryAction: activeFilters.isEmpty && auth.canCreateWorkOrders
                            ? () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const CreateWorkOrderScreen(),
                                  ),
                                )
                            : null,
                        primaryActionLabel: 'Yeni İş Emri Oluştur',
                      ),
                    ),
                  ],
                );
              }

              return RefreshIndicator(
                onRefresh: provider.loadWorkOrders,
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                  itemCount:
                      provider.workOrders.length + (cacheNote != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (cacheNote != null) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: cacheNote,
                        );
                      }
                      index -= 1;
                    }
                    final workOrder = provider.workOrders[index];
                    return WorkOrderCard(
                      key: Key('work_order_card_${workOrder.id}'),
                      workOrder: workOrder,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => WorkOrderDetailScreen(
                              workOrderId: workOrder.id,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  const _SearchBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final provider = context.read<WorkOrderListProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: TextField(
        controller: controller,
        onChanged: provider.setSearchQuery,
        decoration: const InputDecoration(
          hintText: 'Görev ara (İş, başlık, adres)...',
          prefixIcon: Icon(Icons.search),
          isDense: true,
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WorkOrderListProvider>();
    final scheme = Theme.of(context).colorScheme;

    final filters = <String, WorkOrderStatus?>{
      'Tümü': null,
      'Açık': WorkOrderStatus.acik,
      'Yolda': WorkOrderStatus.yolda,
      'Sahada': WorkOrderStatus.sahada,
      'Çözüldü': WorkOrderStatus.cozuldu,
    };

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ...filters.entries.map((entry) {
            final isSelected = provider.filterStatus == entry.value;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: ChoiceChip(
                label: Text(entry.key),
                selected: isSelected,
                showCheckmark: false,
                labelStyle: TextStyle(
                  color: isSelected
                      ? scheme.onPrimary
                      : scheme.onSurfaceVariant,
                ),
                onSelected: (_) => provider.setFilter(entry.value),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: FilterChip(
              label: const Text('Önleyici Bakım'),
              avatar: Icon(
                Icons.build,
                size: 16,
                color: provider.onlyPreventiveMaintenance
                    ? scheme.onPrimary
                    : scheme.onSurfaceVariant,
              ),
              selected: provider.onlyPreventiveMaintenance,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: provider.onlyPreventiveMaintenance
                    ? scheme.onPrimary
                    : scheme.onSurfaceVariant,
              ),
              onSelected: provider.setOnlyPreventiveMaintenance,
            ),
          ),
        ],
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
