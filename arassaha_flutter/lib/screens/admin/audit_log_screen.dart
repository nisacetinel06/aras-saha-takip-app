import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/audit_log_entry.dart';
import '../../providers/audit_log_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;

String _formatDate(DateTime date) {
  return '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
}

/// Denetim Logu Paneli — sistemdeki TÜM state-changing işlemlerin (login
/// denemeleri, kullanıcı/cihaz yönetimi, stok hareketleri, KVKK talepleri,
/// otomatik dosya temizliği) TEK, birleşik bir görünümü. Sadece yönetici
/// erişebilir — bkz. user_management_list_screen.dart'taki AYNI ikinci
/// koruma katmanı deseni (bir teknisyen/dispeçer deep link ile buraya
/// ulaşırsa build() içinde geri yönlendirilir).
///
/// Var olan modül-özel işlem geçmişleri (Cihaz Yönetimi'nin/Kullanıcı
/// Düzenleme'nin kendi ekranındaki geçmiş) bu ekrandan TAMAMEN bağımsızdır —
/// burası yalnızca backend'deki services/auditLogAggregator.js'in ürettiği
/// YENİ, salt okunur bir birleşik görünümü tüketir.
class AuditLogScreen extends StatefulWidget {
  const AuditLogScreen({super.key});

  @override
  State<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends State<AuditLogScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('AuditLogScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuditLogProvider>().fetchInitial();
    });
  }

  Future<void> _pickDateRange() async {
    final provider = context.read<AuditLogProvider>();
    final now = DateTime.now();
    final initialRange =
        provider.fromDateFilter != null && provider.toDateFilter != null
        ? DateTimeRange(start: provider.fromDateFilter!, end: provider.toDateFilter!)
        : null;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: initialRange,
    );
    if (picked == null || !mounted) return;

    // toDate'i günün SONUNA (23:59:59) taşı — aksi halde seçilen bitiş
    // gününün kendisindeki kayıtlar (o günün 00:00'ından SONRAKİ hiçbir
    // kaydı) filtre dışında kalırdı; kullanıcı "bugüne kadar" seçtiğinde
    // bugünün kayıtlarını görmeyi bekler.
    final endOfDay = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
    provider.setDateRange(picked.start, endOfDay);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (!auth.isYonetici) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bu ekrana erişim yetkiniz yok.')),
        );
        Navigator.of(context).pop();
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final provider = context.watch<AuditLogProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'Güvenlik & Denetim Logu'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _FilterBar(onPickDateRange: _pickDateRange),
            Expanded(
              child: Builder(
                builder: (context) {
                  if (provider.isLoading && provider.entries.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (provider.errorMessage != null && provider.entries.isEmpty) {
                    return EmptyState(
                      icon: Icons.error_outline,
                      title: 'Denetim kayıtları yüklenemedi',
                      subtitle: provider.errorMessage!,
                      onPrimaryAction: () => provider.fetchInitial(),
                      primaryActionLabel: 'Tekrar Dene',
                      primaryActionVariant: AppButtonVariant.secondary,
                    );
                  }

                  if (provider.entries.isEmpty) {
                    final activeFilters = <ActiveFilterChip>[
                      if (provider.categoryFilter != null)
                        ActiveFilterChip(
                          label: 'Kategori: ${provider.categoryFilter!.label}',
                          onRemove: () => provider.setCategory(null),
                        ),
                      if (provider.fromDateFilter != null && provider.toDateFilter != null)
                        ActiveFilterChip(
                          label:
                              'Tarih: ${_formatDate(provider.fromDateFilter!)} - ${_formatDate(provider.toDateFilter!)}',
                          onRemove: () => provider.setDateRange(null, null),
                        ),
                    ];

                    return EmptyState(
                      icon: Icons.fact_check_outlined,
                      title: activeFilters.isEmpty
                          ? 'Henüz hiçbir denetim kaydı yok'
                          : 'Bu filtreye uyan kayıt yok',
                      subtitle: activeFilters.isEmpty
                          ? 'Sistemde bir işlem yapıldıkça burada görünecek.'
                          : null,
                      activeFilters: activeFilters,
                      onClearFilters: activeFilters.isEmpty ? null : provider.clearAllFilters,
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () => provider.fetchInitial(),
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.xl,
                      ),
                      itemCount: provider.entries.length + 1, // +1: alt "Daha Fazla Yükle" satırı
                      itemBuilder: (context, index) {
                        if (index == provider.entries.length) {
                          return _LoadMoreFooter(
                            hasMore: provider.hasMore,
                            isLoadingMore: provider.isLoadingMore,
                            errorMessage: provider.loadMoreErrorMessage,
                            totalCount: provider.totalCount,
                            shownCount: provider.entries.length,
                            onLoadMore: () => provider.loadMore(),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _AuditLogRow(entry: provider.entries[index]),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final VoidCallback onPickDateRange;
  const _FilterBar({required this.onPickDateRange});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AuditLogProvider>();
    final scheme = Theme.of(context).colorScheme;

    final filters = <String, AuditLogCategory?>{
      'Tümü': null,
      for (final category in AuditLogCategory.values) category.label: category,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: filters.entries.map((entry) {
              final isSelected = provider.categoryFilter == entry.value;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: ChoiceChip(
                  label: Text(entry.key),
                  selected: isSelected,
                  showCheckmark: false,
                  labelStyle: TextStyle(
                    color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
                  ),
                  onSelected: (_) => provider.setCategory(entry.value),
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPickDateRange,
                  icon: const Icon(Icons.date_range_outlined, size: 18),
                  label: Text(
                    provider.fromDateFilter != null && provider.toDateFilter != null
                        ? '${_formatDate(provider.fromDateFilter!)} - ${_formatDate(provider.toDateFilter!)}'
                        : 'Tarih Aralığı Seç',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              if (provider.fromDateFilter != null || provider.toDateFilter != null) ...[
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  tooltip: 'Tarih filtresini kaldır',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => provider.setDateRange(null, null),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AuditLogRow extends StatelessWidget {
  final AuditLogEntry entry;
  const _AuditLogRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categoryColor = auditCategoryColor(context, entry.category);
    final categoryLabel = entry.category?.label ?? entry.categoryRaw;
    final categoryIcon = entry.category?.icon ?? Icons.history;

    return AppCard(
      // GÜVENLİK VURGUSU: yalnızca "dikkat çekici" (başarısız giriş gibi)
      // kayıtlarda kenar şeridi kullanılır — kategori rengiyle KARIŞTIRILMAZ
      // (bkz. dosya başı not, görev talimatı). Kategori kendi rengini
      // aşağıdaki ikon dairesinde taşır.
      statusStripeColor: entry.isSecurityAlert ? AppColors.danger(context) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Icon(categoryIcon, size: 18, color: categoryColor),
          ),
          const SizedBox(width: AppSpacing.sm + 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.actorName,
                        style: Theme.of(context).textTheme.headlineSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      formatRelativeTime(entry.timestamp),
                      style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$categoryLabel · ${entry.actionType}',
                  style: TextStyle(
                    color: categoryColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (entry.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    entry.description,
                    style: AppTextStyles.bodyMedium(color: scheme.onSurface),
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

class _LoadMoreFooter extends StatelessWidget {
  final bool hasMore;
  final bool isLoadingMore;
  final String? errorMessage;
  final int totalCount;
  final int shownCount;
  final VoidCallback onLoadMore;

  const _LoadMoreFooter({
    required this.hasMore,
    required this.isLoadingMore,
    required this.errorMessage,
    required this.totalCount,
    required this.shownCount,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Center(
          child: Text(
            '$shownCount / $totalCount kayıt gösteriliyor',
            style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          if (errorMessage != null) ...[
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          SizedBox(
            width: double.infinity,
            child: AppButton(
              label: 'Daha Fazla Yükle',
              icon: Icons.expand_more,
              variant: AppButtonVariant.secondary,
              isLoading: isLoadingMore,
              onPressed: onLoadMore,
            ),
          ),
        ],
      ),
    );
  }
}
