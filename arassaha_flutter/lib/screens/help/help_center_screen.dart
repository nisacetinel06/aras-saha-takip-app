import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/faq_content.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/empty_state.dart';

/// Yardım Merkezi / SSS — kullanıcının istediği zaman geri dönüp "bu özellik
/// ne işe yarıyor" sorusuna cevap bulabileceği KALICI bir ekran. Onboarding
/// turunun (bkz. settings_screen.dart _AppTourSection) aksine tek seferlik
/// değildir ve bir "tekrar göster" mekanizması gerektirmez — Ayarlar'dan
/// her zaman erişilebilir.
///
/// TAMAMEN STATİK: hiçbir API çağrısı yapmaz, `faqItems` (bkz.
/// data/faq_content.dart) sabit bir listedir. Her maddenin kod tabanındaki
/// gerçek bir davranışa karşılık geldiği doğrulanmıştır (frontend + backend
/// grep taraması) — uydurma/tahmini bir açıklama içermez.
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key});

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rol filtresi: bir teknisyen, "Yeni iş emri nasıl oluştururum" gibi
    // kendisiyle alakasız bir soruyu hiç görmemeli — bkz.
    // providers/auth_provider.dart canCreateWorkOrders ile AYNI desen
    // (home_screen.dart FAB'ı).
    final role = context.watch<AuthProvider>().currentUser?.role ?? '';
    final visibleForRole = faqItems
        .where((item) => item.visibleToRoles.contains(role))
        .toList();

    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? visibleForRole
        : visibleForRole
              .where(
                (item) =>
                    item.question.toLowerCase().contains(query) ||
                    item.answer.toLowerCase().contains(query),
              )
              .toList();

    final groups = <String, List<FaqItem>>{};
    for (final category in faqCategoryOrder) {
      final items = filtered.where((item) => item.category == category).toList();
      if (items.isNotEmpty) {
        groups[category] = items;
      }
    }

    return Scaffold(
      appBar: const AppTopBar(title: 'Yardım Merkezi'),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: TextField(
                controller: _searchController,
                textInputAction: TextInputAction.search,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Soru veya cevap içinde ara...',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Aramayı temizle',
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            Expanded(
              child: groups.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.md),
                      child: EmptyState(
                        icon: Icons.search_off,
                        title: 'Aramanızla eşleşen bir soru bulunamadı',
                        subtitle: 'Farklı bir kelimeyle tekrar deneyin.',
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.xl,
                      ),
                      children: [
                        for (final category in groups.keys) ...[
                          _CategoryLabel(category),
                          _FaqCategoryCard(items: groups[category]!),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryLabel extends StatelessWidget {
  final String text;
  const _CategoryLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: 4),
      child: Text(
        text,
        style: AppTextStyles.headingMedium(color: scheme.onSurface),
      ),
    );
  }
}

/// Bir kategorinin tüm sorularını tek bir kartta, aralarında çizgiyle
/// ayrılmış [ExpansionTile] listesi olarak gösterir — settings_screen.dart
/// _ThemeSection'daki (AppCard padding sıfır + ListTile'lar arası Divider)
/// AYNI desen.
class _FaqCategoryCard extends StatelessWidget {
  final List<FaqItem> items;
  const _FaqCategoryCard({required this.items});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _FaqTile(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  final FaqItem item;
  const _FaqTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExpansionTile(
      title: Text(
        item.question,
        style: AppTextStyles.bodyMedium(
          color: scheme.onSurface,
        ).copyWith(fontWeight: FontWeight.w600),
      ),
      iconColor: scheme.primary,
      collapsedIconColor: scheme.onSurfaceVariant,
      childrenPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.answer,
          style: AppTextStyles.bodyMedium(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
