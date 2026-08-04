import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/analytics_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_top_bar.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/user_avatar.dart';
import '../../utils/role_helper.dart';
import 'user_edit_screen.dart';

enum _RoleFilter { all, teknisyen, dispecer, yonetici }

String? _roleFilterValue(_RoleFilter filter) {
  switch (filter) {
    case _RoleFilter.all:
      return null;
    case _RoleFilter.teknisyen:
      return 'teknisyen';
    case _RoleFilter.dispecer:
      return 'dispecer';
    case _RoleFilter.yonetici:
      return 'yonetici';
  }
}

/// Kullanıcı Yönetimi paneli (Modül 8) — YALNIZCA YÖNETİCİ erişebilir.
/// Teknisyen/dispeçer bir şekilde (deep link, state restore) bu ekrana
/// ulaşırsa build() içinde Ana Sayfa'ya geri yönlendirilir (bkz.
/// ARCHITECTURE.md Modül 7 — aynı ikinci koruma katmanı deseni).
class UserManagementListScreen extends StatefulWidget {
  const UserManagementListScreen({super.key});

  @override
  State<UserManagementListScreen> createState() =>
      _UserManagementListScreenState();
}

class _UserManagementListScreenState extends State<UserManagementListScreen> {
  _RoleFilter _filter = _RoleFilter.all;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('UserManagementListScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().fetchAllUsers();
    });
  }

  Future<void> _openCreate() async {
    final created = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const UserEditScreen()));
    if (created == true && mounted) {
      context.read<UserProvider>().fetchAllUsers(
        roleFilter: _roleFilterValue(_filter),
      );
    }
  }

  Future<void> _openEdit(int userId) async {
    final updated = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => UserEditScreen(userId: userId)),
    );
    if (updated == true && mounted) {
      context.read<UserProvider>().fetchAllUsers(
        roleFilter: _roleFilterValue(_filter),
      );
    }
  }

  Future<void> _deactivate(AppUser user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kullanıcıyı Pasifleştir'),
        content: Text(
          '${user.name} pasifleştirilecek, iş emri ataması yapılamayacak. Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Pasifleştir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final provider = context.read<UserProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.deactivateUser(user.id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '${user.name} pasifleştirildi.'
              : (provider.saveErrorMessage ?? 'İşlem başarısız oldu.'),
        ),
      ),
    );
  }

  // Aktifleştirme geri dönülebilir/zararsız bir aksiyondur — pasifleştirmenin
  // aksine onay dialogu gerektirmez (bkz. görev tanımı madde 1).
  Future<void> _reactivate(AppUser user) async {
    final provider = context.read<UserProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final success = await provider.reactivateUser(user.id);
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          success
              ? '${user.name} aktifleştirildi.'
              : (provider.saveErrorMessage ?? 'İşlem başarısız oldu.'),
        ),
      ),
    );
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

    final provider = context.watch<UserProvider>();

    return Scaffold(
      appBar: const AppTopBar(title: 'Kullanıcı Yönetimi'),
      body: SafeArea(
        top: false,
        child: Builder(
          builder: (context) {
            if (provider.isLoadingUsers && provider.users.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.usersErrorMessage != null && provider.users.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 56,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: AppSpacing.sm + 4),
                      Text(
                        provider.usersErrorMessage!,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      AppButton(
                        label: 'Tekrar Dene',
                        onPressed: () => provider.fetchAllUsers(),
                      ),
                    ],
                  ),
                ),
              );
            }

            final query = _searchQuery.trim().toLowerCase();
            final visibleUsers = provider.users.where((u) {
              final matchesRole =
                  _filter == _RoleFilter.all ||
                  u.role == _roleFilterValue(_filter);
              final matchesQuery =
                  query.isEmpty ||
                  u.name.toLowerCase().contains(query) ||
                  u.sicilNo.toLowerCase().contains(query);
              return matchesRole && matchesQuery;
            }).toList();

            return RefreshIndicator(
              onRefresh: () =>
                  provider.fetchAllUsers(roleFilter: _roleFilterValue(_filter)),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  // 12+ kullanıcı olduğunda (seed verisi büyüdükçe) hızlı bulma
                  // için isim/sicil no'ya göre anlık, istemci taraflı filtre —
                  // ayrı bir API isteği gerekmez.
                  TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: const InputDecoration(
                      hintText: 'İsim veya sicil no ile ara...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm + 4),
                  _FilterBar(
                    filter: _filter,
                    onChanged: (f) => setState(() => _filter = f),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (visibleUsers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: AppSpacing.xl),
                      child: Center(
                        child: Text('Bu filtreye uyan kullanıcı yok.'),
                      ),
                    )
                  else
                    ...visibleUsers.map(
                      (user) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _UserRow(
                          user: user,
                          onTap: () => _openEdit(user.id),
                          onDeactivate: () => _deactivate(user),
                          onReactivate: () => _reactivate(user),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Yeni Kullanıcı Ekle',
        onPressed: _openCreate,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final _RoleFilter filter;
  final ValueChanged<_RoleFilter> onChanged;
  const _FilterBar({required this.filter, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filters = <String, _RoleFilter>{
      'Tümü': _RoleFilter.all,
      'Teknisyen': _RoleFilter.teknisyen,
      'Dispeçer': _RoleFilter.dispecer,
      'Yönetici': _RoleFilter.yonetici,
    };

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: filters.entries.map((entry) {
          final isSelected = filter == entry.value;
          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs + 4),
            child: ChoiceChip(
              label: Text(entry.key),
              selected: isSelected,
              showCheckmark: false,
              labelStyle: TextStyle(
                color: isSelected ? scheme.onPrimary : scheme.onSurfaceVariant,
              ),
              onSelected: (_) => onChanged(entry.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final AppUser user;
  final VoidCallback onTap;
  final VoidCallback onDeactivate;
  final VoidCallback onReactivate;
  const _UserRow({
    required this.user,
    required this.onTap,
    required this.onDeactivate,
    required this.onReactivate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Opacity(
      opacity: user.isActive ? 1.0 : 0.55,
      child: AppCard(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                UserAvatar(
                  photoPath: user.photoPath,
                  initials: user.initials,
                  role: user.role,
                  radius: 22,
                ),
                const SizedBox(width: AppSpacing.sm + 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Sicil No: ${user.sicilNo}',
                        style: AppTextStyles.caption(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    RoleBadge(role: user.role, label: roleLabel(user.role)),
                    const SizedBox(height: 6),
                    if (!user.isActive)
                      Text(
                        'Pasif',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.danger(context),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),
            // Aktif/Pasif aksiyonu — biri her zaman diğerinin YERİNE görünür,
            // ikisi asla aynı anda gösterilmez (karışmasın diye, bkz. görev
            // tanımı madde 1).
            Align(
              alignment: Alignment.centerRight,
              child: user.isActive
                  ? AppButton(
                      label: 'Pasifleştir',
                      icon: Icons.block_outlined,
                      variant: AppButtonVariant.destructive,
                      onPressed: onDeactivate,
                    )
                  : AppButton(
                      label: 'Aktifleştir',
                      icon: Icons.check_circle_outline,
                      variant: AppButtonVariant.secondary,
                      onPressed: onReactivate,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
