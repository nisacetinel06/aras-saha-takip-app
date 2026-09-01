import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/feedback_item.dart';
import '../../providers/feedback_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/work_order_card.dart' show formatRelativeTime;
import 'feedback_detail_screen.dart';
import 'submit_feedback_screen.dart';

// bekliyor=sarı, incelendi=mavi, kapatildi=yeşil — isg_report_list_screen.dart
// içindeki _statusColor ile AYNI eşleme (bkz. görev talimatı madde 5).
Color _statusColor(BuildContext context, FeedbackStatus status) {
  switch (status) {
    case FeedbackStatus.bekliyor:
      return AppColors.warning(context);
    case FeedbackStatus.incelendi:
      return AppColors.primary(context);
    case FeedbackStatus.kapatildi:
      return AppColors.success(context);
  }
}

/// Öneri / Şikayet Kutusu (Modül 17) — bildirim listesi. İSG bildirim
/// listesinin (screens/isg/isg_report_list_screen.dart) doğrudan bir kopyası
/// — aynı AppCard, aynı durum şeridi renkleri, aynı filtre çubuğu deseni.
/// Görünürlük (teknisyen/dispeçer kendi, yönetici hepsi) backend'de
/// uygulanır (bkz. routes/feedback.js GET /) — bu ekran hiçbir rol kontrolü
/// yapmaz, sunucunun döndürdüğü listeyi olduğu gibi gösterir.
class FeedbackListScreen extends StatefulWidget {
  const FeedbackListScreen({super.key});

  @override
  State<FeedbackListScreen> createState() => _FeedbackListScreenState();
}

class _FeedbackListScreenState extends State<FeedbackListScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('FeedbackListScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FeedbackProvider>().fetchFeedbackItems();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FeedbackProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'Öneri / Şikayet'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SubmitFeedbackScreen()),
          );
          if (context.mounted) {
            context.read<FeedbackProvider>().fetchFeedbackItems();
          }
        },
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Yeni Bildirim'),
      ),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (provider.isListLoading && provider.items.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.listErrorMessage != null && provider.items.isEmpty) {
              return EmptyState(
                icon: Icons.error_outline,
                title: 'Bildirimler yüklenemedi',
                subtitle: provider.listErrorMessage!,
                onPrimaryAction: provider.fetchFeedbackItems,
                primaryActionLabel: 'Tekrar Dene',
                primaryActionVariant: AppButtonVariant.secondary,
              );
            }

            return RefreshIndicator(
              onRefresh: provider.fetchFeedbackItems,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.xl + 64,
                ),
                children: [
                  _SummaryStrip(items: provider.items),
                  const SizedBox(height: AppSpacing.md),
                  _FilterBar(provider: provider),
                  const SizedBox(height: AppSpacing.sm),
                  if (provider.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xl),
                      child: EmptyState(
                        icon: Icons.add_comment_outlined,
                        title: provider.filterStatus == null
                            ? 'Bildirim bulunmuyor'
                            : 'Bu filtreye uyan bildirim yok',
                        activeFilters: provider.filterStatus == null
                            ? null
                            : [
                                ActiveFilterChip(
                                  label:
                                      'Durum: ${provider.filterStatus!.label}',
                                  onRemove: () => provider.setFilter(null),
                                ),
                              ],
                        onClearFilters: provider.filterStatus == null
                            ? null
                            : () => provider.setFilter(null),
                      ),
                    )
                  else
                    ...provider.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _FeedbackCard(
                          item: item,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  FeedbackDetailScreen(feedbackId: item.id),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  final List<FeedbackItem> items;
  const _SummaryStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = items.length;
    final bekliyor = items
        .where((r) => r.status == FeedbackStatus.bekliyor)
        .length;
    final incelendi = items
        .where((r) => r.status == FeedbackStatus.incelendi)
        .length;
    final kapatildi = items
        .where((r) => r.status == FeedbackStatus.kapatildi)
        .length;

    return AppCard(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm + 4,
        horizontal: AppSpacing.sm,
      ),
      child: Text.rich(
        TextSpan(
          style: AppTextStyles.bodyMedium(color: scheme.onSurface),
          children: [
            TextSpan(
              text: '$total',
              style: AppTextStyles.headingMedium(
                color: AppColors.primary(context),
              ),
            ),
            const TextSpan(text: ' bildirim, '),
            TextSpan(
              text: '$bekliyor',
              style: AppTextStyles.headingMedium(
                color: AppColors.warning(context),
              ),
            ),
            const TextSpan(text: ' bekliyor, '),
            TextSpan(
              text: '$incelendi',
              style: AppTextStyles.headingMedium(
                color: AppColors.primary(context),
              ),
            ),
            const TextSpan(text: ' incelendi, '),
            TextSpan(
              text: '$kapatildi',
              style: AppTextStyles.headingMedium(
                color: AppColors.success(context),
              ),
            ),
            const TextSpan(text: ' kapatıldı'),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final FeedbackProvider provider;
  const _FilterBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filters = <String, FeedbackStatus?>{
      'Tümü': null,
      'Bekliyor': FeedbackStatus.bekliyor,
      'İncelendi': FeedbackStatus.incelendi,
      'Kapatıldı': FeedbackStatus.kapatildi,
    };

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.entries.map((entry) {
          final isSelected = provider.filterStatus == entry.value;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs + 4),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              onSelected: (_) => provider.setFilter(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final FeedbackItem item;
  final VoidCallback onTap;
  const _FeedbackCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      statusStripeColor: _statusColor(context, item.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.category.icon, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.category.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              _StatusBadge(status: item.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.description,
            style: Theme.of(context).textTheme.bodyLarge,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              // Tek gerçek fark (bkz. görev talimatı madde 5): anonim bir
              // kayıtta gönderen adı yerine "Anonim Kullanıcı" + nötr bir
              // kişi ikonu — normal kayıtta İSG ile BİREBİR AYNI satır.
              Icon(
                item.isAnonymous ? Icons.person_off_outlined : Icons.person_outline,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  item.isAnonymous
                      ? 'Anonim Kullanıcı'
                      : (item.submittedBy?.name ?? 'Bilinmiyor'),
                  style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                formatRelativeTime(item.createdAt),
                style: AppTextStyles.caption(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final FeedbackStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: accessibleOnColor(color),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
